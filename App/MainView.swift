import SwiftUI

/// The signed-in screen: the selected TV (tap its name to switch), what it's playing, and the
/// same controls as the Live Activity. Everything else is in Settings.
struct MainView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: TVModel
    @State private var switching = false
    @State private var settings = false
    @State private var pairing = false
    /// Pair a TV was tapped in the switcher: open pairing once the sheet is gone.
    @State private var pairAfterSwitcher = false
    /// Short screens (iPhone SE): tighter controls and spacing.
    @State private var compact = false
    @State private var bottomInset: CGFloat = 0
    private let remote = NowPlayingRemote.shared

    /// When the refresh loop runs: see `.task(id:)` below.
    private struct Refresh: Equatable {
        let active: Bool
        let remote: Bool
    }

    init() {
        _model = State(initialValue: TVModel())
    }

    /// For previews: a model with sample TVs.
    init(model: TVModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        // No scrolling: the header on top, what's playing in all the space left, and the controls
        // pinned to the bottom.
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            header
            if model.emailUnverified { UnverifiedBanner() }
            if let message = model.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Group {
                if let device = model.selected {
                    if device.status == .playing {
                        playing(device)
                    } else {
                        idle(device)
                    }
                } else if model.loaded {
                    noTVs
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, compact ? 4 : 8)
        // Above the home indicator; on phones without one, clear of the screen's edge.
        .padding(.bottom, bottomInset > 0 ? 4 : 16)
        .animation(.snappy, value: model.selected?.status)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: Bool.self) { $0.size.height < 700 } action: { compact = $0 }
        .background {
            // Fills the screen, so it sees the home indicator's inset.
            Color.groupedBackground
                .ignoresSafeArea()
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        }
        // On appear, on foreground, and every ~5 s while active: how changes made from the
        // TV remote show up (and how the running Live Activity catches up). With the Lock Screen
        // remote on, in the background too, for its Now Playing card.
        .task(id: Refresh(active: scenePhase == .active, remote: remote.isOn)) {
            let active = scenePhase == .active
            guard active || remote.isOn else { return }
            if active {
                ActivityPush.shared.resync()
                Task { await model.loadSettings() }
            }
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .sheet(isPresented: $switching, onDismiss: {
            if pairAfterSwitcher {
                pairAfterSwitcher = false
                pairing = true
            }
        }) {
            TVSwitcherSheet(model: model) {
                pairAfterSwitcher = true
                switching = false
            }
        }
        .sheet(isPresented: $settings) { settingsSheet }
        .fullScreenCover(isPresented: $pairing) { pairSheet }
        .alert("Welcome", isPresented: Binding(get: { session.notice != nil }, set: { if !$0 { session.notice = nil } })) {
            Button("OK") { session.notice = nil }
        } message: { Text(session.notice ?? "") }
        .task { await session.loadPerson() }
        #if DEBUG
        .onAppear {
            if Self.previewArg("-PreviewNameStep") { pairing = true }
            if Self.previewArg("-PreviewSwitcher") { switching = true }
            if Self.previewArg("-PreviewSettings") || Self.previewArg("-PreviewRename") || Self.previewArg("-PreviewSkipOff") {
                settings = true
            }
        }
        #endif
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let device = model.selected {
                    Button { switching = true } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(device.name)
                                .font(.largeTitle.bold())
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "chevron.down")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("TV: \(device.name)")
                    .accessibilityHint("Shows your TVs")
                    StatusLine(device: device)
                        .font(.subheadline)
                } else {
                    Text("Canopy Control")
                        .font(.largeTitle.bold())
                }
            }
            Spacer(minLength: 0)
            Button { settings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.card, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    // MARK: Playing

    private func playing(_ device: DeviceInfo) -> some View {
        VStack(spacing: compact ? 12 : 16) {
            NowPlayingCard(device: device)
            VStack(spacing: compact ? 10 : 12) {
                SpeedCard(speed: device.speed, playing: device.playing,
                          togglePlaying: { model.setPlaying(!(device.playing ?? true)) },
                          select: { model.setSpeed($0) }, compact: compact)
                CaptionsButton(on: device.captions, toggle: { model.setCaptions(!device.captions) },
                               compact: compact)
            }
            // Always full size: the now-playing area above gives way instead.
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
        }
        .transition(.opacity)
    }

    // MARK: Empty states

    private func idle(_ device: DeviceInfo) -> some View {
        ContentUnavailableView {
            Label("Nothing playing", systemImage: "play.tv")
        } description: {
            Text("Open YouTube on \(device.name) and start a video. Speed controls show up here.")
        }
        .frame(maxHeight: .infinity)
        .transition(.opacity)
    }

    private var noTVs: some View {
        ContentUnavailableView {
            Label("No TVs yet", systemImage: "tv")
        } description: {
            Text("Pair a TV with the code YouTube shows on it.")
        } actions: {
            Button("Pair a TV") { pairing = true }
                .buttonStyle(.glassProminent)
                .tint(.canopyAccent)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Sheets

    @ViewBuilder
    private var settingsSheet: some View {
        #if DEBUG
        if Self.previewArg("-PreviewRename") {
            SettingsView(model: model, initialPath: [.rename])
        } else if Self.previewArg("-PreviewSkipOff") {
            SettingsView(model: model, initialDialog: .skip)
        } else {
            SettingsView(model: model)
        }
        #else
        SettingsView(model: model)
        #endif
    }

    @ViewBuilder
    private var pairSheet: some View {
        #if DEBUG
        if Self.previewArg("-PreviewNameStep") {
            PairSheet(model: model, paired: DeviceInfo.samples[1])
        } else {
            PairSheet(model: model)
        }
        #else
        PairSheet(model: model)
        #endif
    }

    #if DEBUG
    private static func previewArg(_ name: String) -> Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-MainViewPreview") && args.contains(name)
    }
    #endif
}

/// `403 email_unverified` from the speed server.
private struct UnverifiedBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Confirm your email at account.canopysf.com", systemImage: "envelope.badge")
                .font(.subheadline.weight(.semibold))
            Text("Until then, Canopy Control treats you as signed out.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Link("Open account.canopysf.com", destination: CanopyAccount.website)
                .font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#if DEBUG
#Preview("Playing") {
    MainView(model: .preview())
        .environment(AppSession.preview())
}

#Preview("Idle") {
    MainView(model: .preview(selecting: "preview-2"))
        .environment(AppSession.preview())
}
#endif
