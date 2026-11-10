import AVFoundation
import AppKit
import KoeCore
import SwiftUI

/// One attachment opened large over a dimmed screen, the way Shinsa opens an asset: the picture, or the clip
/// playing in a loop with its controls. A click outside it, Esc or the close button puts it away.
struct AttachmentViewer: View {
    let annotation: Annotation
    let screen: CGSize
    let close: () -> Void
    @State private var image: CGImage?
    @State private var playback: ClipPlayback?
    @State private var shown = false

    static func shows(_ annotation: Annotation) -> Bool {
        switch annotation.kind {
        case .screenshot, .clip: true
        case .file, .note: false
        }
    }

    /// The screenshot itself, or a clip's first frame, no larger than `maxSide` pixels.
    static func image(of annotation: Annotation, maxSide: CGFloat) async -> CGImage? {
        switch annotation.kind {
        case .screenshot(let asset):
            let url = asset.url
            return await Task.detached {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                               kCGImageSourceThumbnailMaxPixelSize: maxSide] as CFDictionary
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
            }.value
        case .clip(let asset):
            return try? await ClipMovie.image(at: 0, of: asset.url, maxSide: maxSide)
        case .file, .note:
            return nil
        }
    }

    var body: some View {
        ZStack {
            Palette.scrim
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .opacity(shown ? 1 : 0)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(AttachmentLabel.title(of: annotation)).font(Typography.title).foregroundStyle(Palette.fg4)
                        Text(AttachmentLabel.detail(of: annotation)).font(Typography.meta).foregroundStyle(Palette.fg2)
                    }
                    .lineLimit(1)
                    .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button(action: close) { IconView(icon: .close, size: .small, color: nil) }
                        .buttonStyle(.koe(.secondary, size: .small, iconOnly: true))
                        .hint("Close", shortcut: "Esc")
                        .accessibilityLabel("Close")
                }
                .padding(.leading, 4)
                content
                    .frame(width: fitted.width, height: fitted.height)
                    .background(Palette.well)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                if let playback { ClipControls(playback: playback) }
            }
            // The card is as wide as its picture, never the screen.
            .frame(width: fitted.width)
            .padding(12)
            .floatingSurface(cornerRadius: 18, shadow: false)
            .scaleEffect(shown ? 1 : 0.9)
            .blur(radius: shown ? 0 : 6)
            .opacity(shown ? 1 : 0)
        }
        .frame(width: screen.width, height: screen.height)
        .task(id: annotation.id) { await load() }
        .onAppear { withAnimation(.spring(duration: 0.32, bounce: 0.18)) { shown = true } }
        .onDisappear { playback?.stop() }
    }

    @ViewBuilder private var content: some View {
        if let playback {
            ClipPlayerView(player: playback.player)
        } else if let image {
            ZoomableImage(image: image, size: fitted)
        }
    }

    /// The picture fitted into most of the screen, never drawn larger than it is.
    private var fitted: CGSize {
        let limit = CGSize(width: screen.width * 0.78, height: screen.height * 0.72)
        guard let image, image.width > 0, image.height > 0 else { return CGSize(width: 480, height: 300) }
        let size = CGSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
        let scale = min(1, limit.width / size.width, limit.height / size.height)
        return CGSize(width: max(240, size.width * scale), height: max(150, size.height * scale))
    }

    private func load() async {
        image = ThumbnailCache.shared.image(for: annotation.id)
        image = await Self.image(of: annotation, maxSide: 3200) ?? image
        guard case .clip(let asset) = annotation.kind else { return }
        let playback = ClipPlayback(url: asset.url)
        self.playback = playback
        playback.toggle()
    }
}

/// A clip playing in the viewer: it loops, and you can pause it, drag through it and slow it down.
@MainActor
@Observable
final class ClipPlayback {
    @ObservationIgnored let player: AVPlayer
    private(set) var playing = false
    private(set) var seconds = 0.0
    private(set) var duration = 0.0
    var speed = PlaybackSpeed.initial {
        didSet { if playing { player.rate = Float(speed.rawValue) } }
    }
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?

    init(url: URL) {
        player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .none
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.moved(to: time.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.player.seek(to: .zero)
                if self.playing { self.player.playImmediately(atRate: Float(self.speed.rawValue)) }
            }
        }
    }

    var fraction: Double { duration > 0 ? min(1, max(0, seconds / duration)) : 0 }

    func toggle() {
        playing.toggle()
        if playing { player.playImmediately(atRate: Float(speed.rawValue)) } else { player.pause() }
    }

    func seek(to fraction: Double) {
        guard duration > 0 else { return }
        seconds = fraction * duration
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 6000), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        player.pause()
        playing = false
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
    }

    private func moved(to time: Double) {
        guard time.isFinite else { return }
        seconds = time
        if let length = player.currentItem?.duration.seconds, length.isFinite, length > 0 { duration = length }
    }
}

