import AppKit
import KoeCore
import SwiftUI

/// What the session holds, in the order you added it, just above the pill: each with a preview, what it is and
/// where it came from, and a button that takes it out.
struct AttachmentList: View {
    static let width: CGFloat = 340
    let sessions: SessionController
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Attached so far")
                    .font(Typography.label)
                    .foregroundStyle(Palette.fg2)
                Spacer()
                Button(action: close) { IconView(icon: .close, size: .small, color: nil) }
                    .buttonStyle(.koe(.bare, size: .small, iconOnly: true))
                    .hint("Close", shortcut: "Esc")
            }
            .padding(.leading, 6)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(sessions.attachments) { annotation in
                        AttachmentRow(annotation: annotation) { sessions.remove(annotation.id) }
                            .transition(GlyphSwap())
                    }
                }
            }
            .frame(maxHeight: 280)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(width: Self.width)
        .floatingSurface(cornerRadius: 16)
        .animation(.spring(duration: 0.3, bounce: 0.15), value: sessions.attachments.map(\.id))
    }
}

private struct AttachmentRow: View {
    let annotation: Annotation
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
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
                .buttonStyle(.koe(.bare, size: .small, iconOnly: true))
                .hint("Take it out")
                .accessibilityLabel("Remove \(AttachmentLabel.title(of: annotation))")
        }
        .padding(6)
        .background(hovering ? Palette.press : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
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
