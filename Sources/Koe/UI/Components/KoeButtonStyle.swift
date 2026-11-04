import SwiftUI

/// The web's `Button`: primary is Shinsa's blue with white text, outline a raised control with a hairline ring,
/// secondary a quiet fg-2 label that gets a wash on hover. Pressing deflates only the fill, as on the web.
/// `iconOnly` makes the button a square the height of its size.
struct KoeButtonStyle: ButtonStyle {
    enum Variant { case primary, outline, secondary, destructive }
    enum Size { case small, regular, large }

    var variant: Variant = .primary
    var size: Size = .regular
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        KoeButton(configuration: configuration, variant: variant, size: size, iconOnly: iconOnly)
    }
}

private struct KoeButton: View {
    let configuration: ButtonStyleConfiguration
    let variant: KoeButtonStyle.Variant
    let size: KoeButtonStyle.Size
    let iconOnly: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var height: CGFloat {
        switch size {
        case .small: 24
        case .regular: 26
        case .large: 30
        }
    }

    private var radius: CGFloat { size == .small ? 6 : 7 }

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .font(size == .large ? Typography.rowTitle : Typography.label)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, iconOnly ? 0 : size == .large ? 12 : size == .small ? 8 : 10)
            .frame(width: iconOnly ? height : nil, height: height)
            .background {
                fill(pressed: pressed)
                    .clipShape(shape)
                    .overlay { if variant == .outline { shape.strokeBorder(Palette.ring, lineWidth: 0.5) } }
                    .shadow(color: variant == .secondary ? .clear : Palette.shadow.opacity(0.08), radius: 1, y: 0.5)
                    .padding(pressed ? 1 : 0)
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch variant {
        case .primary, .destructive: Palette.onAction
        case .outline: Palette.fg4
        case .secondary: hovering && isEnabled ? Palette.fg4 : Palette.fg2
        }
    }

    @ViewBuilder private func fill(pressed: Bool) -> some View {
        let active = (hovering || pressed) && isEnabled
        switch variant {
        case .primary: Palette.action.opacity(active ? 0.8 : 1)
        case .destructive: Tone.red.solid.opacity(active ? 0.9 : 1)
        case .outline: pressed ? Palette.controlPressed : Palette.control
        case .secondary: active ? Palette.press.opacity(0.7) : Color.clear
        }
    }
}

extension ButtonStyle where Self == KoeButtonStyle {
    static func koe(
        _ variant: KoeButtonStyle.Variant = .primary,
        size: KoeButtonStyle.Size = .regular,
        iconOnly: Bool = false
    ) -> KoeButtonStyle {
        KoeButtonStyle(variant: variant, size: size, iconOnly: iconOnly)
    }
}
