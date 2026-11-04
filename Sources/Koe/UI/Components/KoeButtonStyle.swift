import SwiftUI

/// The web's `Button`: primary is the one accent with the control shadow, outline is a card with a bg-3 ring,
/// secondary is quiet text that brightens. Pressing insets only the fill, as the web's `::before` does.
struct KoeButtonStyle: ButtonStyle {
    enum Variant { case primary, outline, secondary }
    enum Size { case small, regular, large }

    var variant: Variant = .primary
    var size: Size = .regular
    var fullWidth = false

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size == .large ? Typography.rowTitle : Font(Typography.sans(13, .medium)))
            .foregroundStyle(foreground)
            .padding(.horizontal, size == .large ? 12 : size == .regular ? 10 : 8)
            .frame(height: height)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background {
                fill(pressed: configuration.isPressed)
                    .padding(.horizontal, configuration.isPressed ? 1 : 0)
                    .padding(.vertical, configuration.isPressed ? 0.5 : 0)
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering = $0 }
    }

    private var height: CGFloat {
        switch size {
        case .small: 24
        case .regular: 26
        case .large: 30
        }
    }

    private var radius: CGFloat { size == .small ? 6 : 7 }

    private var foreground: Color {
        switch variant {
        case .primary: Palette.onAction
        case .outline: Palette.fg4
        case .secondary: hovering && isEnabled ? Palette.fg4 : Palette.fg2
        }
    }

    @ViewBuilder private func fill(pressed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let active = isEnabled && (hovering || pressed)
        switch variant {
        case .primary:
            shape.fill(Palette.action.opacity(active ? 0.8 : 1))
                .overlay(shape.strokeBorder(.black.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.1), radius: 0.5, y: 1)
        case .outline:
            shape.fill(Palette.card)
                .overlay(shape.strokeBorder(active ? Palette.rest : Palette.border, lineWidth: 1))
        case .secondary:
            shape.fill(active ? Palette.press.opacity(0.7) : .clear)
        }
    }
}

extension ButtonStyle where Self == KoeButtonStyle {
    static func koe(
        _ variant: KoeButtonStyle.Variant = .primary,
        size: KoeButtonStyle.Size = .regular,
        fullWidth: Bool = false
    ) -> KoeButtonStyle {
        KoeButtonStyle(variant: variant, size: size, fullWidth: fullWidth)
    }
}
