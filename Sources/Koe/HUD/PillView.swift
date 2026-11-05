import KoeCore
import SwiftUI

/// The pill at the bottom of the screen while you talk: a glass capsule with a live waveform of your voice, the
/// session clock, how many attachments it holds, and the button that stops it. Words only show for a notice.
struct PillView: View {
    let sessions: SessionController
    /// Files dropped on the pill; they attach at the moment they land.
    let onDrop: ([URL]) -> Void
    @State private var dropTargeted = false

    var body: some View {
        let phase = sessions.phase
        let text = message(for: phase)
        HStack(spacing: 10) {
            if let text {
                HStack(spacing: 8) {
                    StateDot(tone: tone(for: phase))
                    Text(text)
                        .font(Typography.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 360, alignment: .leading)
                        .fixedSize()
                }
                .id(text)
                .transition(PillSwap())
            } else {
                Waveform(level: { sessions.level }, mode: waveMode(for: phase))
                    .transition(PillSwap())
            }
            if case .recording(let since) = phase, text == nil {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(Elapsed.clock(context.date.timeIntervalSince(since)))
                        .font(Typography.meta.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
                .transition(PillSwap())
            }
            if sessions.annotationCount > 0 {
                AttachmentCount(count: sessions.annotationCount)
                    .transition(PillSwap())
            }
            trailingButton(for: phase)
                .id(ButtonKind(phase))
                .transition(PillSwap())
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 40)
        // While the pill shrinks, what is leaving is cut at its edge instead of spilling past it.
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .floatingSurface(cornerRadius: 20)
        .overlay {
            if dropTargeted {
                Capsule().strokeBorder(Palette.action, lineWidth: 2)
            }
        }
        // A small bounce each time the pill changes what it shows, as a Liquid Glass control does.
        .phaseAnimator([1, 1.04, 1], trigger: text) { pill, scale in
            pill.scaleEffect(scale)
        } animation: { scale in
            scale > 1 ? .spring(duration: 0.18, bounce: 0) : .spring(duration: 0.4, bounce: 0.35)
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: text)
        .animation(.spring(duration: 0.45, bounce: 0.2), value: ButtonKind(phase))
        .animation(.spring(duration: 0.35, bounce: 0.2), value: sessions.annotationCount > 0)
        .dropDestination(for: URL.self) { urls, _ in
            onDrop(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Koe")
    }

    /// Text replaces the waveform only when there is something to read: a notice, a failure, a drop, a change of state.
    private func message(for phase: RecorderPhase) -> String? {
        if dropTargeted { return "Drop to attach at this moment" }
        if let notice = sessions.notice { return notice }
        return switch phase {
        case .idle, .recording, .preparing, .finishing: nil
        case .failed(let reason): reason
        }
    }

    private func tone(for phase: RecorderPhase) -> Tone {
        if dropTargeted { return .neutral }
        switch phase {
        case .recording: return sessions.notice == nil ? .red : .neutral
        case .failed: return .red
        case .preparing, .finishing: return .amber
        case .idle: return sessions.notice == nil ? .neutral : .green
        }
    }

    /// Getting ready and finishing are waiting: the bars run a steady amber wave instead of a text.
    private func waveMode(for phase: RecorderPhase) -> Waveform.Mode {
        switch phase {
        case .recording: .live
        case .preparing, .finishing: .waiting
        case .idle, .failed: .still
        }
    }

    @ViewBuilder private func trailingButton(for phase: RecorderPhase) -> some View {
        switch phase {
        case .preparing, .recording:
            Button(action: sessions.stop) {
                IconView(icon: .close, size: .tiny, color: Palette.actionText, weight: .bold)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Palette.actionTint))
            }
            .buttonStyle(.plain)
            .help("Stop and copy (\(KeyCombo.toggleSession.displayName))")
            .accessibilityLabel("Stop and copy")
        case .failed:
            Button(action: sessions.dismissFailure) {
                IconView(icon: .close, size: .small, color: nil, weight: .semibold).frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        case .idle, .finishing:
            Color.clear.frame(width: 6, height: 24)
        }
    }
}

/// Your voice as a row of rounded bars that scroll from right to left, sampled 30 times a second.
/// While Koe gets ready or finishes, the same bars run a steady amber wave.
private struct Waveform: View {
    enum Mode { case live, waiting, still }

    static let bars = 22
    let level: () -> Float
    let mode: Mode
    @State private var meter = Meter(bars: Self.bars)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: mode == .still)) { context in
            Canvas { canvas, size in
                meter.advance(to: context.date, level: mode == .live ? level() : 0)
                let step = size.width / CGFloat(Self.bars)
                let width = max(2, step - 2)
                let time = context.date.timeIntervalSinceReferenceDate
                let color = mode == .waiting ? Tone.amber.solid : Palette.action
                for index in 0..<Self.bars {
                    let value = mode == .waiting
                        ? WaitingWave.height(bar: index, at: time)
                        : CGFloat(pow(meter.history.bars[index], 1.6))
                    let height = max(3, size.height * value)
                    let rect = CGRect(x: CGFloat(index) * step + (step - width) / 2, y: (size.height - height) / 2,
                                      width: width, height: height)
                    canvas.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(color))
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: mode)
        .frame(width: CGFloat(Self.bars) * 4, height: 22)
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22),
                                   .init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .accessibilityHidden(true)
    }
}

/// A wave that travels right to left at an even pace, between a fifth and three fifths of the bar height.
enum WaitingWave {
    static func height(bar: Int, at time: TimeInterval) -> CGFloat {
        let phase = time * 2 * .pi * 0.9 + Double(bar) * 0.42
        return CGFloat(0.4 + 0.2 * sin(phase))
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

/// An 8 pt dot in a state colour beside a notice.
private struct StateDot: View {
    let tone: Tone

    var body: some View {
        Circle().fill(tone.ink).frame(width: 8, height: 8).accessibilityHidden(true)
    }
}

/// What the trailing button is, so a change of button swaps it with the pill's transition.
private enum ButtonKind: Hashable {
    case stop, dismiss, none

    init(_ phase: RecorderPhase) {
        switch phase {
        case .preparing, .recording: self = .stop
        case .failed: self = .dismiss
        case .idle, .finishing: self = .none
        }
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
