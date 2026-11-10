import KoeCore
import SwiftUI

/// The pill at the bottom of the screen while you talk: a glass capsule with the tools and what you've attached on
/// the left, a live waveform of your voice and the session clock, then discard, pause and finish. While a tool is
/// open it says what to do instead, and when a session ends it shows what happened, in the same capsule.
struct PillView: View {
    let sessions: SessionController
    let tools: PillTools
    @State private var dropTargeted = false

    var body: some View {
        let content = PillContent(phase: sessions.phase, notice: sessions.notice, prompt: tools.status.prompt,
                                  dropTargeted: dropTargeted)
        PillBody(content: content, sessions: sessions, tools: tools)
            .floatingSurface(cornerRadius: 20)
            .overlay {
                if dropTargeted { Capsule().strokeBorder(Palette.action, lineWidth: 2) }
            }
            // A small bounce each time the pill changes what it shows, as a Liquid Glass control does.
            .phaseAnimator([1, 1.04, 1], trigger: content.kind) { pill, scale in
                pill.scaleEffect(scale)
            } animation: { scale in
                scale > 1 ? .spring(duration: 0.18, bounce: 0) : .spring(duration: 0.4, bounce: 0.35)
            }
            .dropDestination(for: URL.self) { urls, _ in
                tools.drop(urls)
                return true
            } isTargeted: { dropTargeted = $0 }
            // The pill is centred inside the animation's scope, so a change of width moves both edges together
            // instead of the left edge jumping while the right one springs.
            .frame(maxWidth: .infinity)
            .animation(.spring(duration: 0.45, bounce: 0.2), value: content)
            .animation(.spring(duration: 0.35, bounce: 0.2), value: sessions.annotationCount > 0)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Koe")
    }
}

/// What the pill's tools do. Files dropped on the pill attach at the moment they land.
struct PillTools {
    let status: ToolStatus
    let comment: () -> Void
    let screenshot: () -> Void
    let clip: () -> Void
    let drop: ([URL]) -> Void
    /// Opens or closes the list of what the session holds.
    let attachments: () -> Void
}

/// What the pill shows: the session's controls, or a notice in their place.
private enum PillContent: Equatable {
    case session(RecorderPhase)
    case prompt(ToolPrompt, paused: Bool)
    case notice(PillNotice)

    init(phase: RecorderPhase, notice: PillNotice?, prompt: ToolPrompt?, dropTargeted: Bool) {
        if let prompt, phase.isOpen {
            self = .prompt(prompt, paused: phase == .paused)
        } else if dropTargeted {
            self = .notice(PillNotice(kind: .neutral, title: "Drop to attach", detail: "At this moment in what you say",
                                      icon: .paperclip))
        } else if case .failed(let reason) = phase {
            self = .notice(PillNotice(kind: .failure, title: "Koe couldn't start", detail: reason))
        } else if let notice {
            self = .notice(notice)
        } else {
            self = .session(phase)
        }
    }

    var isNotice: Bool {
        if case .notice = self { return true }
        return false
    }

    /// What changes the pill's shape, so the bounce runs once per change and not on every tick.
    var kind: String {
        switch self {
        case .session: "session"
        case .prompt(let prompt, _): "prompt:\(prompt.stage)"
        case .notice(let notice): "notice:\(notice.title)"
        }
    }
}

private struct PillBody: View {
    let content: PillContent
    let sessions: SessionController
    let tools: PillTools

    var body: some View {
        // Stacked, not side by side: what leaves and what arrives share the centre while the pill resizes.
        ZStack {
            switch content {
            case .session(let phase):
                SessionControls(phase: phase, sessions: sessions, tools: tools)
                    .transition(PillSwap())
            case .prompt(let prompt, let paused):
                PromptView(prompt: prompt, paused: paused, sessions: sessions, status: tools.status)
                    .id(prompt.stage)
                    .transition(PillSwap())
            case .notice(let notice):
                NoticeView(notice: notice, sessions: sessions)
                    .id(notice.title)
                    .transition(PillSwap())
            }
        }
        // A round badge or button at either end sits 8 pt from the edge on every side, concentric with the pill.
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .frame(height: 40)
        // While the pill shrinks, what is leaving is cut at its edge instead of spilling past it.
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct SessionControls: View {
    let phase: RecorderPhase
    let sessions: SessionController
    let tools: PillTools

    var body: some View {
        let paused = phase == .paused
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                PillButton(icon: .comment, tone: .tool, label: "Comment on something", shortcut: KeyCombo.comment.displayName,
                           action: tools.comment)
                PillButton(icon: .screenshot, tone: .tool, label: "Take a screenshot", shortcut: KeyCombo.screenshot.displayName,
                           action: tools.screenshot)
                PillButton(icon: .video, tone: .tool, label: "Record a clip", shortcut: KeyCombo.clip.displayName, action: tools.clip)
                if sessions.annotationCount > 0 {
                    AttachmentCount(count: sessions.annotationCount, action: tools.attachments)
                        .transition(PillSwap())
                }
            }
            .disabled(!phase.isOpen)
            Divider()
                .frame(height: 16)
                .overlay(Palette.ring)
            Waveform(level: { sessions.level }, live: phase == .recording)
                .opacity(paused ? 0.35 : 1)
            SessionClock(sessions: sessions, paused: paused)
            HStack(spacing: 4) {
                PillButton(icon: .close, tone: .destructive, label: "Discard", action: sessions.cancel)
                PillButton(icon: paused ? .play : .pause, tone: .neutral,
                           label: paused ? "Resume" : "Pause", action: paused ? sessions.resume : sessions.pause)
                PillButton(icon: .checkmark, tone: .action,
                           label: "Finish and copy", shortcut: KeyCombo.toggleSession.displayName, action: sessions.finish)
            }
            .disabled(!phase.isOpen)
        }
    }

}

