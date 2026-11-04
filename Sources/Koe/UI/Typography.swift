import AppKit
import CoreText
import SwiftUI

/// ABC Areal, the web's typeface (scripts/fonts.py), at the web's weights and its Mac sizes:
/// 13 body (`text-xs`), 12 meta (`text-2xs`), 15 and 18 titles. Tracking is baked into the font files.
enum Typography {
    enum Weight: Int {
        case normal = 400, medium = 450, semibold = 550, bold = 600

        var system: NSFont.Weight {
            switch self {
            case .normal: .regular
            case .medium: .medium
            case .semibold, .bold: .semibold
            }
        }
    }

    /// The fonts ship in Koe.app's Resources/Fonts; registered once at launch so `NSFont(name:)` finds them.
    static func registerFonts() {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }

    static func sans(_ size: CGFloat, _ weight: Weight = .normal) -> NSFont {
        NSFont(name: "ShinsaAreal-W\(weight.rawValue)", size: size) ?? .systemFont(ofSize: size, weight: weight.system)
    }

    static func mono(_ size: CGFloat, _ weight: Weight = .normal) -> NSFont {
        let name = weight.rawValue >= Weight.medium.rawValue ? "ShinsaArealMono-W500" : "ShinsaArealMono-W400"
        return NSFont(name: name, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight.system)
    }

    static let pageTitle = Font(sans(18, .medium))
    static let title = Font(sans(15, .medium))
    static let rowTitle = Font(sans(13, .medium))
    static let body = Font(sans(13))
    static let meta = Font(sans(12))
    static let label = Font(sans(12, .medium))
    static let code = Font(mono(12))
}