/// The viewer's controls for a clip, the review's own: play or pause, where it is, a bar to drag, and the speeds.
private struct ClipControls: View {
    let playback: ClipPlayback

    var body: some View {
        HStack(spacing: 10) {
            Button(action: playback.toggle) {
                ZStack {
                    IconView(icon: playback.playing ? .pause : .play, size: .medium, color: nil)
                        .id(playback.playing)
                        .transition(GlyphSwap())
                }
                .animation(GlyphSwap.animation, value: playback.playing)
            }
            .buttonStyle(.koe(.outline, iconOnly: true))
            .hint(playback.playing ? "Pause" : "Play")
            .accessibilityLabel(playback.playing ? "Pause" : "Play")
            SeekBar(fraction: playback.fraction, seek: playback.seek)
                .accessibilityElement()
                .accessibilityLabel("Position in the clip")
            Text(String(format: "%.1f of %.1f s", playback.seconds, playback.duration))
                .font(Typography.meta.monospacedDigit())
                .foregroundStyle(Palette.fg2)
                .fixedSize()
            SegmentedTabs(
                items: PlaybackSpeed.allCases.map { (value: $0, label: $0.label) },
                selection: Binding(get: { playback.speed }, set: { playback.speed = $0 })
            )
            .fixedSize()
        }
    }
}

/// A picture you can zoom: pinch, double-click, or turn a mouse wheel (⌘ and scroll on a trackpad); scroll or drag
/// to move around once it is larger. AppKit's own scroll view, since it zooms about the pointer.
private struct ZoomableImage: NSViewRepresentable {
    let image: CGImage
    let size: CGSize

    func makeNSView(context: Context) -> ZoomScrollView {
        let scroll = ZoomScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.allowsMagnification = true
        scroll.minMagnification = 1
        scroll.maxMagnification = 8
        scroll.scrollerStyle = .overlay
        let picture = NSImageView()
        picture.imageScaling = .scaleAxesIndependently
        scroll.documentView = picture
        return scroll
    }

    func updateNSView(_ scroll: ZoomScrollView, context: Context) {
        guard let picture = scroll.documentView as? NSImageView else { return }
        picture.image = NSImage(cgImage: image, size: size)
        if picture.frame.size != size {
            scroll.magnification = 1
            picture.frame = CGRect(origin: .zero, size: size)
        }
    }
}

final class ZoomScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        // A mouse wheel has no pinch, so it zooms; so does ⌘ with a trackpad scroll.
        guard !event.hasPreciseScrollingDeltas || event.modifierFlags.contains(.command) else {
            return super.scrollWheel(with: event)
        }
        let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
        let target = min(maxMagnification, max(minMagnification, magnification * (1 + step)))
        setMagnification(target, centeredAt: contentView.convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2 else { return drag(from: event) }
        let point = contentView.convert(event.locationInWindow, from: nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            animator().setMagnification(magnification > 1 ? 1 : 2.5, centeredAt: point)
        }
    }

    private func drag(from event: NSEvent) {
        guard magnification > 1, let window else { return }
        var last = event.locationInWindow
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type == .leftMouseDragged {
            let here = next.locationInWindow
            let move = CGPoint(x: (last.x - here.x) / magnification, y: (last.y - here.y) / magnification)
            let origin = contentView.bounds.origin
            let flipped = documentView?.isFlipped ?? false
            contentView.scroll(to: contentView.constrainBoundsRect(
                CGRect(origin: CGPoint(x: origin.x + move.x, y: origin.y + (flipped ? -move.y : move.y)),
                       size: contentView.bounds.size)).origin)
            reflectScrolledClipView(contentView)
            last = here
        }
    }
}

/// The small pictures of what a session holds, made as each thing is attached so the list never opens on a
/// placeholder.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    static let side: CGFloat = 176
    private var images: [UUID: CGImage] = [:]

    func image(for id: UUID) -> CGImage? { images[id] }

    func warm(_ annotations: [Annotation]) async {
        let ids = Set(annotations.map(\.id))
        images = images.filter { ids.contains($0.key) }
        for annotation in annotations where images[annotation.id] == nil {
            images[annotation.id] = await AttachmentViewer.image(of: annotation, maxSide: Self.side)
        }
    }
}
