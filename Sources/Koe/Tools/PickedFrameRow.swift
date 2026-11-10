import KoeCore
import SwiftUI

/// One picked frame: its picture, when it showed, and what you said about it. Before you speak it offers to
/// listen; afterwards it shows your words, with say it again beside remove on the right. While it listens that
/// button is the blue stop.
struct PickedFrameRow: View {
    let pick: PickedFrame
    let thumbnail: CGImage?
    let talking: Bool
    /// What was said about this frame so far; nil when nothing was.
    let note: () -> String?
    /// What has been heard of the note being said now.
    let live: () -> String?
    let talk: () -> Void
    let show: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: show) {
                Group {
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1).resizable().scaledToFill()
                    } else {
                        Palette.well
                    }
                }
                .frame(width: 56, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .hint("Show this frame")
            Text(String(format: "%.2f s", pick.time))
                .font(Typography.meta.monospacedDigit())
                .foregroundStyle(Palette.fg2)
                .fixedSize()
                .padding(.trailing, 6)
            ZStack(alignment: .leading) {
                if talking {
                    // Your words show as they are heard, so they are already there when you click done.
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        let heard = live() ?? ""
                        Text(heard.isEmpty ? "Listening, click when done" : heard)
                            .font(Typography.meta)
                            .foregroundStyle(Palette.fg2)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .shimmer()
                    .transition(GlyphSwap())
                } else if pick.voice == nil {
                    talkButton.transition(GlyphSwap())
                } else {
                    spokenNote.transition(GlyphSwap())
                }
            }
            .animation(GlyphSwap.animation, value: talking)
            .animation(GlyphSwap.animation, value: pick.voice == nil)
            Spacer(minLength: 0)
            if talking || pick.voice != nil {
                Button(action: talk) {
                    ZStack {
                        IconView(icon: talking ? .stop : .retake, size: .small, color: nil)
                            .id(talking)
                            .transition(GlyphSwap())
                    }
                    .animation(GlyphSwap.animation, value: talking)
                }
                .buttonStyle(.koe(talking ? .primary : .secondary, size: .small, iconOnly: true))
                .hint(talking ? "Stop and keep what you said" : "Say it again")
                .accessibilityLabel(talking ? "Stop listening" : "Say this frame's note again")
                .transition(GlyphSwap())
            }
            Button(action: remove) { IconView(icon: .trash, size: .small, color: nil) }
                .buttonStyle(.koe(.destructiveGhost, size: .small, iconOnly: true))
                .hint("Remove this frame")
                .accessibilityLabel("Remove frame at \(String(format: "%.2f", pick.time)) seconds")
        }
        .animation(GlyphSwap.animation, value: pick.voice == nil)
    }

    private var talkButton: some View {
        Button(action: talk) {
            HStack(spacing: 6) {
                IconView(icon: .microphone, size: .small, color: nil)
                Text("Talk about this frame")
            }
            .padding(.leading, -2)
        }
        .buttonStyle(.koe(.secondary, size: .small))
        .hint("What you say next becomes this frame's note")
    }

    /// Your words about the frame, quiet like the time beside them; "Note recorded" until the model has them.
    private var spokenNote: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let text = note() ?? ""
            Text(text.isEmpty ? "Note recorded" : text)
                .font(Typography.meta)
                .foregroundStyle(Palette.fg2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// How a glyph or a short label swaps for another: the old one shrinks, blurs and fades as the new one grows in,
/// quickly, so the control answers at once.
struct GlyphSwap: Transition {
    static let animation = Animation.spring(duration: 0.18, bounce: 0.1)

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(phase.isIdentity ? 1 : 0.6)
            .blur(radius: phase.isIdentity ? 0 : 2)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

/// How a row joins or leaves a list: from half size, blurred and faded, never from nothing.
struct RowChange: Transition {
    static let animation = Animation.spring(duration: 0.17, bounce: 0.08)
    /// Leaving is slower than arriving: the row melts in place first, then the rows below close the gap.
    static let removal = Animation.spring(duration: 0.34, bounce: 0)

    static func animation(removing: Bool) -> Animation { removing ? removal : animation }

    /// A row arrives with the list's spring. It leaves by fading where it stands, barely shrinking, and is gone
    /// by the time the rows below have closed half the gap, so nothing slides through anything.
    static var change: AnyTransition {
        .asymmetric(insertion: AnyTransition(RowChange()),
                    removal: AnyTransition(RowChange(small: 0.96, blur: 6)).animation(.easeOut(duration: 0.16)))
    }

    var small: CGFloat = 0.5
    var blur: CGFloat = 4

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(phase.isIdentity ? 1 : small)
            .blur(radius: phase.isIdentity ? 0 : blur)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

/// A band of light that crosses a label again and again while Koe listens for it.
private struct Shimmer: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay {
            TimelineView(.animation) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                LinearGradient(colors: [.clear, Palette.fg4, .clear],
                               startPoint: UnitPoint(x: phase * 2 - 1, y: 0.5), endPoint: UnitPoint(x: phase * 2, y: 0.5))
            }
            .mask(content)
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}
