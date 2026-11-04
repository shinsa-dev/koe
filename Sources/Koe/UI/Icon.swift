import AppKit
import SwiftUI

/// Every glyph Koe draws, as an SF Symbol, so it matches the rest of macOS.
enum Icon: String, CaseIterable {
    case microphone = "mic"
    case screenCapture = "rectangle.dashed.badge.record"
    case cursorClick = "cursorarrow.click.2"
    case check = "checkmark.circle.fill"
    case checkmark = "checkmark"
    case accessibility = "accessibility"
    case settings = "gearshape"
    case permissions = "hand.raised"
    case shortcuts = "command"
    case stop = "stop.fill"
    case close = "xmark"
    case paperclip = "paperclip"
    case video = "video"
    case play = "play.fill"
    case pause = "pause.fill"
    case previous = "chevron.left"
    case next = "chevron.right"
    case add = "plus"
    case trash = "trash"

    enum Size: CGFloat {
        case tiny = 10, small = 12, medium = 14, large = 18
    }

    /// A template image at `side` points, for AppKit places such as the menu bar.
    @MainActor func image(side: CGFloat) -> NSImage {
        let image = NSImage(systemSymbolName: rawValue, accessibilityDescription: String(describing: self))?
            .withSymbolConfiguration(.init(pointSize: side, weight: .regular)) ?? NSImage()
        image.isTemplate = true
        return image
    }
}

struct IconView: View {
    let icon: Icon
    var size: Icon.Size = .small
    /// nil takes the surrounding foreground, as a glyph inside a button does.
    var color: Color? = Palette.icon2
    var weight: Font.Weight = .medium

    @ViewBuilder var body: some View {
        let glyph = Image(systemName: icon.rawValue)
            .font(.system(size: size.rawValue, weight: weight))
            .accessibilityHidden(true)
        if let color { glyph.foregroundStyle(color) } else { glyph }
    }
}
