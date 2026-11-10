import AppKit
import SwiftUI

extension NSColor {
    convenience init(rgba: UInt32) {
        self.init(
            srgbRed: CGFloat((rgba >> 24) & 0xFF) / 255,
            green: CGFloat((rgba >> 16) & 0xFF) / 255,
            blue: CGFloat((rgba >> 8) & 0xFF) / 255,
            alpha: CGFloat(rgba & 0xFF) / 255
        )
    }

    /// A dynamic colour as it looks in the dark theme, for surfaces that stay dark whatever the theme.
    var inDark: NSColor {
        var resolved = self
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            resolved = self.usingColorSpace(.sRGB) ?? self
        }
        return resolved
    }

    /// Picks between two token colours by theme; each resolves in the appearance being drawn.
    static func token(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    static func token(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgba: isDark ? dark : light)
        }
    }
}

/// Shinsa's semantic tokens (`Tokens`, generated from the web's globals.css by scripts/tokens.py), named as
/// shinsa-ios names them. fg-1 is decoration only, fg-2 meta, fg-3 body, fg-4 titles and what you act on.
enum Palette {
    static let canvas = Color(nsColor: Tokens.background)
    static let card = Color(nsColor: Tokens.card)
    static let surface = Color(nsColor: Tokens.bg2)
    static let well = Color(nsColor: Tokens.bg3)
    static let rest = Color(nsColor: Tokens.bg4)
    static let border = Color(nsColor: Tokens.bg3)
    static let press = Color(nsColor: Tokens.bgA2)
    static let hover = Color(nsColor: Tokens.bgA1)
    static let fg1 = Color(nsColor: Tokens.fg1)
    static let fg2 = Color(nsColor: Tokens.fg2)
    static let fg3 = Color(nsColor: Tokens.fg3)
    static let fg4 = Color(nsColor: Tokens.fg4)
    static let icon2 = Color(nsColor: Tokens.icon2)
    static let action = Color(nsColor: Tokens.primary4)
    static let actionText = Color(nsColor: Tokens.primaryText)
    static let onAction = Color(nsColor: Tokens.primaryForeground)
    static let actionTint = Color(nsColor: Tokens.primaryA3)
    /// The web's shadows are pure black at an alpha (tokens.py skips them), so this is the one black Koe draws.
    static let shadow = Color(nsColor: NSColor(rgba: 0x000000FF))
    static let highlight = Color(nsColor: NSColor(rgba: 0xFFFFFFFF))
    static let scrim = shadow.opacity(0.4)
    static let sidebar = Color(nsColor: Tokens.sidebar)
    static let ring = Color(nsColor: Tokens.bgA3)
    /// The web's outline button and raised segment: the canvas in light, bg-4 lifted off it in dark.
    static let control = Color(nsColor: .token(light: Tokens.background, dark: Tokens.bg3))
    static let popover = Color(nsColor: Tokens.popover)
    static let input = Color(nsColor: Tokens.input)
    static let ringHover = Color(nsColor: Tokens.bg4)
    static let controlPressed = Color(nsColor: .token(light: Tokens.bg1, dark: Tokens.bg4))
    static let segment = Color(nsColor: .token(light: Tokens.background, dark: Tokens.bg4))
    static let hudCanvas = Color(nsColor: Tokens.background.inDark)
    static let hudRing = Color(nsColor: Tokens.bgA3.inDark)
}

/// State colours only, never decoration: green done, amber waiting, red failed.
enum Tone {
    case neutral, green, amber, red

    var ink: Color {
        switch self {
        case .neutral: Palette.fg2
        case .green: Color(nsColor: Tokens.greenText)
        case .amber: Color(nsColor: Tokens.amberText)
        case .red: Color(nsColor: Tokens.redText)
        }
    }

    var glyph: Color { self == .neutral ? Palette.icon2 : ink }

    /// The full-strength fill, for a solid control such as the pill's stop button.
    var solid: Color {
        switch self {
        case .neutral: Palette.fg2
        case .green: Color(nsColor: Tokens.green4)
        case .amber: Color(nsColor: Tokens.amber4)
        case .red: Color(nsColor: Tokens.red4)
        }
    }

    var tint: Color {
        switch self {
        case .neutral: Palette.press
        case .green: Color(nsColor: Tokens.greenA2)
        case .amber: Color(nsColor: Tokens.amberA2)
        case .red: Color(nsColor: Tokens.redA2)
        }
    }
}

/// The surface of everything that floats over other apps: a dark HUD like the notch, whatever the theme. Shinsa's
/// dark canvas over a blur of what is behind, a hairline light ring and a soft shadow. Content inside reads the dark tokens.
struct HUDSurface: ViewModifier {
    let cornerRadius: CGFloat
    var shadow = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            // One material and one fill in the same shape, so the surface, its ring and its content resize as one.
            // Liquid Glass keeps its own pace and showed as a second outline while the pill changed width.
            .background {
                shape.fill(.ultraThinMaterial)
                shape.fill(Palette.hudCanvas.opacity(0.88))
            }
            .overlay(shape.strokeBorder(Palette.hudRing, lineWidth: 1))
            .shadow(color: Palette.shadow.opacity(shadow ? 0.25 : 0), radius: 14, y: 6)
            .tint(Palette.action)
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func floatingSurface(cornerRadius: CGFloat, shadow: Bool = true) -> some View {
        modifier(HUDSurface(cornerRadius: cornerRadius, shadow: shadow))
    }
}
