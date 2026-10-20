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
                .padding(14)
                .activityBackgroundTint(.black.opacity(0.45))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.deviceName, systemImage: "tv")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CaptionsButton(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        SpeedReadout(context: context)
                        SpeedButtons(context: context)
                    }
                }
            } compactLeading: {
                Image(systemName: "play.tv.fill").foregroundStyle(.red)
            } compactTrailing: {
                Text("\(context.state.speed.speedLabel)×")
                    .monospacedDigit()
                    .foregroundStyle(.red)
            } minimal: {
                Text(context.state.speed.speedLabel)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.red)
            }
        }
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
