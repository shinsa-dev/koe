import Foundation

/// Keeps a session open while a tool is still open. A tool takes a ticket stamped with the moment you started it,
/// and hands back its annotation, or nothing when you cancel. The session is settled once the transcriber is done and
/// every ticket is back, so stopping while a note is half typed still keeps the note.
public struct AnnotationLedger: Sendable, Equatable {
    public struct Ticket: Sendable, Equatable, Hashable {
        public let id: UUID
        public let time: AudioTime
    }

    public private(set) var annotations: [Annotation] = []
    private var open: Set<Ticket> = []
    public private(set) var transcriptDone = false

    public init() {}

    public mutating func open(at time: AudioTime) -> Ticket {
        let ticket = Ticket(id: UUID(), time: max(0, time))
        open.insert(ticket)
        return ticket
    }

    /// Takes the annotation stamped with the ticket's time, whatever time it carries. A ticket closes once.
    @discardableResult
    public mutating func close(_ ticket: Ticket, with annotation: Annotation?) -> Bool {
        guard open.remove(ticket) != nil else { return false }
        if var annotation {
            annotation.time = ticket.time
            annotations.append(annotation)
        }
        return true
    }

    public mutating func endTranscript() {
        transcriptDone = true
    }

    public var openCount: Int { open.count }
    public var isSettled: Bool { transcriptDone && open.isEmpty }
}
