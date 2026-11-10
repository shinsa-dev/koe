import KoeCore
import SwiftUI

/// What the pill asks while a tool is open: pick something, attach it, or say what it's about. Your voice shows on
/// every page but a clip's recording, so you always see the session is still hearing you.
struct PromptView: View {
    let prompt: ToolPrompt
    let paused: Bool
    let sessions: SessionController
    let status: ToolStatus

    var body: some View {
        HStack(spacing: 10) {
            if prompt.stage == .recording {
                RecordingBadge()
            } else {
                Waveform(level: { sessions.level }, live: !paused, bars: 9)
                    .opacity(paused ? 0.35 : 1)
            }
            VStack(alignment: .leading, spacing: -1) {
                Text(prompt.title)
                    .font(Typography.label)
                    .foregroundStyle(Palette.fg4)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: prompt.title)
                if let clock = prompt.clock {
                    TimelineView(.periodic(from: clock.started, by: 1)) { context in
                        let elapsed = Elapsed.clock(context.date.timeIntervalSince(clock.started))
                        Text(clock.limit.map { "\(elapsed) of \(Elapsed.clock($0))" } ?? elapsed)
                            .font(Typography.meta.monospacedDigit())
                            .foregroundStyle(Palette.fg2)
                            .contentTransition(.numericText())
                    }
                } else {
                    Text(prompt.detail ?? fallbackDetail)
                        .font(Typography.meta)
                        .foregroundStyle(Palette.fg2)
                        .contentTransition(.opacity)
                        .animation(.snappy(duration: 0.2), value: prompt.detail)
                }
            }
            .lineLimit(1)
            .truncationMode(.middle)
            // While you pick, the name under the pointer changes all the time: the pill keeps one width for it.
            .frame(minWidth: prompt.stage == .picking ? 250 : nil, maxWidth: prompt.stage == .picking ? 250 : 280,
                   alignment: .leading)
            .fixedSize()
            // The session's own order: discard on the left, pause in the middle, confirm on the right.
            HStack(spacing: 4) {
                PillButton(icon: .close, tone: .destructive, label: prompt.cancel, shortcut: "Esc") { status.onCancel?() }
                if prompt.canPause, prompt.stage == .listening || prompt.stage == .recording {
                    PillButton(icon: paused ? .playLine : .pauseLine, tone: .neutral, label: paused ? "Resume" : "Pause",
                               action: paused ? sessions.resume : sessions.pause)
                } else if prompt.stage == .confirming, prompt.canTalk, let talk = status.onTalk {
                    PillButton(icon: .microphone, tone: .neutral, label: "Say something about it", action: talk)
                }
                if prompt.stage != .picking, let confirm = status.onConfirm {
                    PillButton(icon: .checkmark, tone: .action, label: prompt.confirm, shortcut: "↩", action: confirm)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var fallbackDetail: String {
        switch prompt.stage {
        case .picking: "Esc cancels"
        case .confirming: "Talk about it first, or just attach it"
        case .listening: "Click the check when you're done"
        case .recording: "Stop when you have it"
        }
    }
}

/// A red dot that breathes while a clip records.
private struct RecordingBadge: View {
    @State private var dim = false

    var body: some View {
        ZStack {
            Circle().fill(Tone.red.tint)
            Circle()
                .fill(Tone.red.ink)
                .frame(width: 8, height: 8)
                .opacity(dim ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dim)
                .onAppear { dim = true }
        }
        .frame(width: 24, height: 24)
    }
}
