import AppKit
import KoeCore
import SwiftUI

/// What shows on the screen while a clip records: a red outline around the region. The clock and the buttons that
/// stop or discard it are in the pill. The outline is not in the clip, since recordings leave Koe's windows out.
@MainActor
final class RecordingIndicator {
    private let outline: NSPanel

    /// `region` is in AppKit's global space.
    init(region: NSRect) {
        outline = NSPanel(contentRect: region.insetBy(dx: -3, dy: -3), styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        outline.isFloatingPanel = true
        outline.level = .screenSaver
        outline.ignoresMouseEvents = true
        outline.isOpaque = false
        outline.backgroundColor = .clear
        outline.hasShadow = false
        outline.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        outline.isReleasedWhenClosed = false
        outline.contentView = NSHostingView(rootView: Outline())

    }

    func show() {
        outline.orderFrontRegardless()
    }

    func close() {
        outline.close()
    }
}

private struct Outline: View {
    var body: some View {
        Rectangle()
            .strokeBorder(Tone.red.ink, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .padding(1)
    }
}
