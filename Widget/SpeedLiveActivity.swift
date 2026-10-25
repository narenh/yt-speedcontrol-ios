import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct SpeedWidgetBundle: WidgetBundle {
    var body: some Widget { SpeedLiveActivity() }
}

struct SpeedLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpeedAttributes.self) { context in
            LockScreenView(context: context)
                .quickUpdates(context)
                .padding(14)
                .activityBackgroundTint(.black.opacity(0.45))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // The expanded island's corners are deeply rounded: leading and trailing drop below
                // the camera when they don't fit beside it, and the bottom row sits inside the
                // content margins so the outer buttons' corners clear the curve.
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.deviceName, systemImage: "tv")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CaptionsButton(context: context)
                        .quickUpdates(context)
                        .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        SpeedReadout(context: context)
                        SpeedButtons(context: context)
                    }
                    .padding(.horizontal, 6)
                    .quickUpdates(context)
                }
            } compactLeading: {
                Image(systemName: "play.tv.fill").foregroundStyle(.red)
            } compactTrailing: {
                Text("\(context.state.speed.speedLabel)×")
                    .monospacedDigit()
                    .foregroundStyle(.red)
                    .quickUpdates(context)
            } minimal: {
                Text(context.state.speed.speedLabel)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.red)
                    .quickUpdates(context)
            }
            .contentMargins(.horizontal, 24, for: .expanded)
        }
    }
}

private extension View {
    /// The system's default animation for an update is a slow crossfade, which makes a tap feel
    /// laggy: changes snap in quickly instead.
    func quickUpdates(_ context: ActivityViewContext<SpeedAttributes>) -> some View {
        animation(.snappy(duration: 0.15), value: context.state)
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<SpeedAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "play.tv.fill").foregroundStyle(.red)
                Text(context.state.deviceName).font(.subheadline.weight(.semibold))
                Spacer()
                Circle()
                    .fill(context.state.connected ? .green : .gray)
                    .frame(width: 7, height: 7)
                Text(context.state.connected ? "YouTube" : "Not connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom) {
                SpeedReadout(context: context)
                Spacer()
                CaptionsButton(context: context)
            }
            SpeedButtons(context: context)
        }
        .foregroundStyle(.white)
    }
}

private struct SpeedReadout: View {
    let context: ActivityViewContext<SpeedAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(context.state.speed.speedLabel)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("×").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            }
            if let error = context.state.error {
                Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(1)
            }
        }
    }
}

private struct SpeedButtons: View {
    let context: ActivityViewContext<SpeedAttributes>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SpeedAPI.speeds, id: \.self) { speed in
                let selected = speed == context.state.speed
                Button(intent: SetSpeedIntent(speed: speed, deviceId: context.state.deviceId)) {
                    Text(speed.speedLabel)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(selected ? Color.red : Color.white.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CaptionsButton: View {
    let context: ActivityViewContext<SpeedAttributes>

    var body: some View {
        let on = context.state.captions
        Button(intent: SetCaptionsIntent(on: !on, deviceId: context.state.deviceId)) {
            Label("Captions", systemImage: on ? "captions.bubble.fill" : "captions.bubble")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(on ? Color.white : Color.white.opacity(0.14), in: Capsule())
                .foregroundStyle(on ? .black : .white)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: SpeedAttributes()) {
    SpeedLiveActivity()
} contentStates: {
    SpeedAttributes.ContentState(deviceId: "preview", deviceName: "Living Room TV", speed: 1.5,
                                 captions: true, connected: true, error: nil)
    SpeedAttributes.ContentState(deviceId: "preview", deviceName: "Bedroom Sony Bravia XR", speed: 1,
                                 captions: false, connected: true, error: nil)
}
