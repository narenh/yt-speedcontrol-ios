import SwiftUI

/// "Your TVs": pick the TV the app (and the Live Activity) controls, or pair another one.
/// Renaming and removing are in Settings.
struct TVSwitcherSheet: View {
    let model: TVModel
    /// Pair a TV was tapped: the sheet closes, then the pairing screen opens.
    let pair: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat = 320

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("Your TVs")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.canopyLink)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 4)

                if !model.devices.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(model.devices.enumerated()), id: \.element.id) { index, device in
                            if index > 0 { Divider().padding(.leading, 64) }
                            row(device)
                        }
                    }
                    .card()
                }

                Button(action: pair) {
                    Label {
                        Text("Pair a TV")
                    } icon: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.canopyLink)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .card()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.groupedBackground)
    }

    private func row(_ device: DeviceInfo) -> some View {
        let selected = device.id == model.selectedId
        return Button {
            model.selectedId = device.id
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "tv")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(selected ? Color.canopyLink : Color.secondary)
                    .frame(width: 36, height: 36)
                    .background(selected ? Color.canopyLink.opacity(0.12) : Color(.tertiarySystemFill),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    StatusLine(device: device, style: .row)
                        .font(.footnote)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.canopyLink)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if DEBUG
#Preview {
    Color.gray.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            TVSwitcherSheet(model: .preview()) {}
        }
}
#endif
