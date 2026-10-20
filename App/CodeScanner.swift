import SwiftUI
import VisionKit

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
struct CodeScanner: UIViewControllerRepresentable {
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

