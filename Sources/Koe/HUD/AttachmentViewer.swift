import AVFoundation
import AppKit
import KoeCore
import SwiftUI

/// One attachment opened large over a dimmed screen, the way Shinsa opens an asset: the picture, or the clip
/// playing in a loop. A click outside it, Esc or the close button puts it away.
struct AttachmentViewer: View {
    let annotation: Annotation
    let screen: CGSize
    let close: () -> Void
    @State private var image: CGImage?
    @State private var player: AVPlayer?
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
        .onDisappear { player?.pause() }
    }

    @ViewBuilder private var content: some View {
        if let player {
            ClipPlayerView(player: player)
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
        let player = AVPlayer(url: asset.url)
        player.isMuted = true
        player.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                               object: player.currentItem, queue: .main) { [weak player] _ in
            MainActor.assumeIsolated {
                player?.seek(to: .zero)
                player?.play()
            }
        }
        self.player = player
        player.play()
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
