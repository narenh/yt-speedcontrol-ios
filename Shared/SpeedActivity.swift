import ActivityKit
import AppIntents
import Foundation

/// There's at most one activity, and it shows the TV selected in the app. The TV lives in the
/// state rather than the attributes, so switching TVs updates the activity in place.
/// The server sends this same shape in its pushes (attributes `{}`, content-state keys
/// `deviceId, deviceName, speed, captions, playing, connected`, no `error`): don't rename anything.
struct SpeedAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var deviceId: String
        var deviceName: String
        var speed: Double
        var captions: Bool
        var connected: Bool
        /// Optional: older servers don't send it, and it's `null` until the TV has said.
        var playing: Bool?
        var error: String?
    }
}

extension SpeedAttributes.ContentState {
    init(_ info: DeviceInfo) {
        self.init(deviceId: info.id, deviceName: info.name, speed: info.speed,
                  captions: info.captions, connected: info.connected, playing: info.playing, error: nil)
    }
}

// MARK: - Intents (compiled into both targets; the system runs them in the app's process)

struct SetSpeedIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Set Playback Speed"
    static let isDiscoverable = false

    @Parameter(title: "Speed") var speed: Double
    @Parameter(title: "TV") var deviceId: String

    init() {}
    init(speed: Double, deviceId: String) {
        self.speed = speed
        self.deviceId = deviceId
    }

    func perform() async throws -> some IntentResult {
        let autoCaptions = AccountSettings.saved
        await SpeedActivity.apply(deviceId: deviceId, change: {
            $0.speed = speed
            $0.captions = AccountSettings.captions(afterSpeed: speed, autoCaptions: autoCaptions, current: $0.captions)
        }) {
            try await SpeedAPI.setSpeed(speed, device: deviceId)
        }
        return .result()
    }
}

struct SetCaptionsIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Set Captions"
    static let isDiscoverable = false

    @Parameter(title: "On") var on: Bool
    @Parameter(title: "TV") var deviceId: String

    init() {}
    init(on: Bool, deviceId: String) {
        self.on = on
        self.deviceId = deviceId
    }

    func perform() async throws -> some IntentResult {
        await SpeedActivity.apply(deviceId: deviceId, change: { $0.captions = on }) {
            try await SpeedAPI.setCaptions(on, device: deviceId)
        }
        return .result()
    }
}

struct SetPlayingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let isDiscoverable = false

    @Parameter(title: "Play") var play: Bool
    @Parameter(title: "TV") var deviceId: String

    init() {}
    init(play: Bool, deviceId: String) {
        self.play = play
        self.deviceId = deviceId
    }

    func perform() async throws -> some IntentResult {
        await SpeedActivity.apply(deviceId: deviceId, change: { $0.playing = play }) {
            try await SpeedAPI.setPlaying(play, device: deviceId)
        }
        return .result()
    }
}

// MARK: - Activity management

enum SpeedActivity {
    /// UserDefaults key for the id of the activity the app adopted last (the app's ActivityPush
    /// keeps it). If a push started a second one that the app hasn't caught up with yet, this
    /// still picks the one the app knows about.
    static let currentKey = "currentActivity"

    /// The one running activity, if any.
    static var current: Activity<SpeedAttributes>? {
        let running = Activity<SpeedAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
        let adopted = UserDefaults.standard.string(forKey: currentKey)
        return running.first { $0.id == adopted } ?? running.first
    }

    static var isRunning: Bool { current != nil }

    /// Taps on the activity's buttons so far: only the latest one's answer is shown.
    @MainActor private static var taps = 0

    /// Runs a server call for a tap on the activity. `change` shows on it right away; the server's
    /// answer then replaces it, or an error puts the old speed, captions and playing back and says why.
    /// Answers to earlier taps are dropped, so quick taps don't flicker back through them.
    /// A signed-out answer ends the activity: its buttons can't work until the app signs in again.
    @MainActor
    static func apply(deviceId: String, change: (inout SpeedAttributes.ContentState) -> Void,
                      _ call: () async throws -> DeviceInfo) async {
        taps += 1
        let tap = taps
        var before: SpeedAttributes.ContentState?
        if let activity = current, activity.content.state.deviceId == deviceId {
            before = activity.content.state
            var state = activity.content.state
            change(&state)
            state.error = nil
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        do {
            let info = try await call()
            guard tap == taps else { return }
            await show(info)
        } catch {
            guard let activity = current, activity.content.state.deviceId == deviceId else { return }
            var state = activity.content.state
            if let before {
                state.speed = before.speed
                state.captions = before.captions
                state.playing = before.playing
            }
            if let api = error as? SpeedAPIError, api.isSignedOut {
                TokenStore.delete()
                state.error = "Signed out. Open Canopy Control to sign in."
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .default)
            } else if tap == taps {
                state.error = error.localizedDescription
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        }
    }

    /// Starts the activity for this TV, or points the running one at it. Push updates are on
    /// (`.token`): the app sends the activity's push token to the server.
    @discardableResult
    static func start(_ device: DeviceInfo) async throws -> Activity<SpeedAttributes> {
        if let activity = current {
            await show(device, switching: true)
            return activity
        }
        return try Activity.request(
            attributes: SpeedAttributes(),
            content: ActivityContent(state: .init(device), staleDate: nil),
            pushType: .token
        )
    }

    /// Updates the running activity with this TV's state. Unless `switching`, only when the
    /// activity is already showing this TV, and only when something changed.
    static func show(_ device: DeviceInfo, switching: Bool = false) async {
        guard let activity = current else { return }
        guard switching || activity.content.state.deviceId == device.id else { return }
        let state = SpeedAttributes.ContentState(device)
        guard state != activity.content.state else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    static func end() async {
        for activity in Activity<SpeedAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
