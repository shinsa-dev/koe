import AppKit
import KoeCore
@preconcurrency import ScreenCaptureKit

/// One screen as it looked when Koe froze it.
struct FrozenScreen {
    let screen: NSScreen
    let image: CGImage
    /// The screen in Quartz space, the one `WindowInfo` frames use.
    let frame: CGRect
}

/// Every screen and the windows on them at one moment, with Koe's own windows left out.
struct Freeze {
    let screens: [FrozenScreen]
    let windows: [WindowInfo]
    let frontApp: String?
}

enum ScreenFreezer {
    enum Failure: LocalizedError {
        case nothingCaptured

        var errorDescription: String? {
            "Koe couldn't capture the screen. Check that screen recording is allowed for Koe in System Settings."
        }
    }

    @MainActor
    static func freeze() async throws -> Freeze {
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName
        let windows = onScreenWindows()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let koe = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        var screens: [FrozenScreen] = []
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == number }) else { continue }
            let filter = SCContentFilter(display: display, excludingApplications: koe, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            screens.append(FrozenScreen(
                screen: screen, image: image, frame: ScreenGeometry.flip(screen.frame, mainScreenHeight: mainHeight)
            ))
        }
        guard !screens.isEmpty else { throw Failure.nothingCaptured }
        return Freeze(screens: screens, windows: windows, frontApp: frontApp)
    }

    /// Front to back, as CGWindowList orders them. Window titles need the screen recording permission.
    private static func onScreenWindows() -> [WindowInfo] {
        let own = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.compactMap { entry in
            guard (entry[kCGWindowOwnerPID as String] as? pid_t) != own,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return WindowInfo(
                app: entry[kCGWindowOwnerName as String] as? String ?? "",
                title: entry[kCGWindowName as String] as? String,
                frame: frame,
                layer: entry[kCGWindowLayer as String] as? Int ?? 0
            )
        }
    }
}

enum PNG {
    static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
