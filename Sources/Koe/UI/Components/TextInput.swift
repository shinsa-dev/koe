import SwiftUI

/// The web's `Input`: a bg-input fill with no ring and no focus ring, 13 medium fg-4 with an fg-2 placeholder.
/// `regular` is 26 tall, rounded 7 and padded 10; `small` 24, rounded 6 and padded 8.
struct TextInput: View {
    enum Size { case small, regular }

    let placeholder: String
    @Binding var text: String
    var size: Size = .regular
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.fg2))
            .textFieldStyle(.plain)
            .focusEffectDisabled()
            .font(Typography.control)
            .foregroundStyle(Palette.fg4)
            .padding(.horizontal, size == .small ? 8 : 10)
            .frame(height: size == .small ? 24 : 26)
            .background(Palette.input, in: RoundedRectangle(cornerRadius: size == .small ? 6 : 7, style: .continuous))
            .onSubmit(onSubmit)
    }
}
