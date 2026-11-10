import SwiftUI
import VisionKit

/// What pairing a TV with a code does.
enum PairMode {
    /// A TV Canopy Control controls and shows in Live Activities (`POST /pair`).
    case paired
    /// Sponsor skipping only (`POST /skip-tvs`): no remote, no Live Activity.
    case sponsorBlockOnly
}

/// The TV just paired, in either mode: what the name step needs.
private struct PairedTV {
    let id: String
    let name: String
}

/// Pair a TV with the code YouTube shows under Settings → Link with TV code. Opens full screen on
/// the camera and pairs as soon as it reads a code; typing it is the fallback. Once paired, it
/// asks for a name, with the TV's own as the placeholder.
struct PairSheet: View {
    let model: TVModel
    let mode: PairMode
    @Environment(\.dismiss) private var dismiss
    /// The TV just paired: the sheet is on its name step.
    @State private var paired: PairedTV?
    @State private var manual = !PairSheet.canScan
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    /// The code the camera read, while pairing with it or after it failed.
    @State private var scanned: String?
    /// Bumped to start a fresh scanner after a failed pairing.
    @State private var scanAttempt = 0
    @FocusState private var focused: Bool

    private static var canScan: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    init(model: TVModel, mode: PairMode = .paired) {
        self.model = model
        self.mode = mode
    }

    private var title: LocalizedStringKey { mode == .paired ? "Pair a TV" : "Sponsor Block Only" }
    private var skipNote: String {
        "Canopy Control won't control this TV or show it in Live Activities. It only skips sponsors and ads."
    }

    #if DEBUG
    /// For previews: the sheet already on the name step for `paired`.
    init(model: TVModel, paired: DeviceInfo) {
        self.model = model
        self.mode = .paired
        _paired = State(initialValue: PairedTV(id: paired.id, name: paired.name))
    }
    #endif

    var body: some View {
        NavigationStack {
            if let paired {
                NameStep(model: model, mode: mode, device: paired) { dismiss() }
            } else if manual {
                manualForm
            } else {
                scanView
            }
        }
    }

    // MARK: Scanner

    private var scanView: some View {
        VStack(spacing: 0) {
            viewfinder
                .padding(.horizontal, 24)
                .padding(.top, 12)
            VStack(spacing: 10) {
                Text("Point at the code on your TV")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("On the TV, open YouTube › Settings › Link with TV code. Canopy Control pairs as soon as it reads it.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                if mode == .sponsorBlockOnly {
                    Text(skipNote)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                status
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            Spacer(minLength: 16)
            Button("Type the code instead") {
                if let scanned { code = TVCode.grouped(scanned) }
                errorMessage = nil
                manual = true
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Color(hex: 0xFF6B5E))
            .frame(minHeight: 44)
            .disabled(isWorking)
            .padding(.bottom, 16)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pairBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var viewfinder: some View {
        Color.black
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                if scanned == nil {
                    CodeScanner { digits in
                        scanned = digits
                        Task { await pair(digits) }
                    }
                    .id(scanAttempt)
                } else if let scanned {
                    Text(TVCode.grouped(scanned))
                        .font(.title.monospacedDigit().weight(.semibold))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            }
    }

    @ViewBuilder
    private var status: some View {
        if scanned != nil {
            if isWorking {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Pairing…").font(.subheadline.weight(.semibold))
                }
                .padding(.top, 8)
            } else if let errorMessage {
                VStack(spacing: 10) {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                    Button("Scan again", systemImage: "camera.viewfinder") {
                        self.scanned = nil
                        self.errorMessage = nil
                        scanAttempt += 1
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.canopyAccent)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: Typing the code

    private var manualForm: some View {
        Form {
            Section {
                TextField("TV code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.title3.monospacedDigit())
                    .focused($focused)
                if Self.canScan {
                    Button("Scan code instead", systemImage: "camera.viewfinder") {
                        scanned = nil
                        errorMessage = nil
                        scanAttempt += 1
                        manual = false
                    }
                }
            } footer: {
                Text(mode == .sponsorBlockOnly
                     ? "On the TV: YouTube › Settings › Link with TV code\n\(skipNote)"
                     : "On the TV: YouTube › Settings › Link with TV code")
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.orange) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isWorking {
                    ProgressView()
                } else {
                    Button("Pair") { Task { await pair(code) } }
                        .disabled(code.filter(\.isNumber).isEmpty)
                }
            }
        }
        .tint(.canopyLink)
        .onAppear { focused = true }
    }

    private func pair(_ code: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            // Spaces in the code are fine for the server.
            let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
            switch mode {
            case .paired:
                let device = try await model.pair(code: code)
                paired = PairedTV(id: device.id, name: device.name)
            case .sponsorBlockOnly:
                let tv = try await model.addSkipTV(code: code)
                paired = PairedTV(id: tv.id, name: tv.name)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// After pairing: an optional name for the TV. Empty keeps the name the TV reported, which is
/// the placeholder. The TV is already in the list and selected behind the sheet.
private struct NameStep: View {
    let model: TVModel
    let mode: PairMode
    let device: PairedTV
    let done: () -> Void
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private var trimmed: String { TVName.trimmed(name) }
    private var tooLong: Bool { TVName.isTooLong(name) }

    var body: some View {
        Form {
            Section {
                NameField(placeholder: device.name, text: $name, focused: $focused, disabled: isSaving, onSubmit: save)
            } footer: {
                Text(tooLong ? TVName.tooLongMessage(name) : "Leave it empty to keep “\(device.name)”.")
                    .foregroundStyle(tooLong ? .orange : .secondary)
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.orange) }
            }
        }
        .navigationTitle("Name this TV")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip", action: done).disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save", action: save)
                        .buttonStyle(.glassProminent)
                        .tint(.canopyAccent)
                        .disabled(tooLong)
                }
            }
        }
        .onAppear {
            #if DEBUG
            // `-PreviewNameText "<text>"`: start with text in the field, for checking the layout.
            if let text = UserDefaults.standard.string(forKey: "PreviewNameText") { name = text }
            #endif
            focused = true
        }
    }

    /// Empty text is the same as Skip.
    private func save() {
        guard !isSaving, !tooLong else { return }
        let newName = trimmed
        guard !newName.isEmpty else { return done() }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                switch mode {
                case .paired: try await model.rename(device: device.id, to: newName)
                case .sponsorBlockOnly: try await model.renameSkipTV(device.id, to: newName)
                }
                done()
            } catch {
                errorMessage = error.localizedDescription
                focused = true
            }
        }
    }
}

#if DEBUG
#Preview("Scanner") {
    PairSheet(model: .preview())
}

#Preview("Scanner, Sponsor Block only") {
    PairSheet(model: .preview(), mode: .sponsorBlockOnly)
}

#Preview("Name this TV") {
    PairSheet(model: .preview(), paired: DeviceInfo.samples[1])
}
#endif
