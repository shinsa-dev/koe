import SwiftUI

/// The card you type a note in: under a screenshot's region, or on its own under the pill. Return attaches,
/// Esc cancels.
struct NoteCard: View {
    static let width: CGFloat = 340
    static let height: CGFloat = 80

    let placeholder: String
    let action: String
    /// Where the capture came from, shown so you can tell Koe picked the right window.
    var detail: String?
    @Binding var text: String
    let submit: () -> Void
    let cancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextInput(placeholder: placeholder, text: $text, onSubmit: submit)
                .focused($focused)
            HStack(spacing: 6) {
                if let detail {
                    Text(detail)
                        .font(Typography.meta)
                        .foregroundStyle(Palette.fg2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Button(action: cancel) {
                    HStack(spacing: 6) { Text("Cancel"); Kbd("Esc") }
                }
                .buttonStyle(.koe(.secondary, size: .small))
                Button(action: submit) { Text(action) }
                .buttonStyle(.koe(.primary, size: .small))
            }
        }
        .padding(8)
        .frame(width: Self.width)
        // Swallows presses on the card, so they never reach the region picker behind it.
        .contentShape(shape)
        .onTapGesture {}
        .floatingSurface(cornerRadius: 14)
        .onAppear { focused = true }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }
}
