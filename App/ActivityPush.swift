import ActivityKit
import Foundation
import os

extension Notification.Name {
    /// Posted on the main queue when the app adopts a new Live Activity (usually one the server
    /// started by push). `object` is the activity's TV id; the app selects that TV.
    static let liveActivityTVChanged = Notification.Name("liveActivityTVChanged")
}

/// Registers this iPhone with the speed server so it can start and update the Live Activity by
/// push (`PUT /installs/{install_id}`), and keeps the app down to one activity.
///
/// - The push-to-start token goes up while signed in, so the server can start an activity when
///   one of the person's TVs starts playing, even with the app closed.
/// - The current activity's push token goes up with the TV it shows, so the server can push that
///   TV's speed, captions, connection and name to it.
/// - A new activity (started by push, or from the app) becomes the current one and ends the rest.
///
/// Started from the App's init, so it runs when the system launches the app in the background
/// for a push-started activity. Until the server has `/installs`, every PUT fails: failures are
/// logged and otherwise ignored.
@MainActor
final class ActivityPush {
    static let shared = ActivityPush()

    private static let installKey = "installId"
    private static let log = Logger(subsystem: "com.canopysf.CanopyControl", category: "push")

    /// The APNs environment of this build's tokens. It follows the signing, not the build
    /// configuration: a development profile (Xcode, devicectl, ota-build's development exports,
    /// Release ones too) says `aps-environment: development`, so its tokens are sandbox ones. Ad hoc
    /// and enterprise profiles say `production`, and App Store builds have no profile at all.
    private static let environment: String = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              // The profile is a signed CMS message with the plist inside it as plain XML.
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil),
              let entitlements = (plist as? [String: Any])?["Entitlements"] as? [String: Any],
              entitlements["aps-environment"] as? String == "development"
        else { return "production" }
        return "sandbox"
    }()

    /// This app install, as the server knows it. A new one after signing out.
    private static var installId: String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: installKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: installKey)
        return id
    }

    private var started = false
    private var pushToStartToken: String?
    /// Activity id → its push token (hex).
    private var activityTokens: [String: String] = [:]
    /// What the server was last sent, so repeats are skipped: the push-to-start token, and
    /// "token|device" for the activity.
    private var sentPushToStart: String?
    private var sentActivity: String?
    /// Activity id → the tasks watching its push token and state.
    private var observers: [String: [Task<Void, Never>]] = [:]
    /// Activities already running at launch, handled there; `activityUpdates` may repeat them.
    private var runningAtLaunch: Set<String> = []
    /// The PUTs, one after another, so the server sees them in order.
    private var queue: Task<Void, Never>?

    /// The adopted activity (in UserDefaults so `SpeedActivity.current` and the next launch see it).
    private var currentId: String? {
        get { UserDefaults.standard.string(forKey: SpeedActivity.currentKey) }
        set { UserDefaults.standard.set(newValue, forKey: SpeedActivity.currentKey) }
    }

    private var signedIn: Bool { TokenStore.token != nil }

    // MARK: Launch

    func start() {
        guard !started else { return }
        started = true

        // Activities started while the app wasn't running (by push, or before a relaunch).
        let running = Activity<SpeedAttributes>.activities.filter(\.isLive)
        runningAtLaunch = Set(running.map(\.id))
        if let newest = running.last(where: { $0.id != currentId }) {
            adopt(newest, select: true)
        } else if let current = running.first {
            adopt(current, select: false)
        } else if currentId != nil {
            // It ended while the app wasn't running (e.g. swiped away on the Lock Screen).
            currentId = nil
            put(["activity": NSNull()], what: "no activity")
        }

        Task {
            for await activity in Activity<SpeedAttributes>.activityUpdates {
                if runningAtLaunch.remove(activity.id) != nil { continue }
                adopt(activity, select: true)
            }
        }

        if let token = Activity<SpeedAttributes>.pushToStartToken { pushToStartToken = token.hex }
        sendPushToStart()
        Task {
            for await token in Activity<SpeedAttributes>.pushToStartTokenUpdates {
                pushToStartToken = token.hex
                sendPushToStart()
            }
        }
    }

    // MARK: The current activity

    /// Makes this activity the current one: ends any others, sends its token, and (`select`)
    /// selects its TV in the app. Does nothing if it already is.
    func adopt(_ activity: Activity<SpeedAttributes>, select: Bool) {
        guard activity.isLive else { return }
        guard signedIn else {
            // Its buttons can't work signed out.
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        if currentId == activity.id, observers[activity.id] != nil { return }

        currentId = activity.id
        for other in Activity<SpeedAttributes>.activities where other.id != activity.id {
            stopObserving(other.id)
            Task { await other.end(nil, dismissalPolicy: .immediate) }
        }
        observe(activity)
        if let token = activity.pushToken { activityTokens[activity.id] = token.hex }
        sendActivity()

        if select {
            let deviceId = activity.content.state.deviceId
            UserDefaults.standard.set(deviceId, forKey: TVModel.selectedKey)
            NotificationCenter.default.post(name: .liveActivityTVChanged, object: deviceId)
        }
    }

    /// The app changed which TV the activity shows (switching TVs updates it in place): tell
    /// the server, with the same token.
    func activityTVChanged() {
        sendActivity()
    }

    private func observe(_ activity: Activity<SpeedAttributes>) {
        let id = activity.id
        let tokens = Task {
            for await token in activity.pushTokenUpdates {
                activityTokens[id] = token.hex
                if id == currentId { sendActivity() }
            }
        }
        let states = Task {
            for await state in activity.activityStateUpdates where state == .ended || state == .dismissed {
                ended(id)
                return
            }
        }
        observers[id] = [tokens, states]
    }

    private func stopObserving(_ id: String) {
        observers.removeValue(forKey: id)?.forEach { $0.cancel() }
        activityTokens[id] = nil
    }

    /// Unless a newer activity has replaced it, the server stops pushing to this one.
    private func ended(_ id: String) {
        stopObserving(id)
        guard id == currentId else { return }
        currentId = nil
        sentActivity = nil
        put(["activity": NSNull()], what: "no activity")
    }

    // MARK: Sending

    private func sendPushToStart(force: Bool = false) {
        guard signedIn, let token = pushToStartToken, force || token != sentPushToStart else { return }
        sentPushToStart = token
        put(["push_to_start_token": token], what: "push-to-start token")
    }

    private func sendActivity(force: Bool = false) {
        guard signedIn, let id = currentId,
              let activity = Activity<SpeedAttributes>.activities.first(where: { $0.id == id }), activity.isLive,
              let token = activityTokens[id] ?? activity.pushToken?.hex
        else { return }
        let deviceId = activity.content.state.deviceId
        let key = "\(token)|\(deviceId)"
        guard force || key != sentActivity else { return }
        sentActivity = key
        put(["activity": ["token": token, "device_id": deviceId]], what: "activity token for TV \(deviceId)")
    }

    /// Adds `environment` and queues the PUT behind any earlier ones. Never logs tokens.
    private func put(_ fields: [String: Any], what: String) {
        var body = fields
        body["environment"] = Self.environment
        guard let json = try? JSONSerialization.data(withJSONObject: body) else { return }
        let install = Self.installId
        let previous = queue
        queue = Task {
            await previous?.value
            guard TokenStore.token != nil else { return }
            do {
                try await SpeedAPI.putInstall(install, json: json)
                Self.log.info("PUT /installs: \(what, privacy: .public)")
            } catch {
                Self.log.error("PUT /installs (\(what, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Session

    /// On coming to the foreground: send everything again, in case an earlier PUT failed.
    func resync() {
        if let id = currentId, !Activity<SpeedAttributes>.activities.contains(where: { $0.id == id && $0.isLive }) {
            ended(id)
        }
        sendPushToStart(force: true)
        sendActivity(force: true)
    }

    func didSignIn() {
        if let token = Activity<SpeedAttributes>.pushToStartToken { pushToStartToken = token.hex }
        sendPushToStart(force: true)
        sendActivity(force: true)
    }

    /// The token is gone (sign-out, or a 401 anywhere): stop tracking activities. The caller
    /// ends them; they're not reported to the server, which can't be reached without a token.
    func didSignOut() {
        for id in Array(observers.keys) { stopObserving(id) }
        currentId = nil
        sentActivity = nil
        sentPushToStart = nil
    }

    /// Signing out on purpose: `DELETE /installs/{id}` while there's still a token, end all
    /// activities, and use a new install id next time.
    func signOut() async {
        didSignOut()
        await queue?.value
        if signedIn {
            do {
                try await SpeedAPI.deleteInstall(Self.installId)
                Self.log.info("DELETE /installs")
            } catch {
                Self.log.error("DELETE /installs failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        UserDefaults.standard.removeObject(forKey: Self.installKey)
        await SpeedActivity.end()
    }
}

private extension Activity where Attributes == SpeedAttributes {
    var isLive: Bool { activityState != .ended && activityState != .dismissed }
}

private extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
