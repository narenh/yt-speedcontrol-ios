import SwiftUI

/// A TV name: the server allows 1–40 characters after trimming, and has the last word.
enum TVName {
    static let maxLength = 40

    static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func isTooLong(_ text: String) -> Bool { trimmed(text).count > maxLength }
    static func tooLongMessage(_ text: String) -> String {
        "That's \(trimmed(text).count) characters. Up to \(maxLength)."
    }
}

/// A text field for a TV name, with a clear button while it has text and focus.
struct NameField: View {
    let placeholder: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var disabled = false
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack {
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused(focused)
                .onSubmit(onSubmit)
                .disabled(disabled)
            if !text.isEmpty && focused.wrappedValue && !disabled {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tertiary)
                    .buttonStyle(.plain)
            }
        }
    }
}
