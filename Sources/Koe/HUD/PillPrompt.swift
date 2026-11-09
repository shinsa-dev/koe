import KoeCore
import SwiftUI

/// What the pill asks while a tool is open: pick something, attach it, or say what it's about. While it listens,
/// your voice shows where the badge was, so you see it's hearing you.
struct PromptView: View {
    let prompt: ToolPrompt
    let paused: Bool
    let sessions: SessionController
    let status: ToolStatus

    var body: some View {
        HStack(spacing: 10) {
            if prompt.stage == .listening {
                Waveform(level: { sessions.level }, live: !paused, bars: 9)
            } else {
                ZStack {
                    Circle().fill(Tone.neutral.tint)
                    IconView(icon: prompt.icon, size: .small, color: Palette.icon2)
                }
                .frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: -2) {
                Text(prompt.title)
                    .font(Typography.label)
                    .foregroundStyle(Palette.fg4)
                Text(prompt.detail ?? fallbackDetail)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.fg2)
                    .contentTransition(.opacity)
                    .animation(.snappy(duration: 0.2), value: prompt.detail)
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(minWidth: 140, maxWidth: 280, alignment: .leading)
            .fixedSize()
            HStack(spacing: 4) {
                if prompt.stage != .picking, prompt.canTalk, let talk = status.onTalk {
                    let listening = prompt.stage == .listening
                    PillButton(icon: listening ? .muted : .microphone, tone: listening ? .neutral : .tool,
                               label: listening ? "Stop listening" : "Say something about it", action: talk)
                }
                PillButton(icon: .close, tone: .destructive, label: "Cancel", shortcut: "Esc") { status.onCancel?() }
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
        }
    }
}
