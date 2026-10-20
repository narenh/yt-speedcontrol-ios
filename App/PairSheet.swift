import SwiftUI
import VisionKit

/// Pair a TV with the code YouTube shows under Settings → Link with TV code. Opens on the camera
/// and pairs as soon as it reads a code; typing it is the fallback. Once paired, it asks for a
/// name, with the TV's own as the placeholder.
struct PairSheet: View {
    let model: TVModel
    @Environment(\.dismiss) private var dismiss
    /// The TV just paired: the sheet is on its name step.
    @State private var paired: DeviceInfo?
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

    init(model: TVModel) {
        self.model = model
    }

    #if DEBUG
    /// For previews: the sheet already on the name step for `paired`.
    init(model: TVModel, paired: DeviceInfo) {
        self.model = model
        _paired = State(initialValue: paired)
    }
    #endif

    var body: some View {
        NavigationStack {
            if let paired {
                NameStep(model: model, device: paired) { dismiss() }
            } else {
                pairing
            }
        }
    }

    private var pairing: some View {
        Group {
            if manual { manualForm } else { scanView }
        }
        .navigationTitle("Pair a TV")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            if manual {
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Pair") { Task { await pair(code) } }
                            .disabled(code.filter(\.isNumber).isEmpty)
                    }
                }
            }
        }
    }

    private var scanView: some View {
        ZStack(alignment: .bottom) {
            if scanned == nil {
                CodeScanner { digits in
                    scanned = digits
                    Task { await pair(digits) }
                }
                .id(scanAttempt)
                .ignoresSafeArea(edges: .bottom)
            } else {
                Color.black.ignoresSafeArea(edges: .bottom)
            }
            VStack(spacing: 14) {
                if let scanned {
                    VStack(spacing: 10) {
                        if isWorking {
                            ProgressView()
                            Text("Pairing \(TVCode.grouped(scanned))…").font(.subheadline.weight(.semibold))
                        } else if let errorMessage {
                            Text(errorMessage).font(.subheadline).multilineTextAlignment(.center)
                            Button("Scan again", systemImage: "camera.viewfinder") {
                                self.scanned = nil
                                self.errorMessage = nil
                                scanAttempt += 1
                            }
                            .buttonStyle(.glassProminent)
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    Text("Point the camera at the code on the TV\n(YouTube → Settings → Link with TV code)")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Button("Enter code manually", systemImage: "keyboard") {
                    if let scanned { code = TVCode.grouped(scanned) }
                    errorMessage = nil
                    manual = true
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(isWorking)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

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
                Text("On the TV: YouTube → Settings → Link with TV code")
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.orange) }
            }
        }
        .onAppear { focused = true }
    }

    private func pair(_ code: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            // Spaces in the code are fine for the server.
            paired = try await model.pair(code: code.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// After pairing: an optional name for the TV. Empty keeps the name the TV reported, which is
/// the placeholder. The TV is already in the list and selected behind the sheet.
private struct NameStep: View {
    let model: TVModel
    let device: DeviceInfo
    let done: () -> Void
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    /// The server allows 1–40 characters; it has the last word.
    private static let maxLength = 40

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var tooLong: Bool { trimmed.count > Self.maxLength }

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField(device.name, text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit(save)
                    if !name.isEmpty && focused && !isSaving {
                        Button("Clear", systemImage: "xmark.circle.fill") { name = "" }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.tertiary)
                            .buttonStyle(.plain)
                    }
                }
            } footer: {
                Text(tooLong ? "That's \(trimmed.count) characters. Up to \(Self.maxLength)."
                             : "Leave it empty to keep “\(device.name)”.")
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
                try await model.rename(device: device.id, to: newName)
                done()
            } catch {
                errorMessage = error.localizedDescription
                focused = true
            }
        }
    }
}

/// YouTube's "Link with TV code": 12 digits, usually shown as "123 456 789 012".
enum TVCode {
    /// A run of digits, allowing a space or dash between any two of them.
    private static let digitRun = #/\d(?:[ \-]?\d)*/#

    /// The digits of the first run in `text` with exactly 12 of them (not part of a longer number).
    static func find(in text: String) -> String? {
        for match in text.matches(of: digitRun) {
            let digits = match.output.filter(\.isNumber)
            if digits.count == 12 { return String(digits) }
        }
        return nil
    }

    /// "123456789012" → "123 456 789 012", the way the TV shows it.
    static func grouped(_ digits: String) -> String {
        stride(from: 0, to: digits.count, by: 3).map { i in
            let start = digits.index(digits.startIndex, offsetBy: i)
            let end = digits.index(start, offsetBy: 3, limitedBy: digits.endIndex) ?? digits.endIndex
            return String(digits[start..<end])
        }.joined(separator: " ")
    }
}

/// VisionKit's live text scanner, stopping at the first 12-digit TV code.
private struct CodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning && !context.coordinator.found { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        var found = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            check(addedItems, scanner)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            check(updatedItems, scanner)
        }

        private func check(_ items: [RecognizedItem], _ scanner: DataScannerViewController) {
            guard !found else { return }
            for item in items {
                guard case .text(let text) = item, let digits = TVCode.find(in: text.transcript) else { continue }
                found = true
                scanner.stopScanning()
                onCode(digits)
                return
            }
        }
    }
}

#if DEBUG
#Preview("Name this TV") {
    PairSheet(model: .preview(), paired: DeviceInfo.samples[1])
}
#endif
