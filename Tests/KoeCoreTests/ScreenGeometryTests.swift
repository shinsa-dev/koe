import CoreGraphics
import KoeCore
import Testing

struct ScreenGeometryTests {
    @Test func flipTurnsAppKitSpaceIntoQuartzSpaceAndBack() {
        let appKit = CGRect(x: 10, y: 100, width: 50, height: 20)
        let quartz = ScreenGeometry.flip(appKit, mainScreenHeight: 1000)
        #expect(quartz == CGRect(x: 10, y: 880, width: 50, height: 20))
        #expect(ScreenGeometry.flip(quartz, mainScreenHeight: 1000) == appKit)
    }

    @Test func aSelectionIsTheSameWhicheverWayYouDrag() {
        let rect = CGRect(x: 10, y: 20, width: 90, height: 60)
        #expect(ScreenGeometry.selection(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 100, y: 80)) == rect)
        #expect(ScreenGeometry.selection(from: CGPoint(x: 100, y: 80), to: CGPoint(x: 10, y: 20)) == rect)
    }

    @Test func aPressThatBarelyMovesIsAClick() {
        #expect(ScreenGeometry.isClick(from: .zero, to: CGPoint(x: 3, y: -3)))
        #expect(!ScreenGeometry.isClick(from: .zero, to: CGPoint(x: 4, y: 0)))
    }

    @Test func pixelRectScalesToTheImageOnWholePixels() {
        let rect = ScreenGeometry.pixelRect(
            of: CGRect(x: 10.25, y: 20, width: 100, height: 50), screenSize: CGSize(width: 1000, height: 500),
            imageSize: CGSize(width: 2000, height: 1000)
        )
        #expect(rect == CGRect(x: 20, y: 40, width: 201, height: 100))
    }

    @Test func pixelRectClipsToTheImage() {
        let rect = ScreenGeometry.pixelRect(
            of: CGRect(x: 900, y: -50, width: 300, height: 100), screenSize: CGSize(width: 1000, height: 500),
            imageSize: CGSize(width: 1000, height: 500)
        )
        #expect(rect == CGRect(x: 900, y: 0, width: 100, height: 50))
    }

    @Test func pixelRectIsNilOffScreenOrForAnEmptyScreen() {
        let size = CGSize(width: 100, height: 100)
        #expect(ScreenGeometry.pixelRect(of: CGRect(x: 200, y: 0, width: 10, height: 10), screenSize: size, imageSize: size) == nil)
        #expect(ScreenGeometry.pixelRect(of: CGRect(x: 0, y: 0, width: 10, height: 10), screenSize: .zero, imageSize: size) == nil)
    }

    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let card = CGSize(width: 300, height: 80)

    @Test func theNoteCardSitsUnderTheSelection() {
        let origin = ScreenGeometry.cardOrigin(for: CGRect(x: 100, y: 100, width: 400, height: 200), cardSize: card, in: screen)
        #expect(origin == CGPoint(x: 100, y: 308))
    }

    @Test func theNoteCardGoesAboveWhenThereIsNoRoomBelow() {
        let origin = ScreenGeometry.cardOrigin(for: CGRect(x: 100, y: 500, width: 400, height: 250), cardSize: card, in: screen)
        #expect(origin == CGPoint(x: 100, y: 412))
    }

    @Test func theNoteCardGoesInsideASelectionThatFillsTheScreen() {
        let origin = ScreenGeometry.cardOrigin(for: screen, cardSize: card, in: screen)
        #expect(origin == CGPoint(x: 12, y: 708))
    }

    @Test func theNoteCardStaysOnScreenAtTheRightEdge() {
        let origin = ScreenGeometry.cardOrigin(for: CGRect(x: 900, y: 100, width: 90, height: 50), cardSize: card, in: screen)
        #expect(origin.x == 688)
    }
}

struct WindowInfoTests {
    private let windows = [
        WindowInfo(app: "Menu", frame: CGRect(x: 0, y: 0, width: 500, height: 500), layer: 25),
        WindowInfo(app: "Safari", title: "Settings", frame: CGRect(x: 100, y: 100, width: 200, height: 200)),
        WindowInfo(app: "Finder", title: "", frame: CGRect(x: 0, y: 0, width: 400, height: 400)),
    ]

    @Test func aClickPicksTheFrontmostNormalWindow() {
        #expect(windows.topmost(at: CGPoint(x: 150, y: 150))?.app == "Safari")
        #expect(windows.topmost(at: CGPoint(x: 350, y: 350))?.app == "Finder")
        #expect(windows.topmost(at: CGPoint(x: 450, y: 450)) == nil)
    }

    @Test func aRegionComesFromTheWindowUnderItsCentre() {
        #expect(windows.source(of: CGRect(x: 120, y: 120, width: 40, height: 40))?.app == "Safari")
    }

    @Test func anUntitledWindowNamesOnlyItsApp() {
        #expect(windows[2].source == CaptureSource(app: "Finder"))
        #expect(windows[1].source == CaptureSource(app: "Safari", window: "Settings"))
    }
}
