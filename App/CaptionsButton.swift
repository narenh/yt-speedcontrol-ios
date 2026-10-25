import SwiftUI

/// Full-width captions toggle: dark with a light "On" pill when on, a plain card with "Off" when off.
struct CaptionsButton: View {
    let on: Bool
    let toggle: () -> Void
    /// Short screens (iPhone SE): a little less height and padding.
    var compact = false

    @ScaledMetric(relativeTo: .headline) private var minHeight: CGFloat = 64

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: compact ? 12 : 14) {
                Image(systemName: on ? "captions.bubble.fill" : "captions.bubble")
                    .font(.title2)
                    .symbolRenderingMode(.monochrome)
                    .accessibilityHidden(true)
                Text("Captions")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(on ? "On" : "Off")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(on ? Color.captionsOnFill : Color.secondary)
                    .background(on ? Color.captionsOnText : Color(.tertiarySystemFill), in: Capsule())
                    .contentTransition(.opacity)
            }
            .foregroundStyle(on ? Color.captionsOnText : Color.primary)
            .padding(.horizontal, compact ? 18 : 20)
            .frame(minHeight: minHeight * (compact ? 52 / 64 : 1))
            .background(on ? Color.captionsOnFill : Color.card, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: on)
        .sensoryFeedback(.impact(weight: .light), trigger: on)
        .accessibilityLabel("Captions")
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: compact ? 18 : 20, style: .continuous)
    }
}

#if DEBUG
#Preview {
    @Previewable @State var on = true
    VStack {
        CaptionsButton(on: on) { on.toggle() }
        CaptionsButton(on: !on) { on.toggle() }
    }
    .padding()
    .background(Color.groupedBackground)
}
#endif
