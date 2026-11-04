import SwiftUI

/// Native push buttons under Koe's names, tinted with Shinsa's blue: primary is the prominent accent button,
/// outline the standard bordered one, secondary a quiet borderless one in fg-2 for icon buttons and Cancel.
struct KoeButtonStyle: PrimitiveButtonStyle {
    enum Variant { case primary, outline, secondary }
    enum Size { case small, regular, large }

    var variant: Variant = .primary
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        styled(Button(configuration))
            .controlSize(size == .small ? .small : size == .large ? .large : .regular)
    }

    @ViewBuilder private func styled(_ button: Button<Configuration.Label>) -> some View {
        switch variant {
        case .primary: button.buttonStyle(.borderedProminent)
        case .outline: button.buttonStyle(.bordered)
        case .secondary: button.buttonStyle(.borderless).tint(Palette.fg2)
        }
    }
}

extension PrimitiveButtonStyle where Self == KoeButtonStyle {
    static func koe(
        _ variant: KoeButtonStyle.Variant = .primary,
        size: KoeButtonStyle.Size = .regular,
        fullWidth: Bool = false,
        iconOnly: Bool = false
    ) -> KoeButtonStyle {
        KoeButtonStyle(variant: variant, size: size)
    }
}
