import SwiftUI

/// The web's `Button` (`packages/ui/src/components/button.tsx`), variant by variant and size by size. The fill and
/// its shadow sit behind the label, so pressing deflates only the fill by Shinsa's fixed press inset; the label
/// never moves. Hover and press change at once, with no transition, as on the web.
struct KoeButtonStyle: ButtonStyle {
    /// `secondary` is the web's ghost: nothing at rest, a fill on hover. `destructiveGhost` is the same in red, for
    /// removing one row of a list. `destructiveSoft` is Koe's own: the pill's discard, as a square button.
    enum Variant { case primary, secondary, outline, destructive, destructiveSoft, destructiveGhost, bare, link }
    /// `tiny` 22, `small` 24, `regular` 26 and `large` 30 tall; `iconOnly` makes a square of that height.
    enum Size { case tiny, small, regular, large }

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
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    private var height: CGFloat {
        switch size {
        case .tiny: 22
        case .small: 24
        case .regular: 26
        case .large: 30
        }
    }

    private var radius: CGFloat {
        switch size {
        case .tiny, .small: 6
        case .regular, .large: 7
        }
    }

    private var padding: CGFloat {
        if iconOnly || variant == .link { return 0 }
        switch size {
        case .tiny, .small: return 8
        case .regular: return 10
        case .large: return 12
        }
    }

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        let active = (hovering || pressed) && isEnabled
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .font(size == .large ? Typography.controlLarge : Typography.control)
            .lineLimit(1)
            .foregroundStyle(foreground(active: active))
            .padding(.horizontal, padding)
            .frame(width: iconOnly ? height : nil, height: height)
            .background {
                if hasFill {
                    fill(shape: shape, pressed: pressed, active: active)
                        .padding(.horizontal, pressed ? 1 : 0)
                        .padding(.vertical, pressed ? 0.5 : 0)
                }
            }
            .opacity(variant == .link && active ? 0.8 : 1)
            .scaleEffect(variant == .link && pressed ? 0.975 : 1)
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering = $0 }
            .transaction { $0.animation = nil }
    }

    private var hasFill: Bool { variant != .bare && variant != .link }

    private func foreground(active: Bool) -> Color {
        switch variant {
        case .primary, .destructive: Palette.onAction
        case .outline: Palette.fg4
        case .destructiveSoft: Tone.red.ink
        case .destructiveGhost: active ? Tone.red.ink : Palette.fg2
        case .secondary, .bare: active ? Palette.fg4 : Palette.fg2
        case .link: Palette.actionText
        }
    }

    /// The fill with the web's control shadows: primary and destructive a soft drop, a faint ring and a highlight
    /// along the top edge; outline a hairline ring of bg-3 (bg-4 on hover), outside in light, inside in dark.
    @ViewBuilder private func fill(shape: RoundedRectangle, pressed: Bool, active: Bool) -> some View {
        switch variant {
        case .primary:
            raised(shape: shape, color: Palette.action.opacity(active ? 0.8 : 1), ring: 0.08, highlight: 0.16)
        case .destructive:
            raised(shape: shape, color: Tone.red.solid.opacity(active ? 0.9 : 1), ring: 0.06, highlight: 0.2)
        case .outline:
            let ring = active ? Palette.ringHover : Palette.border
            let color = pressed ? Palette.controlPressed : Palette.control
            if scheme == .dark {
                shape.fill(color).overlay(shape.strokeBorder(ring, lineWidth: 1))
            } else {
                shape.fill(color).background(shape.inset(by: -1).fill(ring))
            }
        case .destructiveSoft:
            shape.fill(Tone.red.tint).brightness(active ? 0.06 : 0)
        case .destructiveGhost:
            shape.fill(active ? Tone.red.tint : .clear)
        case .secondary:
            shape.fill(active ? Palette.press.opacity(0.7) : .clear)
        case .bare, .link:
            EmptyView()
        }
    }

    private func raised(shape: RoundedRectangle, color: Color, ring: Double, highlight: Double) -> some View {
        shape.fill(color)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Palette.highlight.opacity(highlight), .clear],
                                   startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.12)),
                    lineWidth: 1
                )
            )
            .background(shape.inset(by: -1).fill(Palette.shadow.opacity(ring)))
            .shadow(color: Palette.shadow.opacity(0.1), radius: 0.5, y: 1)
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
