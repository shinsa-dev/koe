import KoeCore
import SwiftUI

/// What the pill asks while a tool is open, in place of its usual controls: pick something on the frozen screen,
/// then attach it, or say what it's about first. There is never a field to type in: a note is what you say.
struct ToolPrompt: Equatable {
    enum Stage: Equatable {
        /// The screen is frozen and waits for a click or a drag.
        case picking
        /// Something is picked and waits for you to attach it, with or without saying something about it.
        case confirming
        /// What you say now is this attachment's note.
        case listening
    }

    var stage: Stage
    var icon: Icon
    var title: String
    /// What the pointer is over, or what was picked: "Dia · Settings".
    var detail: String?
    /// The confirm button's label, such as "Attach" or "Add comment".
    var confirm: String
    /// Whether this tool takes a spoken note at all.
    var canTalk = true
}

/// The open tool's prompt and what its buttons do. The pill reads it; the tool coordinator writes it.
@MainActor
@Observable
final class ToolStatus {
    var prompt: ToolPrompt?
    @ObservationIgnored var onCancel: (() -> Void)?
    @ObservationIgnored var onConfirm: (() -> Void)?
    @ObservationIgnored var onTalk: (() -> Void)?

    func clear() {
        prompt = nil
        onCancel = nil
        onConfirm = nil
        onTalk = nil
    }
}

/// When you spoke about one attachment: starts when you begin talking about it, ends when you attach it.
@MainActor
final class VoiceNote {
    private let now: () -> AudioTime
    private var start: AudioTime?
    private var end: AudioTime?

    init(now: @escaping () -> AudioTime) {
        self.now = now
    }

    var isListening: Bool { start != nil && end == nil }

    /// Starts listening, or carries on where it stopped: what you said before stays in the note.
    func begin() {
        if start == nil { start = now() }
        end = nil
    }

    /// Forgets the note, for the next thing you comment on.
    func reset() {
        start = nil
        end = nil
    }

    func stop() {
        guard isListening else { return }
        end = now()
    }

    /// The span heard, closing it if it is still open; nil when you never spoke about it.
    func span() -> VoiceSpan? {
        stop()
        guard let start, let end else { return nil }
        return VoiceSpan(start: start, end: end)
    }
}
