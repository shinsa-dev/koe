import AppKit
import SwiftUI

/// Every glyph Koe draws, named as the web names it: Central Icons, rendered by shinsa's own icon pipeline
/// (`bun scripts/icons.ts`) into Resources/Icons, so a glyph here is the one the web draws. A name that isn't an
/// "Icon…" is an SF Symbol, kept only where Central has no match (the ⌘ key).
enum Icon: String, CaseIterable {
    case microphone = "IconMicrophone"
    case screenCapture = "IconScreenCapture"
    case cursorClick = "IconCursorClick"
    case checkmark = "IconCheckmark1"
    case accessibility = "IconHandTouch"
    case settings = "IconSettingsGear1"
    case permissions = "IconHand4Finger"
    case shortcuts = "command"
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
    case warning = "IconExclamationCircle"
    case muted = "IconMicrophoneOff"
    case comment = "IconBubbleAnnotation2"
    case screenshot = "IconCamera1"
    case image = "IconImages1"
    case file = "IconPaperclip2"

    /// The web's icon sizes: 12 for the smallest glyphs, sm 14, md 16, lg 20 (globals.css → --icon-size-*).
    enum Size: CGFloat {
        case tiny = 12, small = 14, medium = 16, large = 20
    }

    var isSymbol: Bool { !rawValue.hasPrefix("Icon") }

    @MainActor private static var cache: [String: NSImage] = [:]

    /// A template image at `side` points, tinted by whoever draws it.
    @MainActor func image(side: CGFloat) -> NSImage {
        let key = "\(rawValue)@\(side)"
        if let cached = Self.cache[key] { return cached }
        let image: NSImage
        if isSymbol {
            image = NSImage(systemSymbolName: rawValue, accessibilityDescription: String(describing: self))?
                .withSymbolConfiguration(.init(pointSize: side * 0.85, weight: .medium)) ?? NSImage()
        } else {
            let url = Bundle.main.resourceURL?.appendingPathComponent("Icons/\(rawValue).svg")
            image = url.flatMap(NSImage.init(contentsOf:)) ?? NSImage(size: NSSize(width: side, height: side))
            image.size = NSSize(width: side, height: side)
        }
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
    /// Kept for callers; the web's glyphs have one stroke.
    var weight: Font.Weight = .medium

    var body: some View {
        Image(nsImage: icon.image(side: size.rawValue))
            .renderingMode(.template)
            .foregroundStyle(color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.foreground))
            .frame(width: size.rawValue, height: size.rawValue)
            .accessibilityHidden(true)
    }
}
