import CoreGraphics

/// Rects for picking a region of a frozen screen. Everything here is in Quartz space, the one CGWindowList uses:
/// points, y down from the top of the main screen. A screen's own space is the same with its top-left at zero.
public enum ScreenGeometry {
    /// A press that moves less than this is a click, which picks the window under it.
    public static let clickTolerance: CGFloat = 4

    /// AppKit's global space has y up from the bottom of the main screen; this turns a rect from one space into the
    /// other (it is its own inverse).
    public static func flip(_ rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func selection(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    public static func isClick(from start: CGPoint, to end: CGPoint) -> Bool {
        abs(end.x - start.x) < clickTolerance && abs(end.y - start.y) < clickTolerance
    }

    /// The pixels of an image captured from a screen `screenSize` points large that show `rect` (in the screen's own
    /// space), on whole pixels and inside the image. Nil when nothing of it is on the screen.
    public static func pixelRect(of rect: CGRect, screenSize: CGSize, imageSize: CGSize) -> CGRect? {
        guard screenSize.width > 0, screenSize.height > 0 else { return nil }
        let scaleX = imageSize.width / screenSize.width
        let scaleY = imageSize.height / screenSize.height
        let pixels = CGRect(x: rect.minX * scaleX, y: rect.minY * scaleY, width: rect.width * scaleX, height: rect.height * scaleY)
            .integral
            .intersection(CGRect(origin: .zero, size: imageSize))
        return pixels.isNull || pixels.width < 1 || pixels.height < 1 ? nil : pixels
    }

    /// The pixel size to record a region of `size` points at `scale`: whole and even, since H.264 needs even sides,
    /// and at least 2 × 2.
    public static func recordingPixels(of size: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        func even(_ points: CGFloat) -> Int {
            let pixels = Int((points * max(1, scale)).rounded())
            return max(2, pixels - pixels % 2)
        }
        return (even(size.width), even(size.height))
    }

    /// Where a note card of `cardSize` goes for a selection on a screen `bounds` large: under it, above it when there
    /// is no room below, or inside its bottom edge when it fills the screen. Its left edge follows the selection's
    /// and it always stays `margin` inside the screen.
    public static func cardOrigin(for selection: CGRect, cardSize: CGSize, in bounds: CGRect, gap: CGFloat = 8,
                                  margin: CGFloat = 12) -> CGPoint {
        let below = selection.maxY + gap
        let above = selection.minY - gap - cardSize.height
        let y: CGFloat = if below + cardSize.height <= bounds.maxY - margin {
            below
        } else if above >= bounds.minY + margin {
            above
        } else {
            selection.maxY - margin - cardSize.height
        }
        let x = min(max(selection.minX, bounds.minX + margin), bounds.maxX - margin - cardSize.width)
        return CGPoint(x: max(bounds.minX + margin, x), y: max(bounds.minY + margin, y))
    }
}

/// A window on screen when Koe froze it, front to back as CGWindowList lists them.
public struct WindowInfo: Sendable, Equatable {
    public var app: String
    public var title: String?
    /// In Quartz space.
    public var frame: CGRect
    /// 0 is a normal window; menus, the Dock and the menu bar sit on higher layers.
    public var layer: Int

    public init(app: String, title: String? = nil, frame: CGRect, layer: Int = 0) {
        self.app = app
        self.title = title
        self.frame = frame
        self.layer = layer
    }

    public var source: CaptureSource {
        CaptureSource(app: app, window: title?.isEmpty == false ? title : nil)
    }
}

extension [WindowInfo] {
    /// The frontmost normal window under `point`: what a click on the frozen screen picks.
    public func topmost(at point: CGPoint) -> WindowInfo? {
        first { $0.layer == 0 && $0.frame.contains(point) }
    }

    /// The window a region was taken from: the frontmost one under its centre.
    public func source(of region: CGRect) -> WindowInfo? {
        topmost(at: CGPoint(x: region.midX, y: region.midY))
    }
}
