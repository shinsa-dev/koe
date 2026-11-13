import AppKit
import SwiftUI

/// Every glyph Koe draws, named as the web names it: Central Icons, rendered by shinsa's own icon pipeline
/// (`bun scripts/icons.ts`) into Resources/Icons, so a glyph here is the one the web draws. A name that isn't an
/// "Icon…" is an SF Symbol, kept only where Central has no match (the ⌘ key).
enum Icon: String, CaseIterable {
    case microphone = "IconMicrophone"
    case screenCapture = "IconScreenCapture"
    case systemAudio = "IconVolumeFull"
    case cursorClick = "IconCursorClick"
    case checkmark = "IconCheckmark1"
    case accessibility = "IconHandTouch"
    case settings = "IconSettingsGear1"
    case permissions = "IconHand4Finger"
    case shortcuts = "command"
    case close = "IconCrossSmall"
    case paperclip = "IconPaperclip1"
    case video = "IconVideo"
    case play = "IconPlayFilled"
    case pause = "IconPauseFilled"
    case stop = "IconStopFilled"
    /// Stroked like the cross and the check beside them in the pill.
    case pauseLine = "IconPause"
    case playLine = "IconPlay"
    case retake = "IconArrowRotateCounterClockwise"
    case previous = "IconChevronLeftSmall"
    case next = "IconChevronRightSmall"
    case chevronDown = "IconChevronDownMedium"
    /// The medium plus: its arms reach as far as the cross and the check beside it in the pill.
    case add = "IconPlusMedium"
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
    /// Drawn this many points larger than its box, for a glyph whose artwork is slighter than its neighbours'.
    var grow: CGFloat = 0

    var body: some View {
        glyph
            .frame(width: size.rawValue, height: size.rawValue)
            .accessibilityHidden(true)
    }

    /// With no colour of its own the glyph inherits the foreground around it, as a button's label does. Setting
    /// `.foreground` here would pin it to the primary label colour instead.
    @ViewBuilder private var glyph: some View {
        let image = Image(nsImage: icon.image(side: size.rawValue + grow)).renderingMode(.template)
        if let color { image.foregroundStyle(color) } else { image }
    }
}
