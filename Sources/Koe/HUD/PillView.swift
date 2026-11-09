import KoeCore
import SwiftUI

/// The pill at the bottom of the screen while you talk: a glass capsule with a live waveform of your voice, the
/// session clock, how many attachments it holds, and pause, discard and finish. When a session ends it shows what
/// happened, in the same capsule, until it fades.
struct PillView: View {
    let sessions: SessionController
    let tools: PillTools
    @State private var dropTargeted = false

    var body: some View {
        let content = PillContent(phase: sessions.phase, notice: sessions.notice, dropTargeted: dropTargeted)
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
    let comment: () -> Void
    let screenshot: () -> Void
    let note: () -> Void
    let clip: () -> Void
    let drop: ([URL]) -> Void
}

/// What the pill shows: the session's controls, or a notice in their place.
private enum PillContent: Equatable {
    case session(RecorderPhase)
    case notice(PillNotice)

    init(phase: RecorderPhase, notice: PillNotice?, dropTargeted: Bool) {
        if dropTargeted {
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
                PillButton(icon: .comment, tone: .tool, label: help("Comment on something", .comment),
                           action: tools.comment)
                PillButton(icon: .screenshot, tone: .tool, label: help("Take a screenshot", .screenshot),
                           action: tools.screenshot)
                PillButton(icon: .clip, tone: .tool, label: help("Record a clip", .clip), action: tools.clip)
                PillButton(icon: .note, tone: .tool, label: help("Add a note", .note), action: tools.note)
            }
            .disabled(!phase.isOpen)
            Divider()
                .frame(height: 16)
                .overlay(Palette.ring)
            Waveform(level: { sessions.level }, live: phase == .recording)
                .opacity(paused ? 0.35 : 1)
            SessionClock(sessions: sessions, paused: paused)
            if sessions.annotationCount > 0 {
                AttachmentCount(count: sessions.annotationCount)
                    .transition(PillSwap())
            }
            HStack(spacing: 4) {
                PillButton(icon: .close, tone: .destructive, label: "Discard", action: sessions.cancel)
                PillButton(icon: paused ? .play : .pause, tone: .neutral,
                           label: paused ? "Resume" : "Pause", action: paused ? sessions.resume : sessions.pause)
                    .contentTransition(.symbolEffect(.replace.byLayer, options: .speed(2.5)))
                    // Quick on its own, whatever pace the rest of the pill moves at.
                    .animation(.snappy(duration: 0.14), value: paused)
                PillButton(icon: .checkmark, tone: .action,
                           label: "Finish and copy (\(KeyCombo.toggleSession.displayName))", action: sessions.finish)
            }
            .disabled(!phase.isOpen)
        }
        .animation(.spring(duration: 0.3, bounce: 0.2), value: paused)
    }

    private func help(_ title: String, _ combo: KeyCombo) -> String {
        "\(title) (\(combo.displayName))"
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
private struct PillButton: View {
    enum Tone { case tool, neutral, destructive, action }

    let icon: Icon
    let tone: Tone
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconView(icon: icon, size: .tiny, color: glyph, weight: .bold)
        }
        .buttonStyle(PressDownStyle(fill: fill))
        .help(label)
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

private typealias KoeTone = Tone

private struct PressDownStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        PressDown(configuration: configuration, fill: fill)
    }
}

private struct PressDown: View {
    let configuration: ButtonStyleConfiguration
    let fill: Color
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        configuration.label
            .frame(width: 24, height: 24)
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
            .contentShape(Circle())
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
                IconView(icon: icon, size: .tiny, color: tone.glyph, weight: .bold)
            }
            .frame(width: 24, height: 24)
            // The two lines sit at the font's own line height, no gap between them.
            VStack(alignment: .leading, spacing: -2) {
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

/// Your voice as a row of rounded bars in Shinsa's blue that scroll from right to left, sampled 30 times a second,
/// fading out at both ends. Paused, the bars hold still.
private struct Waveform: View {
    static let bars = 22
    let level: () -> Float
    let live: Bool
    @State private var meter = Meter(bars: Self.bars)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !live)) { context in
            Canvas { canvas, size in
                meter.advance(to: context.date, level: live ? level() : 0)
                let step = size.width / CGFloat(Self.bars)
                let width = max(2, step - 2)
                for (index, value) in meter.history.bars.enumerated() {
                    let height = max(3, size.height * CGFloat(pow(value, 1.6)))
                    let rect = CGRect(x: CGFloat(index) * step + (step - width) / 2, y: (size.height - height) / 2,
                                      width: width, height: height)
                    canvas.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(Palette.action))
                }
            }
        }
        .frame(width: CGFloat(Self.bars) * 4, height: 22)
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22),
                                   .init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .accessibilityHidden(true)
    }
}

/// Smooths the raw level, rising fast and falling slowly as a level meter does, and keeps the bars' history.
/// A reference type so the canvas can advance it on each frame without re-rendering the view.
private final class Meter {
    private(set) var history: LevelHistory
    private var smoothed: Float = 0
    private var last: Date?

    init(bars: Int) {
        history = LevelHistory(count: bars)
    }

    func advance(to date: Date, level: Float) {
        if let last, date.timeIntervalSince(last) < 1.0 / 32 { return }
        last = date
        smoothed = level > smoothed ? level : smoothed * 0.55 + level * 0.45
        history.push(smoothed)
    }
}

/// How many screenshots, notes and files the session holds, so you see each one land.
private struct AttachmentCount: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            IconView(icon: .paperclip, size: .small, color: nil)
            Text("\(count)")
                .font(Typography.label.monospacedDigit())
                .contentTransition(.numericText())
        }
        .foregroundStyle(Palette.fg2)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Palette.press, in: Capsule())
        .animation(.snappy, value: count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count == 1 ? "1 attachment" : "\(count) attachments")
    }
}

/// How the pill's pieces come and go: they shrink, blur and fade out while the new ones grow in, so a change
/// reads as one smooth morph rather than a cut.
private struct PillSwap: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(phase.isIdentity ? 1 : 0.82)
            .blur(radius: phase.isIdentity ? 0 : 5)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}
