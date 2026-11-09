import AppKit
import KoeCore
import SwiftUI

/// What shows while a clip records: a red outline around the region, and a card next to it with the clock and the
/// button that stops it. Neither is in the clip, since recordings leave Koe's windows out, and neither takes focus.
@MainActor
final class RecordingIndicator {
    private let outline: NSPanel
    private let card: ToolPanel

    /// `region` is in AppKit's global space.
    init(region: NSRect, on screen: NSScreen, limit: AudioTime, stop: @escaping () -> Void) {
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

        // Room around the card for its shadow, which the panel would otherwise clip into a grey box.
        let inset: CGFloat = 16
        let size = NSSize(width: 360, height: 34 + inset * 2)
        let visible = screen.visibleFrame
        let above = region.maxY + 8 + 34 <= visible.maxY
        let y = above ? region.maxY + 8 - inset : max(visible.minY, region.minY - 8 - size.height + inset)
        let x = min(max(region.minX - 3 - inset, visible.minX), visible.maxX - size.width)
        card = ToolPanel(frame: NSRect(origin: NSPoint(x: x, y: y), size: size), level: .screenSaver)
        card.host(RecordingCard(started: Date(), limit: limit, stop: stop)
            .padding(inset)
            .frame(width: size.width, height: size.height, alignment: .leading))
    }

    func show() {
        outline.orderFrontRegardless()
        card.orderFrontRegardless()
    }

    func close() {
        outline.close()
        card.close()
    }
}

private struct Outline: View {
    var body: some View {
        Rectangle()
            .strokeBorder(Tone.red.ink, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .padding(1)
    }
}

private struct RecordingCard: View {
    let started: Date
    let limit: AudioTime
    let stop: () -> Void
    @State private var dim = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Tone.red.ink)
                .frame(width: 8, height: 8)
                .opacity(dim ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dim)
                .onAppear { dim = true }
                .padding(.leading, 4)
            Text("Recording")
                .font(Typography.rowTitle)
                .foregroundStyle(Palette.fg4)
            TimelineView(.periodic(from: started, by: 1)) { context in
                Text("\(Elapsed.clock(context.date.timeIntervalSince(started))) of \(Elapsed.clock(limit))")
                    .font(Typography.meta.monospacedDigit())
                    .foregroundStyle(Palette.fg2)
            }
            Spacer(minLength: 4)
            Button(action: stop) {
                HStack(spacing: 4) {
                    IconView(icon: .stop, size: .small, color: nil)
                    Text("Stop")
                }
                .padding(.leading, -2)
            }
            .buttonStyle(.koe(.outline, size: .small))
            .hint("Stop recording", shortcut: KeyCombo.clip.displayName)
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .frame(height: 34)
        .floatingSurface(cornerRadius: 17)
        .fixedSize()
    }
}
