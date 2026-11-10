import AppKit
import KoeCore
import SwiftUI

/// What the session holds, newest first, just above the pill: each with a preview, what it is and where it came
/// from, and a button that takes it out. Clicking a picture or a clip opens it in the viewer; the list never grows.
struct AttachmentList: View {
    static let width: CGFloat = 340
    let sessions: SessionController
    let open: (Annotation) -> Void
    let close: () -> Void
    @State private var shown = false

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
            // The same inset as a row, so the close button sits exactly above the remove buttons.
            .padding(.horizontal, 6)
            .padding(.top, 2)
            FadingScroll(maxHeight: 340) {
                VStack(spacing: 2) {
                    ForEach(sessions.attachments.reversed()) { annotation in
                        AttachmentRow(annotation: annotation) {
                            open(annotation)
                        } remove: {
                            withAnimation(RowChange.animation) { sessions.remove(annotation.id) }
                        }
                        .transition(RowChange.change)
                    }
                }
            }
        }
        .padding(8)
        .frame(width: Self.width)
        .floatingSurface(cornerRadius: 16, shadow: false)
        .animation(RowChange.animation, value: sessions.attachments.map(\.id))
        // It grows out of the pill below it, the way the pill itself arrives.
        .scaleEffect(shown ? 1 : 0.9, anchor: .bottom)
        .blur(radius: shown ? 0 : 6)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(duration: 0.32, bounce: 0.2)) { shown = true } }
    }
}

private struct AttachmentRow: View {
    let annotation: Annotation
    let open: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    private var opens: Bool { AttachmentViewer.shows(annotation) }

    var body: some View {
        HStack(spacing: 10) {
            AttachmentThumbnail(annotation: annotation)
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
        .padding(6)
        .background(opens && hovering ? Palette.press : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { if opens { open() } }
        .accessibilityAddTraits(opens ? .isButton : [])
        .accessibilityHint(opens ? "Opens it larger" : "")
    }
}

/// The small picture in a row: the screenshot itself, a clip's first frame, or a glyph for a file.
private struct AttachmentThumbnail: View {
    let annotation: Annotation
    @State private var image: CGImage?

    init(annotation: Annotation) {
        self.annotation = annotation
        _image = State(initialValue: ThumbnailCache.shared.image(for: annotation.id))
    }

    var body: some View {
        ZStack {
            Palette.press
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                IconView(icon: icon, size: .small, color: Palette.icon2)
            }
        }
        .frame(width: 44, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.hudRing, lineWidth: 1))
        .task(id: annotation.id) {
            guard image == nil else { return }
            image = await AttachmentViewer.image(of: annotation, maxSide: ThumbnailCache.side)
        }
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
