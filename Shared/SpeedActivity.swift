import ActivityKit
import AppIntents
import Foundation

struct SpeedAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var speed: Double
        var captions: Bool
        var connected: Bool
        var error: String?
    }

    var deviceId: String
    var deviceName: String
}

extension SpeedAttributes.ContentState {
    init(_ info: DeviceInfo) {
        self.init(speed: info.speed, captions: info.captions, connected: info.connected, error: nil)
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
        await SpeedActivity.apply(deviceId: deviceId) {
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
        await SpeedActivity.apply(deviceId: deviceId) {
            try await SpeedAPI.setCaptions(on, device: deviceId)
        }
        return .result()
    }
}

// MARK: - Activity management

enum SpeedActivity {
    static func current(for deviceId: String) -> Activity<SpeedAttributes>? {
        Activity<SpeedAttributes>.activities.first { $0.attributes.deviceId == deviceId }
    }

    static var running: [Activity<SpeedAttributes>] { Activity<SpeedAttributes>.activities }

    /// Runs a server call and pushes the result (or its error) into the device's Live Activity.
    static func apply(deviceId: String, _ call: () async throws -> DeviceInfo) async {
        guard let activity = current(for: deviceId) else { return }
        var state = activity.content.state
        do {
            state = .init(try await call())
        } catch {
            state.error = error.localizedDescription
        }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    static func start(_ device: DeviceInfo) throws {
        guard current(for: device.id) == nil else { return }
        _ = try Activity.request(
            attributes: SpeedAttributes(deviceId: device.id, deviceName: device.name),
            content: ActivityContent(state: .init(device), staleDate: nil)
        )
    }

    static func end(_ deviceId: String) async {
        await current(for: deviceId)?.end(nil, dismissalPolicy: .immediate)
    }

    /// Pull fresh state for every running activity (called when the app comes to the foreground).
    static func syncAll() async {
        guard !running.isEmpty, let devices = try? await SpeedAPI.devices() else { return }
        for activity in running {
            guard let info = devices.first(where: { $0.id == activity.attributes.deviceId }) else { continue }
            await activity.update(ActivityContent(state: .init(info), staleDate: nil))
        }
    }
}
