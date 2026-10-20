import SwiftUI
import VisionKit

/// Pair a TV with the code YouTube shows under Settings → Link with TV code: typed, or read with
/// the camera.
struct PairSheet: View {
    let model: TVModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var scanning = false
    @FocusState private var focused: Bool

    private var canScan: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("TV code", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.title3.monospacedDigit())
                        .focused($focused)
                    if canScan {
                        Button("Scan code", systemImage: "camera.viewfinder") { scanning = true }
                    }
                } footer: {
                    Text("On the TV: YouTube → Settings → Link with TV code")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.orange) }
                }
            }
            .navigationTitle("Pair a TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Pair") { Task { await pair() } }
                            .disabled(code.filter(\.isNumber).isEmpty)
                    }
                }
            }
            .onAppear { focused = !canScan }
            .fullScreenCover(isPresented: $scanning) {
                CodeScannerSheet { digits in
                    code = TVCode.grouped(digits)
                    scanning = false
                }
            }
        }
    }

    private func pair() async {
        isWorking = true
        defer { isWorking = false }
        do {
            // Spaces in the code are fine for the server.
            try await model.pair(code: code.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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

/// The camera, with a Cancel button.
private struct CodeScannerSheet: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            CodeScanner(onCode: onCode).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Point the camera at the code on the TV")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
            .padding(.bottom, 24)
        }
    }
}

/// VisionKit's live text scanner, stopping at the first 12-digit TV code. It doesn't submit:
/// the code goes into the field for the person to check and tap Pair.
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
