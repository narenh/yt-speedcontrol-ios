import ActivityKit
import Foundation
import Observation

/// The signed-in person's TVs, the selected one, and the Live Activity that follows it.
@MainActor
@Observable
final class TVModel {
    static let selectedKey = "selectedDevice"

    private(set) var devices: [DeviceInfo] = []
    private(set) var loaded = false
    private(set) var activityRunning = SpeedActivity.isRunning
    /// The speed server needs a confirmed Canopy Account email (`403 email_unverified`).
    private(set) var emailUnverified = false
    /// The last error, from the server's `detail`.
    var message: String?
    /// A control call in flight, so the buttons don't double-fire.
    private(set) var busy = false
    /// TVs with a skip-sponsors change in flight: their toggle waits for the server's answer.
    private(set) var skipPending: Set<String> = []
    /// Skip-sponsors changes started or finished per TV, so an answer that left the server
    /// before one of them landed doesn't put the old value back.
    @ObservationIgnored private var skipChanges: [String: Int] = [:]
    #if DEBUG
    /// Sample TVs, no server: for previews.
    @ObservationIgnored private var isPreview = false
    #endif

    var selectedId: String = UserDefaults.standard.string(forKey: selectedKey) ?? "" {
        didSet {
            UserDefaults.standard.set(selectedId, forKey: Self.selectedKey)
            if selectedId != oldValue, !following, let device = selected {
                // The activity follows the selected TV, updated in place.
                Task {
                    await SpeedActivity.show(device, switching: true)
                    ActivityPush.shared.activityTVChanged()
                }
            }
        }
    }

