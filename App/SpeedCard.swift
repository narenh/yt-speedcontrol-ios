import SwiftUI

/// "SPEED", the current speed, and the five speeds as a segmented control.
struct SpeedCard: View {
    let speed: Double
    let select: (Double) -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var readoutSize: CGFloat = 44
    @ScaledMetric(relativeTo: .title) private var timesSize: CGFloat = 26
    @ScaledMetric(relativeTo: .body) private var segmentHeight: CGFloat = 44
    @Namespace private var selection

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Speed")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(speed.speedLabel)
                        .font(.system(size: readoutSize, weight: .bold))
                        .tracking(-1)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: speed))
                    Text("×")
                        .font(.system(size: timesSize, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
            }
            segments
        }
        .padding(EdgeInsets(top: 18, leading: 16, bottom: 16, trailing: 16))
        .card()
        .animation(.snappy, value: speed)
        .sensoryFeedback(.selection, trigger: speed)
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
    SpeedCard(speed: speed) { speed = $0 }
        .padding()
        .background(Color.groupedBackground)
}
#endif
