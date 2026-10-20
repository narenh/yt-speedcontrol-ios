#if DEBUG
import ActivityKit
import UIKit

/// Debug only: launch with `-LiveActivityPreview` to start a sample Live Activity without
/// signing in, then re-alert it every few seconds so the expanded Dynamic Island shows once the
/// app is in the background (go Home or open another app). For checking the island's layout in
/// the simulator. `-LiveActivityPreviewName "<name>"` sets the TV name.
enum LiveActivityPreview {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-LiveActivityPreview") }

    @MainActor
    static func run() {
        let name = UserDefaults.standard.string(forKey: "LiveActivityPreviewName") ?? "Living Room TV"
        let state = SpeedAttributes.ContentState(deviceId: "preview", deviceName: name, speed: 1.5,
                                                 captions: true, connected: true, error: nil)
        let content = ActivityContent(state: state, staleDate: nil)
        var background = UIBackgroundTaskIdentifier.invalid
        background = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(background) }
        Task {
            for activity in Activity<SpeedAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            guard let activity = try? Activity.request(attributes: SpeedAttributes(), content: content, pushType: nil) else { return }
            for _ in 0..<10 {
                try? await Task.sleep(for: .seconds(3))
                let alert = AlertConfiguration(title: "Canopy Control", body: "Preview", sound: .default)
                await activity.update(content, alertConfiguration: alert)
            }
            UIApplication.shared.endBackgroundTask(background)
        }
    }
}
#endif
