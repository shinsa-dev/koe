import AppKit
import KoeCore
import SwiftUI

/// What the session holds, newest first, just above the pill: each with a preview, what it is and where it came
/// from, and a button that takes it out. Clicking a picture or a clip opens it in the viewer; the list never grows.
struct AttachmentList: View {
    static let width: CGFloat = 340
    /// The window it sits at the bottom of. The placing is inside the animation, so the card's bottom edge
    /// holds while its height changes; placed from outside, it jumped down first and shrank after.
    static let stage = CGSize(width: width + 40, height: 440)
    let sessions: SessionController
    let open: (Annotation) -> Void
    let close: () -> Void
    @State private var shown = false
    @State private var removing = false

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
            // The list gives its own height, so it shrinks on the rows' spring with its bottom edge held.
            FadingScroll(maxHeight: 340, height: Self.listHeight(rows: sessions.attachments.count)) {
                VStack(spacing: Self.rowGap) {
                    ForEach(sessions.attachments.reversed()) { annotation in
                        AttachmentRow(annotation: annotation) {
                            open(annotation)
                        } remove: {
                            remove(annotation)
                        }
                        .frame(height: Self.rowHeight)
                        .transition(RowChange.change)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(8)
        .frame(width: Self.width)
        .floatingSurface(cornerRadius: 16, shadow: false)
        .padding(.bottom, 20)
        .frame(width: Self.stage.width, height: Self.stage.height, alignment: .bottom)
        .animation(RowChange.animation(removing: removing), value: sessions.attachments.map(\.id))
        .onChange(of: sessions.attachments.count) { removing = false }
        // It grows out of the pill below it, the way the pill itself arrives.
        .growsIn(shown)
        .onAppear { withAnimation(GrowIn.animation) { shown = true } }
    }

    private static let rowHeight: CGFloat = 42
    private static let rowGap: CGFloat = 2

    private static func listHeight(rows: Int) -> CGFloat {
        CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) * rowGap
    }

    /// Taking out the last one puts the whole list away in one motion, the row still in it.
    private func remove(_ annotation: Annotation) {
        guard sessions.attachments.count == 1 else {
            removing = true
            withAnimation(RowChange.animation(removing: true)) { sessions.remove(annotation.id) }
            return
        }
        withAnimation(GrowIn.exit) { shown = false } completion: {
            sessions.remove(annotation.id)
            close()
        }
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
