import AppKit
import SwiftUI

/// Every glyph Koe draws, named as the web names it. scripts/icons.ts renders each with shinsa's own icon pipeline
/// into Resources/Icons, so an icon here is the web's icon. Never an SF Symbol.
enum Icon: String, CaseIterable {
    case microphone = "IconMicrophone"
    case screenCapture = "IconScreenCapture"
    case cursorClick = "IconCursorClick"
    case check = "IconCheckmark1"
    case stop = "IconStop"
    case close = "IconCrossSmall"
    case paperclip = "IconPaperclip1"
    case video = "IconVideo"
    case play = "IconPlay"
    case pause = "IconPause"
    case previous = "IconChevronLeftSmall"
    case next = "IconChevronRightSmall"
    case add = "IconPlusSmall"
    case trash = "IconTrashCanSimple"

    /// The web's icon sizes: sm 14, md 16, lg 20 (globals.css → --icon-size-*).
    enum Size: CGFloat {
        case small = 14, medium = 16, large = 20
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    /// A template image at `side` points, tinted by whoever draws it.
    @MainActor func image(side: CGFloat) -> NSImage {
        let key = "\(rawValue)@\(side)"
        if let cached = Self.cache[key] { return cached }
        let url = Bundle.main.resourceURL?.appendingPathComponent("Icons/\(rawValue).svg")
        let image = url.flatMap(NSImage.init(contentsOf:)) ?? NSImage(size: NSSize(width: side, height: side))
        image.size = NSSize(width: side, height: side)
        image.isTemplate = true
        image.accessibilityDescription = String(describing: self)
        Self.cache[key] = image
        return image
    }
}

struct IconView: View {
    let icon: Icon
    var size: Icon.Size = .small
    /// nil takes the surrounding foreground, as a glyph inside a button does.
    var color: Color? = Palette.icon2

    var body: some View {
        Image(nsImage: icon.image(side: size.rawValue))
            .renderingMode(.template)
            .foregroundStyle(color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.foreground))
            .frame(width: size.rawValue, height: size.rawValue)
            .accessibilityHidden(true)
    }
}
