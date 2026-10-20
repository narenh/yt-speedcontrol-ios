import SwiftUI

/// The signed-in screen: pick a TV, then the same controls as the Live Activity.
struct MainView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = TVModel()
    @State private var pairing = false
    @State private var confirmRemove = false
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !model.devices.isEmpty { tvSwitcher }
                    if model.emailUnverified { UnverifiedBanner() }
                    if let device = model.selected {
                        controls(device)
                    } else if model.loaded {
                        emptyState
                    } else {
                        ProgressView().padding(.top, 80)
                    }
                    if let message = model.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
            .navigationTitle("Canopy Control")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbar }
            .refreshable { await model.refresh() }
            // On appear, on foreground, and every ~5 s while active: how changes made from the
            // TV remote show up (and how the running Live Activity catches up).
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                ActivityPush.shared.resync()
                while !Task.isCancelled {
                    await model.refresh()
                    try? await Task.sleep(for: .seconds(5))
                }
            }
            .sheet(isPresented: $pairing) { PairSheet(model: model) }
            .confirmationDialog("Remove \(model.selected?.name ?? "this TV")?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove TV", role: .destructive) { Task { await model.removeSelected() } }
            } message: {
                Text("You can pair it again later with a new code from the TV.")
            }
            .alert("Rename TV", isPresented: $renaming) {
                TextField("Name", text: $newName)
                    .textInputAutocapitalization(.words)
                Button("Save") { Task { await model.renameSelected(to: newName) } }
                Button("Use TV's name") { Task { await model.renameSelected(to: nil) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Up to 40 characters.")
            }
            .alert("Welcome", isPresented: Binding(get: { session.notice != nil }, set: { if !$0 { session.notice = nil } })) {
                Button("OK") { session.notice = nil }
            } message: { Text(session.notice ?? "") }
        }
        .task { await session.loadPerson() }
    }

    // MARK: Pieces

    /// Below the title, centered: the selected TV, opening the list of TVs.
    private var tvSwitcher: some View {
        Menu {
            Picker("TV", selection: $model.selectedId) {
                ForEach(model.devices) { device in
                    Label(device.name, systemImage: device.connected ? "circle.fill" : "circle")
                        .tag(device.id)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.selected?.connected == true ? .green : .gray)
                    .frame(width: 8, height: 8)
                Text(model.selected?.name ?? "TV").font(.headline).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("TV: \(model.selected?.name ?? "none")")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let person = session.person {
                    Text("Signed in as \(person.displayName)")
                }
                Button("Pair a TV", systemImage: "plus") { pairing = true }
                // Same path (and push-token registration) as before, from the menu now.
                if model.activityRunning {
                    Button("End Live Activity", systemImage: "platter.filled.bottom.iphone") {
                        Task { await model.endActivity() }
                    }
                } else if model.selected != nil {
                    Button("Start Live Activity", systemImage: "platter.filled.bottom.iphone") {
                        Task { await model.startActivity() }
                    }
                }
                if let device = model.selected {
                    Button("Rename TV…", systemImage: "pencil") {
                        newName = device.name
                        renaming = true
                    }
                    Button("Remove this TV", systemImage: "trash", role: .destructive) { confirmRemove = true }
                }
                Divider()
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                    Task {
                        await session.signOut()
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("More")
        }
    }

    private func controls(_ device: DeviceInfo) -> some View {
        VStack(spacing: 24) {
            HStack(spacing: 6) {
                Circle().fill(device.connected ? .green : .gray).frame(width: 8, height: 8)
                Text(device.connected ? "YouTube is open" : "Not connected. Is YouTube open on it?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(device.speed.speedLabel)
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("×").font(.largeTitle.weight(.semibold)).foregroundStyle(.secondary)
            }
            .animation(.snappy, value: device.speed)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Speed \(device.speed.speedLabel) times")

            HStack(spacing: 8) {
                ForEach(SpeedAPI.speeds, id: \.self) { speed in
                    let selected = speed == device.speed
                    Button {
                        Task { await model.setSpeed(speed) }
                    } label: {
                        Text(speed.speedLabel)
                            .font(.headline)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(selected ? Color.red : Color.secondary.opacity(0.18),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(selected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            Button {
                Task { await model.setCaptions(!device.captions) }
            } label: {
                Label("Captions \(device.captions ? "on" : "off")",
                      systemImage: device.captions ? "captions.bubble.fill" : "captions.bubble")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(device.captions ? Color.primary : Color.secondary.opacity(0.18), in: Capsule())
                    .foregroundStyle(device.captions ? Color(.systemBackground) : .primary)
            }
            .buttonStyle(.plain)
        }
        .disabled(model.busy)
        .padding(.top, 24)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No TVs yet", systemImage: "tv")
        } description: {
            Text("Pair a TV with the code YouTube shows on it.")
        } actions: {
            Button("Pair a TV") { pairing = true }
                .buttonStyle(.glassProminent)
        }
        .padding(.top, 60)
    }
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
