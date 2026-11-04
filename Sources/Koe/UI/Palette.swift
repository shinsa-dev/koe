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
/// dark canvas over Liquid Glass, a hairline light ring and a soft shadow. Content inside reads the dark tokens.
struct HUDSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .environment(\.colorScheme, .dark)
            .background { shape.fill(Color(nsColor: NSColor(rgba: 0x101012FF)).opacity(0.88)) }
            .glassEffect(.regular.tint(.black.opacity(0.4)), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.09), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            .tint(Palette.action)
    }
}

extension View {
    func floatingSurface(cornerRadius: CGFloat) -> some View {
        modifier(HUDSurface(cornerRadius: cornerRadius))
    }
}
