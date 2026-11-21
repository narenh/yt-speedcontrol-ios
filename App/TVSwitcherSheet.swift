import SwiftUI

/// "Your TVs": pick the TV the app (and the Live Activity) controls, or pair another one.
/// Renaming and removing paired TVs are in Settings. For accounts that may use it, a second
/// segment lists the "Sponsor Block only" TVs (no remote, no Live Activity), which can be
/// removed here with a swipe.
struct TVSwitcherSheet: View {
    enum Segment: Hashable { case paired, sponsorBlock }

    let model: TVModel
    /// An add button was tapped: the sheet closes, then the pairing screen opens in that mode.
    let pair: (PairMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat = 320
    @State private var segment: Segment = .paired
    @State private var pendingRemoval: SkipTV?
    /// Each Sponsor Block row's height, so the (non-scrolling) list can be given its height.
    @State private var skipRowHeights: [String: CGFloat] = [:]

    init(model: TVModel, pair: @escaping (PairMode) -> Void, segment: Segment = .paired) {
        self.model = model
        self.pair = pair
        _segment = State(initialValue: segment)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PreviewSkipSegment") { _segment = State(initialValue: .sponsorBlock) }
        #endif
    }

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

                if model.skipAllowed {
                    Picker("TV type", selection: $segment) {
                        Text("Paired TVs").tag(Segment.paired)
                        Text("Sponsor Block").tag(Segment.sponsorBlock)
                    }
                    .pickerStyle(.segmented)
                }

                if !model.skipAllowed || segment == .paired {
                    if !model.devices.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(model.devices.enumerated()), id: \.element.id) { index, device in
                                if index > 0 { Divider().padding(.leading, 64) }
                                row(device)
                            }
                        }
                        .card()
                    }
                } else {
                    skipList
                }

                VStack(spacing: 12) {
                    addButton("Pair a TV", color: .canopyLink) { pair(.paired) }
                    if model.skipAllowed {
                        addButton("Sponsor Block Only", color: .canopyBlue) { pair(.sponsorBlockOnly) }
                    }
                }
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
        .alert("Remove \(pendingRemoval?.name ?? "this TV")?", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let tv = pendingRemoval { model.removeSkipTV(tv.id) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("You'll need a new TV code to add it again.")
        }
    }

    private func addButton(_ title: LocalizedStringKey, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: "plus").fontWeight(.semibold)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card()
    }

    // MARK: Sponsor Block only

    @ViewBuilder
    private var skipList: some View {
        if model.skipTVs.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.canopyBlue)
                    .accessibilityHidden(true)
                Text("No Sponsor Block TVs")
                    .font(.body.weight(.semibold))
                Text("A Sponsor Block only TV skips sponsors and ads, but Canopy Control can't control it or show it in Live Activities. Handy for a TV that isn't yours.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .card()
        } else {
            // A List for swipe actions; it doesn't scroll and is sized to its rows, so the
            // sheet's detent still follows the measured content.
            List {
                ForEach(model.skipTVs) { tv in
                    skipRow(tv)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.card)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 64 }
                        .listRowSeparator(tv.id == model.skipTVs.last?.id ? .hidden : .automatic, edges: .bottom)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Remove", systemImage: "trash", role: .destructive) { pendingRemoval = tv }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .environment(\.defaultMinListRowHeight, 0)
            .frame(height: model.skipTVs.reduce(0) { $0 + (skipRowHeights[$1.id] ?? 60) })
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func skipRow(_ tv: SkipTV) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.canopyBlue)
                .frame(width: 36, height: 36)
                .background(Color.canopyBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tv.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Skipping sponsors")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { skipRowHeights[tv.id] = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Remove") { pendingRemoval = tv }
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
#Preview("Paired TVs") {
    Color.gray.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            TVSwitcherSheet(model: .preview()) { _ in }
        }
}

#Preview("Sponsor Block") {
    Color.gray.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            TVSwitcherSheet(model: .preview(), pair: { _ in }, segment: .sponsorBlock)
        }
}

#Preview("Sponsor Block, empty") {
    Color.gray.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            TVSwitcherSheet(model: .preview(skipTVs: []), pair: { _ in }, segment: .sponsorBlock)
        }
}

#Preview("Not allowed") {
    Color.gray.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            TVSwitcherSheet(model: .preview(skipTVs: [], skipAllowed: false)) { _ in }
        }
}
#endif
