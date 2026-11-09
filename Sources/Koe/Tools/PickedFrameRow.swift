import KoeCore
import SwiftUI

struct PickedFrameRow: View {
    let pick: PickedFrame
    let thumbnail: CGImage?
    let talking: Bool
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
                .frame(width: 52, alignment: .leading)
            Button(action: talk) {
                HStack(spacing: 6) {
                    ZStack {
                        IconView(icon: talkIcon, size: .small, color: nil)
                            .id(talkIcon)
                            .transition(GlyphSwap())
                    }
                    Text(talkLabel)
                        .contentTransition(.opacity)
                }
                .padding(.leading, -2)
                .animation(GlyphSwap.animation, value: talkLabel)
            }
            .buttonStyle(.koe(talking ? .primary : .secondary, size: .small))
            .hint(talking ? "Stop and keep what you said" : "What you say next becomes this frame's note")
            Spacer(minLength: 0)
            Button(action: remove) { IconView(icon: .trash, size: .small, color: nil) }
                .buttonStyle(.koe(.bare, size: .small, iconOnly: true))
                .hint("Remove this frame")
                .accessibilityLabel("Remove frame at \(String(format: "%.2f", pick.time)) seconds")
        }
    }
}

extension PickedFrameRow {
    private var talkIcon: Icon { talking ? .stop : (pick.voice == nil ? .microphone : .checkmark) }

    private var talkLabel: String {
        if talking { return "Listening, click when done" }
        return pick.voice == nil ? "Talk about this frame" : "Note spoken, talk again"
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