    /// Selecting the TV of a newly adopted activity, which already shows it.
    @ObservationIgnored private var following = false
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .liveActivityTVChanged, object: nil, queue: .main) { [weak self] note in
            guard let deviceId = note.object as? String else { return }
            MainActor.assumeIsolated { self?.follow(deviceId) }
        }
    }

    /// A new activity (usually started by the server's push) is for this TV: select it.
    private func follow(_ deviceId: String) {
        following = true
        selectedId = deviceId
        following = false
        activityRunning = SpeedActivity.isRunning
    }

    var selected: DeviceInfo? { devices.first { $0.id == selectedId } }

    // MARK: Loading

    func refresh() async {
        #if DEBUG
        if isPreview { return }
        #endif
        let changes = skipChanges
        do {
            let list = try await SpeedAPI.devices()
            devices = list.map { keepingSkip($0, since: changes) }
            loaded = true
            emailUnverified = false
            if selected == nil { selectedId = list.first?.id ?? "" }
            if let device = selected {
                await SpeedActivity.show(device, switching: true)
                ActivityPush.shared.activityTVChanged()
            } else if SpeedActivity.isRunning {
                await SpeedActivity.end()
            }
        } catch {
            handle(error)
        }
        activityRunning = SpeedActivity.isRunning
    }

    // MARK: Controls

    func setSpeed(_ speed: Double) async {
        guard let id = selected?.id else { return }
        await control { try await SpeedAPI.setSpeed(speed, device: id) }
    }

    func setCaptions(_ on: Bool) async {
        guard let id = selected?.id else { return }
        await control { try await SpeedAPI.setCaptions(on, device: id) }
    }

    private func control(_ call: () async throws -> DeviceInfo) async {
        do {
            try await apply(call)
        } catch {
            handle(error)
        }
    }

    /// Runs a call that answers with one TV, which then replaces it in the list and the Live
    /// Activity. Throws the error instead of showing it.
    private func apply(_ call: () async throws -> DeviceInfo) async throws {
        busy = true
        defer { busy = false }
        let changes = skipChanges
        replace(keepingSkip(try await call(), since: changes))
        message = nil
    }

    private func replace(_ device: DeviceInfo) {
        if let i = devices.firstIndex(where: { $0.id == device.id }) {
            devices[i] = device
        } else {
            devices.append(device)
        }
        Task { await SpeedActivity.show(device) }
    }

    /// Turns skipping sponsors on or off for the selected TV: the toggle flips right away, then
    /// takes the server's answer. An error puts it back and shows the server's `detail`.
    func setSkipSponsors(_ on: Bool) {
        guard let i = devices.firstIndex(where: { $0.id == selectedId }),
              let before = devices[i].skipSponsors, before != on else { return }
        let id = devices[i].id
        guard !skipPending.contains(id) else { return }
        devices[i].skipSponsors = on
        skipPending.insert(id)
        skipChanges[id, default: 0] += 1
        Task {
            defer {
                skipPending.remove(id)
                skipChanges[id, default: 0] += 1
            }
            do {
                replace(try await SpeedAPI.setSkipSponsors(on, device: id))
                message = nil
            } catch {
                if let j = devices.firstIndex(where: { $0.id == id }) { devices[j].skipSponsors = before }
                handle(error)
            }
        }
    }

    /// The server's answer for a TV, keeping the app's skip-sponsors value if a change to it was
    /// in flight or landed while this answer was on its way (`changes`: `skipChanges` when it was asked for).
    private func keepingSkip(_ device: DeviceInfo, since changes: [String: Int]) -> DeviceInfo {
        guard skipPending.contains(device.id) || skipChanges[device.id] != changes[device.id],
              let local = devices.first(where: { $0.id == device.id }) else { return device }
        var device = device
        device.skipSponsors = local.skipSponsors
        return device
    }

    /// Renames the selected TV (`nil`: back to the TV's own name). The list and the Live Activity
    /// take the answer right away; the server's push says the same a moment later.
    func renameSelected(to name: String?) async {
        guard let id = selected?.id else { return }
        do {
            try await rename(device: id, to: name)
        } catch {
            handle(error)
        }
    }

    /// Renames one TV, like `renameSelected`, but throws the server's `detail` (for the pair
    /// sheet's name step) instead of showing it on the main screen.
    func rename(device id: String, to name: String?) async throws {
        try await apply { try await SpeedAPI.rename(device: id, name: name) }
    }

    // MARK: Pairing and removing

    /// Throws the server's `detail` so the pair sheet can show it. Returns the new TV, with the
    /// name it reported (or the custom name it already had, when paired again).
    @discardableResult
    func pair(code: String) async throws -> DeviceInfo {
        do {
            let device = try await SpeedAPI.pair(code: code)
            replace(device)
            selectedId = device.id
            message = nil
            return device
        } catch {
            if let api = error as? SpeedAPIError, api.isEmailUnverified { emailUnverified = true }
            throw error
        }
    }

    func removeSelected() async {
        guard let id = selected?.id else { return }
        do {
            try await SpeedAPI.remove(device: id)
            devices.removeAll { $0.id == id }
            selectedId = devices.first?.id ?? ""
            if devices.isEmpty { await endActivity() }
            message = nil
        } catch {
            handle(error)
        }
    }

    // MARK: Live Activity

    func startActivity() async {
        guard let device = selected else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "Live Activities are turned off for Canopy Control in Settings."
            return
        }
        do {
            // Same registration path as a push-started activity.
            let activity = try await SpeedActivity.start(device)
            ActivityPush.shared.adopt(activity, select: false)
            ActivityPush.shared.activityTVChanged()
            message = nil
        } catch {
            message = error.localizedDescription
        }
        activityRunning = SpeedActivity.isRunning
    }

    func endActivity() async {
        await SpeedActivity.end()
        activityRunning = false
    }

    // MARK: Errors

    private func handle(_ error: Error) {
        if let api = error as? SpeedAPIError {
            // 401: SpeedAPI has deleted the token, and the session goes back to sign-in.
            if api.isSignedOut { return }
            if api.isEmailUnverified {
                emailUnverified = true
                return
            }
        }
        if (error as? URLError)?.code == .cancelled { return }
        message = error.localizedDescription
    }

    #if DEBUG
    /// Sample TVs for previews and the `-MainViewPreview` launch argument. Never calls the server
    /// to load; a toggle still tries, and its error reverts it.
    static func preview(_ devices: [DeviceInfo] = DeviceInfo.samples) -> TVModel {
        let model = TVModel()
        model.isPreview = true
        model.devices = devices
        model.loaded = true
        model.following = true
        model.selectedId = devices.first?.id ?? ""
        model.following = false
        return model
    }
    #endif

    func reset() {
        devices = []
        loaded = false
        emailUnverified = false
        message = nil
    }
}

#if DEBUG
extension DeviceInfo {
    static let samples: [DeviceInfo] = [
        DeviceInfo(id: "preview-1", name: "Living Room TV", connected: true, videoId: "dQw4w9WgXcQ",
                   speed: 1.5, captions: true, skipSponsors: true),
        DeviceInfo(id: "preview-2", name: "Bedroom TV", connected: false, videoId: nil,
                   speed: 1, captions: false),
    ]
}
#endif
