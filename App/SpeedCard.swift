import SwiftUI

/// "SPEED", play/pause, and the five speeds as a segmented control (the selected one is the speed).
struct SpeedCard: View {
    let speed: Double
    /// `nil` (the TV hasn't said): shown as playing, since there's a video.
    let playing: Bool?
    let togglePlaying: () -> Void
    let select: (Double) -> Void
    /// Short screens (iPhone SE): tighter padding and a smaller button; same segments.
    var compact = false

    @ScaledMetric(relativeTo: .largeTitle) private var playSize: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var segmentHeight: CGFloat = 44
    @Namespace private var selection

    var body: some View {
        VStack(spacing: compact ? 10 : 14) {
            HStack {
                Text("Speed")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                Spacer()
                playPause
            }
            segments
        }
        .padding(compact ? EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14)
                         : EdgeInsets(top: 18, leading: 16, bottom: 16, trailing: 16))
        .card()
        .animation(.snappy(duration: 0.2), value: speed)
        .animation(.snappy(duration: 0.2), value: playing)
        .sensoryFeedback(.selection, trigger: speed)
    }

    private var playPause: some View {
        let isPlaying = playing ?? true
        let size = playSize * (compact ? 0.82 : 1)
        return Button(action: togglePlaying) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.canopyAccent, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: playing)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }

    private var segments: some View {
        HStack(spacing: 4) {
            ForEach(SpeedAPI.speeds, id: \.self) { option in
                let selected = option == speed
                Button { select(option) } label: {
                    Text(option.speedLabel)
                        .font(.body.weight(selected ? .bold : .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: segmentHeight)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.canopyAccent)
                                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "selected", in: selection)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        // VoiceOver and Voice Control get a standard segmented picker.
        .accessibilityRepresentation {
            Picker("Playback speed", selection: Binding(get: { speed }, set: select)) {
                ForEach(SpeedAPI.speeds, id: \.self) { option in
                    Text("\(option.speedLabel)×").tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

#if DEBUG
#Preview {
    @Previewable @State var speed = 1.5
    @Previewable @State var playing = true
    SpeedCard(speed: speed, playing: playing, togglePlaying: { playing.toggle() }) { speed = $0 }
        .padding()
        .background(Color.groupedBackground)
}
#endif