/// The session's length, ticking with its audio so it stops while paused. Each digit rolls as it changes.
private struct SessionClock: View {
    let sessions: SessionController
    let paused: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let clock = Elapsed.clock(sessions.currentTime)
            Text(clock)
                .font(Typography.meta.monospacedDigit())
                .foregroundStyle(paused ? Palette.fg2 : Palette.fg4)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.35), value: clock)
                .accessibilityLabel("Recorded \(clock)")
        }
        .fixedSize()
    }
}

/// A round glyph button. Pressing it deflates the circle behind the glyph, as Shinsa's buttons do.
struct PillButton: View {
    enum Tone { case tool, neutral, destructive, action }

    let icon: Icon
    let tone: Tone
    let label: String
    var shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // A new glyph swaps in on its own quick spring, whatever pace the rest of the pill moves at.
            ZStack {
                IconView(icon: icon, size: .small, color: glyph)
                    .id(icon)
                    .transition(GlyphSwap())
            }
            .animation(GlyphSwap.animation, value: icon)
        }
        .buttonStyle(PressDownStyle(fill: fill))
        .hint(label, shortcut: shortcut)
        .accessibilityLabel(label)
    }

    private var glyph: Color {
        switch tone {
        case .tool: Palette.fg3
        case .neutral: Palette.fg4
        case .destructive: KoeTone.red.ink
        case .action: Palette.actionText
        }
    }

    private var fill: Color {
        switch tone {
        case .tool: .clear
        case .neutral: Palette.press
        case .destructive: KoeTone.red.tint
        case .action: Palette.actionTint
        }
    }
}

typealias KoeTone = Tone

struct PressDownStyle: ButtonStyle {
    let fill: Color
    /// nil fits the label, as for the attachment count.
    var width: CGFloat? = 24

    func makeBody(configuration: Configuration) -> some View {
        PressDown(configuration: configuration, fill: fill, width: width)
    }
}

private struct PressDown: View {
    let configuration: ButtonStyleConfiguration
    let fill: Color
    let width: CGFloat?
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        configuration.label
            .frame(width: width, height: 24)
            .background {
                // Shinsa's press: the background pulls in by the same inset at any size (`--press-inset-x` 1 px,
                // `--press-inset-y` 0.5 px), so a small button barely moves and a large one moves just as little.
                Capsule()
                    .fill(hovering && isEnabled && fill == .clear ? Palette.press : fill)
                    .brightness(hovering && isEnabled && fill != .clear ? 0.06 : 0)
                    .padding(.horizontal, pressed ? 1 : 0)
                    .padding(.vertical, pressed ? 0.5 : 0)
                    .animation(.spring(duration: 0.2, bounce: 0.3), value: pressed)
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
    }
}

/// What happened, in the pill's own shape: a tinted badge, a short title and one line of detail.
private struct NoticeView: View {
    let notice: PillNotice
    let sessions: SessionController

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(tone.tint)
                IconView(icon: icon, size: .small, color: tone.glyph)
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: -1) {
                Text(notice.title)
                    .font(Typography.label)
                    .foregroundStyle(Palette.fg4)
                if let detail = notice.detail {
                    Text(detail)
                        .font(Typography.meta)
                        .foregroundStyle(Palette.fg2)
                        .contentTransition(.numericText())
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 320, alignment: .leading)
            .fixedSize()
            if notice.kind == .failure {
                PillButton(icon: .close, tone: .neutral, label: "Dismiss", action: sessions.dismissFailure)
            }
        }
        .padding(.trailing, notice.kind == .failure ? 0 : 6)
        .accessibilityElement(children: .combine)
    }

    private var tone: KoeTone {
        switch notice.kind {
        case .success: .green
        case .neutral: .neutral
        case .failure: .red
        }
    }

    private var icon: Icon {
        if let icon = notice.icon { return icon }
        return switch notice.kind {
        case .success: .checkmark
        case .neutral: .close
        case .failure: .warning
        }
    }
}

/// How many comments, screenshots, clips and files the session holds, so you see each one land. Clicking it lists
/// them, to look at or take one out.
private struct AttachmentCount: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                IconView(icon: .paperclip, size: .small, color: nil)
                Text("\(count)")
                    .font(Typography.label.monospacedDigit())
                    .contentTransition(.numericText())
            }
            .foregroundStyle(Palette.fg3)
            .padding(.horizontal, 6)
        }
        .buttonStyle(PressDownStyle(fill: .clear, width: nil))
        .animation(.snappy, value: count)
        .hint("What you've attached")
        .accessibilityLabel(count == 1 ? "1 attachment" : "\(count) attachments")
    }
}

/// How the pill's pieces come and go: they shrink, blur and fade out while the new ones grow in, so a change
/// reads as one smooth morph rather than a cut.
struct PillSwap: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(phase.isIdentity ? 1 : 0.82)
            .blur(radius: phase.isIdentity ? 0 : 5)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}
