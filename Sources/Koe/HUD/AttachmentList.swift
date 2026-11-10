import AppKit
import KoeCore
import SwiftUI

/// What the session holds, in the order you added it, just above the pill: each with a preview, what it is and
/// where it came from, and a button that takes it out. Clicking a picture or a clip opens it larger in place.
struct AttachmentList: View {
    static let width: CGFloat = 340
    let sessions: SessionController
    let close: () -> Void
    @State private var expanded: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Attached so far")
                    .font(Typography.label)
                    .foregroundStyle(Palette.fg2)
                Spacer()
                Button(action: close) { IconView(icon: .close, size: .small, color: nil) }
                    .buttonStyle(.koe(.secondary, size: .small, iconOnly: true))
                    .hint("Close", shortcut: "Esc")
                    .accessibilityLabel("Close")
            }
            .padding(.leading, 6)
            FadingScroll(maxHeight: 340) {
                VStack(spacing: 2) {
                    ForEach(sessions.attachments) { annotation in
                        AttachmentRow(annotation: annotation, expanded: expanded == annotation.id) {
                            expanded = expanded == annotation.id ? nil : annotation.id
                        } remove: {
                            sessions.remove(annotation.id)
                        }
                        .transition(GlyphSwap())
                    }
                }
            }
        }
        .padding(8)
        .frame(width: Self.width)
        .floatingSurface(cornerRadius: 16, shadow: false)
        .animation(.spring(duration: 0.3, bounce: 0.15), value: sessions.attachments.map(\.id))
        .animation(.spring(duration: 0.3, bounce: 0.12), value: expanded)
    }
}

private struct AttachmentRow: View {
    let annotation: Annotation
    let expanded: Bool
    let toggle: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    /// A picture or a clip can open larger; a dropped file has nothing to show.
    private var opens: Bool {
        switch annotation.kind {
        case .screenshot, .clip: true
        case .file, .note: false
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Preview(annotation: annotation)
                VStack(alignment: .leading, spacing: -2) {
                    Text(AttachmentLabel.title(of: annotation))
                        .font(Typography.label)
                        .foregroundStyle(Palette.fg4)
                    Text(AttachmentLabel.detail(of: annotation))
                        .font(Typography.meta)
                        .foregroundStyle(Palette.fg2)
                }
                .lineLimit(1)
                .truncationMode(.middle)
                Spacer(minLength: 4)
                Button(action: remove) { IconView(icon: .trash, size: .small, color: nil) }
                    .buttonStyle(.koe(.destructiveGhost, size: .small, iconOnly: true))
                    .hint("Take it out")
                    .accessibilityLabel("Remove \(AttachmentLabel.title(of: annotation))")
            }
            if expanded, opens {
                LargePreview(annotation: annotation).transition(GlyphSwap())
            }
        }
        .padding(6)
        .background(opens && hovering ? Palette.press : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { if opens { toggle() } }
        .accessibilityAddTraits(opens ? .isButton : [])
        .accessibilityHint(opens ? (expanded ? "Shows it smaller" : "Shows it larger") : "")
    }
}

/// The attachment at the list's full width: the picture itself, or a clip's first frame.
private struct LargePreview: View {
    let annotation: Annotation
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else {
                Palette.press.frame(height: 120)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 200)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .task(id: annotation.id) { image = await load() }
    }

    private func load() async -> CGImage? {
        switch annotation.kind {
        case .screenshot(let asset):
            let url = asset.url
            return await Task.detached { NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }.value
        case .clip(let asset):
            return try? await ClipMovie.image(at: 0, of: asset.url, maxSide: 1280)
        case .file, .note:
            return nil
        }
    }
}

private struct Preview: View {
    let annotation: Annotation

    var body: some View {
        Group {
            if case .screenshot(let asset) = annotation.kind, let image = NSImage(contentsOf: asset.url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Palette.press
                    IconView(icon: icon, size: .small, color: Palette.icon2)
                }
            }
        }
        .frame(width: 44, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.hudRing, lineWidth: 1))
    }

    private var icon: Icon {
        switch annotation.kind {
        case .screenshot: .screenshot
        case .clip: .video
        case .file: .file
        case .note: .comment
        }
    }
}
