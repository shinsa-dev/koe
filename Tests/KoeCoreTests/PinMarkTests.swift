import CoreGraphics
import KoeCore
import Testing

struct PinMarkTests {
    @Test func aPointLandsInTheCropScaledToItsPixels() {
        let region = CGRect(x: 100, y: 50, width: 400, height: 300)
        #expect(PinMark.location(of: CGPoint(x: 150, y: 80), in: region, scale: 2) == CGPoint(x: 100, y: 60))
    }

    @Test func aPointOutsideTheRegionHasNoPin() {
        let region = CGRect(x: 100, y: 50, width: 400, height: 300)
        #expect(PinMark.location(of: CGPoint(x: 20, y: 80), in: region, scale: 2) == nil)
    }

    @Test func aPointIsPlacedAsFractionsOfTheRegion() {
        let region = CGRect(x: 100, y: 50, width: 400, height: 300)
        let place = PinMark.place(of: CGPoint(x: 300, y: 125), in: region)
        #expect(place == PinPlace(x: 0.5, y: 0.25))
        #expect(place?.words == "50% across and 25% down")
        #expect(PinMark.place(of: CGPoint(x: 20, y: 80), in: region) == nil)
    }

    @Test func theHaloTintsTheRingAroundTheDot() throws {
        let image = try #require(Self.white(width: 200, height: 100))
        let pinned = try #require(PinMark.draw(on: image, at: CGPoint(x: 100, y: 50), radius: 10))
        let inHalo = try #require(Self.pixel(of: pinned, x: 125, y: 50))
        #expect(inHalo[2] > inHalo[0])
    }

    @Test func thePinIsBlueAtItsCentreAndLeavesTheRestAlone() throws {
        let image = try #require(Self.white(width: 200, height: 100))
        let pinned = try #require(PinMark.draw(on: image, at: CGPoint(x: 50, y: 30), radius: 10))
        let centre = try #require(Self.pixel(of: pinned, x: 50, y: 30))
        #expect(centre[2] > 200 && centre[0] < 40)
        let corner = try #require(Self.pixel(of: pinned, x: 190, y: 90))
        #expect(corner.allSatisfy { $0 > 250 })
    }

    @Test func aNumberedPinCarriesItsNumberInWhiteAndSaysItInWords() throws {
        let image = try #require(Self.white(width: 200, height: 100))
        let plain = try #require(PinMark.draw(on: image, at: CGPoint(x: 100, y: 50), radius: 20))
        let numbered = try #require(PinMark.draw(on: image, at: CGPoint(x: 100, y: 50), radius: 20, number: 1))
        let whiteInDot = { (pin: CGImage) in
            (88...112).flatMap { x in (38...62).map { (x, $0) } }
                .filter { Self.pixel(of: pin, x: $0.0, y: $0.1)?.prefix(3).allSatisfy { $0 > 230 } == true }.count
        }
        #expect(whiteInDot(plain) == 0)
        #expect(whiteInDot(numbered) > 20)
        let place = PinMark.place(of: CGPoint(x: 300, y: 125), in: CGRect(x: 100, y: 50, width: 400, height: 300), number: 2)
        #expect(place?.number == 2)
    }

    private static func white(width: Int, height: Int) -> CGImage? {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(CGColor(gray: 1, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }

    /// The red, green and blue of the pixel at `x`, `y` from the top left.
    private static func pixel(of image: CGImage, x: Int, y: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return Array(bytes.prefix(3))
    }
}
