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
                    Spacer()
                    Button(action: close) { IconView(icon: .close, size: .small, color: nil) }
                        .buttonStyle(.koe(.secondary, size: .small, iconOnly: true))
                        .hint("Close", shortcut: "Esc")
                        .accessibilityLabel("Close")
                }
                content
                    .frame(width: fitted.width, height: fitted.height)
                    .background(Palette.well)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
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
            Image(decorative: image, scale: 1).resizable().scaledToFit()
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
        image = await Self.image(of: annotation, maxSide: 3200)
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
