import SwiftUI

/// Native push buttons under Koe's names, tinted with Shinsa's blue: primary is the prominent accent button,
/// outline the standard bordered one, secondary a quiet borderless one in fg-2 for icon buttons and Cancel.
/// `iconOnly` makes the label a square the height of the control, so a row of glyph buttons lines up.
struct KoeButtonStyle: PrimitiveButtonStyle {
    enum Variant { case primary, outline, secondary }
    enum Size { case small, regular, large }

    var variant: Variant = .primary
    var size: Size = .regular
    var iconOnly = false

    private var iconSide: CGFloat {
        switch size {
        case .small: 14
        case .regular: 18
        case .large: 24
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        styled(Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.frame(width: iconOnly ? iconSide : nil, height: iconOnly ? iconSide : nil)
        })
            .controlSize(size == .small ? .small : size == .large ? .large : .regular)
    }

    @ViewBuilder private func styled(_ button: some View) -> some View {
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
        iconOnly: Bool = false
    ) -> KoeButtonStyle {
        KoeButtonStyle(variant: variant, size: size, iconOnly: iconOnly)
    }
}
