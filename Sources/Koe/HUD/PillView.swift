import KoeCore
import SwiftUI

/// The pill at the top of the screen while you talk, built as the web's toast: a card with a bg-3 ring, rounded as
/// a popup. A state dot, the session clock, the end of what you've said, and the button that stops it.
struct PillView: View {
    let sessions: SessionController

    var body: some View {
        let phase = sessions.phase
        HStack(spacing: 8) {
            StateDot(tone: tone(for: phase), pulses: isRecording(phase))
                .padding(.leading, 4)
            if case .recording(let since) = phase {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(Elapsed.clock(context.date.timeIntervalSince(since)))
                        .font(Typography.meta.monospacedDigit())
                        .foregroundStyle(Palette.fg2)
                }
                .fixedSize()
            }
            Text(message(for: phase))
                .font(Typography.body)
                .foregroundStyle(sessions.transcript.isEmpty ? Palette.fg2 : Palette.fg4)
                .lineLimit(2)
                .truncationMode(.head)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380, alignment: .leading)
                .animation(nil, value: sessions.transcript)
            trailingButton(for: phase)
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .frame(minHeight: 34)
        .background(Palette.card, in: shape)
        .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Koe")
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    private func message(for phase: RecorderPhase) -> String {
        switch phase {
        case .idle: ""
        case .preparing: "Getting ready…"
        case .failed(let reason): reason
        case .recording, .finishing:
            sessions.transcript.isEmpty
                ? (phase == .finishing ? "Finishing…" : "Listening…")
                : sessions.transcript.tail(limit: 110)
        }
    }

    private func tone(for phase: RecorderPhase) -> Tone {
        switch phase {
        case .recording, .failed: .red
        case .preparing, .finishing: .amber
        case .idle: .neutral
        }
    }

    private func isRecording(_ phase: RecorderPhase) -> Bool {
        if case .recording = phase { return true }
        return false
    }

    @ViewBuilder private func trailingButton(for phase: RecorderPhase) -> some View {
        switch phase {
        case .preparing, .recording:
            Button(action: sessions.stop) { IconView(icon: .stop, size: .small, color: nil) }
                .buttonStyle(.koe(.secondary, size: .small, iconOnly: true))
                .help("Stop (\(KeyCombo.toggleSession.displayName))")
                .accessibilityLabel("Stop")
        case .failed:
            Button(action: sessions.dismissFailure) { IconView(icon: .close, size: .small, color: nil) }
                .buttonStyle(.koe(.secondary, size: .small, iconOnly: true))
                .accessibilityLabel("Dismiss")
        case .idle, .finishing:
            Color.clear.frame(width: 4, height: 24)
        }
    }
}

/// An 8 pt dot in a state colour. While recording it breathes, so a glance tells you Koe is listening.
private struct StateDot: View {
    let tone: Tone
    let pulses: Bool
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(tone.ink)
            .frame(width: 8, height: 8)
            .opacity(pulses && dim ? 0.35 : 1)
            .animation(pulses ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: dim)
            .onAppear { dim = pulses }
            .onChange(of: pulses) { _, now in dim = now }
            .accessibilityHidden(true)
    }
}
