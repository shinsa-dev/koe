import CoreGraphics
import CoreText
import Foundation

/// The pin a comment leaves on its screenshot: a blue dot ringed in white inside a wide blue halo, where you
/// clicked, with the comment's number in it, so the agent sees exactly what the comment is about and which it is.
public enum PinMark {
    /// Shinsa's blue (`--primary-4`, light).
    static let blue = CGColor(srgbRed: 0, green: 0x7B / 255, blue: 0xFC / 255, alpha: 1)

    /// Where a point on the screen lands in a crop of it: `point` and `region` in screen points from the top left,
    /// `scale` the image's pixels per point. Nil when the point is outside the region.
    public static func location(of point: CGPoint, in region: CGRect, scale: CGFloat) -> CGPoint? {
        guard region.contains(point) else { return nil }
        return CGPoint(x: (point.x - region.minX) * scale, y: (point.y - region.minY) * scale)
    }

    /// The same point as fractions of the region, for the bundle's words.
    public static func place(of point: CGPoint, in region: CGRect, number: Int? = nil) -> PinPlace? {
        guard region.contains(point), region.width > 0, region.height > 0 else { return nil }
        return PinPlace(x: (point.x - region.minX) / region.width, y: (point.y - region.minY) / region.height,
                        number: number)
    }

    /// The image with a pin drawn at `point`, in pixels from its top left. `radius` is the dot's, in pixels.
    public static func draw(on image: CGImage, at point: CGPoint, radius: CGFloat, number: Int? = nil) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: bounds)
        // Core Graphics counts from the bottom left.
        let center = CGPoint(x: point.x, y: CGFloat(height) - point.y)
        let ring = radius * 1.35
        let halo = radius * 3.4
        let around = CGRect(x: center.x - halo, y: center.y - halo, width: halo * 2, height: halo * 2)
        context.setFillColor(blue.copy(alpha: 0.16) ?? blue)
        context.fillEllipse(in: around)
        context.setStrokeColor(blue.copy(alpha: 0.9) ?? blue)
        context.setLineWidth(max(1, radius * 0.3))
        context.strokeEllipse(in: around)
        context.setShadow(offset: CGSize(width: 0, height: -radius * 0.2), blur: radius * 0.8,
                          color: CGColor(gray: 0, alpha: 0.35))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillEllipse(in: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2))
        context.setShadow(offset: .zero, blur: 0)
        context.setFillColor(blue)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        if let number { write(number, in: context, at: center, radius: radius) }
        return context.makeImage()
    }

    private static func write(_ number: Int, in context: CGContext, at center: CGPoint, radius: CGFloat) {
        let text = "\(number)"
        let size = radius * (text.count > 1 ? 1.0 : 1.25)
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1)] as CFDictionary
        guard let string = CFAttributedStringCreate(nil, text as CFString, attributes) else { return }
        let line = CTLineCreateWithAttributedString(string)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.textPosition = CGPoint(x: center.x - ink.midX, y: center.y - ink.midY)
        CTLineDraw(line, context)
    }
}
