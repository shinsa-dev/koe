import SwiftUI

/// The web's `Input`: a bg-input fill with no ring, 26 pt tall, rounded as a control, medium fg-4 text.
struct TextInput: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.fg2))
            .textFieldStyle(.plain)
            .font(Font(Typography.sans(13, .medium)))
            .foregroundStyle(Palette.fg4)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color(nsColor: Tokens.input), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onSubmit(onSubmit)
    }
}
