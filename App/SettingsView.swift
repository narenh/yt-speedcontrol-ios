import SwiftUI

/// Account-wide captions, the selected TV's name, sponsor skipping and removal, the Live
/// Activity, and the Canopy Account.
struct SettingsView: View {
    let model: TVModel
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false
    @State private var confirmSkip = false
    @State private var path: [Route] = []

    enum Route: Hashable { case rename }

    #if DEBUG
    /// For previews: open with a dialog up or the rename screen pushed.
    var initialDialog: InitialDialog?
    enum InitialDialog { case skip, remove }
    var initialPath: [Route] = []
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                if let message = model.message {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                captions
                if let device = model.selected { tvSection(device) }
                liveActivity
                account
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .navigationDestination(for: Route.self) { _ in
                if let device = model.selected { RenameView(model: model, device: device) }
            }
        }
        .tint(.canopyLink)
        #if DEBUG
        .onAppear {
            path = initialPath
            switch initialDialog {
            case .skip: confirmSkip = true
            case .remove: confirmRemove = true
            case nil: break
            }
        }
        #endif
    }

    // MARK: Sections

    private var captions: some View {
        Section {
            Toggle("Auto captions above 1×", isOn: Binding(get: { model.autoCaptions }, set: { model.setAutoCaptions($0) }))
                .tint(.green)
                .disabled(model.autoCaptionsPending)
            Toggle("Captions always on", isOn: Binding(get: { model.captionsAlways }, set: { model.setCaptionsAlways($0) }))
                .tint(.green)
                .disabled(model.autoCaptionsPending)
        } header: {
            Text("Captions")
        } footer: {
            if let error = model.autoCaptionsError {
                Text(error).foregroundStyle(.orange)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto captions: speeding up turns captions on; back at 1× turns them off.")
                    Text("Always on: every new video starts with captions on, at any speed.")
                    Text("The Captions button works either way.")
                }
            }
        }
    }

    private func tvSection(_ device: DeviceInfo) -> some View {
        Section {
            NavigationLink(value: Route.rename) {
                LabeledContent("Name", value: device.name)
            }
            // Absent: this person may not use it, or the server has it off. No row at all then.
            if let skip = device.skipSponsors {
                Button { confirmSkip = true } label: {
                    HStack {
                        LabeledContent("Sponsor skipping", value: skip ? "On" : "Off")
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .disabled(model.skipPending.contains(device.id))
                .accessibilityHint(skip ? "Asks before turning it off" : "Asks before turning it on")
                .confirmationDialog(skip ? "Stop skipping sponsors on \(device.name)?" : "Skip sponsors on \(device.name)?",
                                    isPresented: $confirmSkip, titleVisibility: .visible) {
                    if skip {
                        Button("Turn Off", role: .destructive) { model.setSkipSponsors(false) }
                        Button("Keep Skipping", role: .cancel) {}
                    } else {
                        Button("Turn On") { model.setSkipSponsors(true) }
                        Button("Not Now", role: .cancel) {}
                    }
                } message: {
                    Text(skip ? "Sponsor segments and ads will play on this TV again. You can turn it back on here in Settings."
                              : "Canopy Control will skip sponsor segments and ads on this TV with SponsorBlock. You can turn it off here in Settings.")
                }
            }
            Button("Remove this TV") { confirmRemove = true }
                .confirmationDialog("Remove \(device.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                    Button("Remove TV", role: .destructive) { Task { await model.removeSelected() } }
                } message: {
                    Text("You can pair it again later with a new code from the TV.")
                }
        } header: {
            Text(device.name)
        } footer: {
            Text("Settings for the TV selected on the main screen.")
        }
    }

    private var liveActivity: some View {
        Section {
            if model.activityRunning {
                Button("End Live Activity") { Task { await model.endActivity() } }
            } else {
                Button("Show on Lock Screen now") { Task { await model.startActivity() } }
                    .disabled(model.selected == nil)
            }
        } header: {
            Text("Live Activity")
        } footer: {
            Text("It also appears by itself when a video starts on one of your TVs.")
        }
    }

    private var account: some View {
        Section("Canopy Account") {
            LabeledContent("Signed in as", value: session.person?.displayName ?? "…")
            Button("Sign out") { Task { await session.signOut() } }
        }
    }
}

/// Renames the selected TV: Save, or Use TV's name to go back to the name the TV reports.
struct RenameView: View {
    let model: TVModel
    let device: DeviceInfo
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private var trimmed: String { TVName.trimmed(name) }
    private var tooLong: Bool { TVName.isTooLong(name) }
    private var canSave: Bool { !trimmed.isEmpty && !tooLong && trimmed != device.name }

    var body: some View {
        Form {
            Section {
                NameField(placeholder: device.name, text: $name, focused: $focused, disabled: isSaving) {
                    if canSave { save(trimmed) }
                }
            } footer: {
                Text(tooLong ? TVName.tooLongMessage(name) : "Up to \(TVName.maxLength) characters.")
                    .foregroundStyle(tooLong ? .orange : .secondary)
            }
            Section {
                Button("Use TV's name") { save(nil) }
                    .disabled(isSaving)
            } footer: {
                Text("Goes back to the name the TV reports itself.")
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.orange) }
            }
        }
        .navigationTitle("Name")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { save(trimmed) }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear {
            name = device.name
            focused = true
        }
    }

    /// `nil`: the TV's own name.
    private func save(_ newName: String?) {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await model.rename(device: device.id, to: newName)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                focused = true
            }
        }
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView(model: .preview())
        .environment(AppSession.preview())
}

#Preview("Turn off sponsor skipping") {
    SettingsView(model: .preview(), initialDialog: .skip)
        .environment(AppSession.preview())
}

#Preview("Rename") {
    NavigationStack {
        RenameView(model: .preview(), device: DeviceInfo.samples[0])
    }
}
#endif
