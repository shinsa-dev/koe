import Foundation

/// Which models read a finished recording again, and in what order the recordings wait for them.
public enum RefinePlan {
    /// The models that read a recording again, from the ones installed. Whisper and the first of the Parakeet family each read it;
    /// Apple's model joins only beside both, as a third reading breaks their ties and a second could not outvote the
    /// first. With nothing installed there is nothing better than what streamed.
    public static func readers(installed: Set<ModelID>) -> [ModelID] {
        let whisper = installed.contains(.whisperTurbo) ? [ModelID.whisperTurbo] : []
        let parakeet = ModelID.parakeetFamily.first { installed.contains($0) }.map { [$0] } ?? []
        let apple = whisper.isEmpty || parakeet.isEmpty ? [] : [ModelID.apple]
        return whisper + parakeet + apple
    }

    /// The session with the refined words, or nil when they say the same as what it has.
    public static func refined(_ session: Session, words: [TimedWord]) -> Session? {
        guard !words.isEmpty, words.map(\.text) != session.words.map(\.text) else { return nil }
        var session = session
        session.words = words
        return session
    }
}

/// Recordings waiting to be read again, one at a time. A session that starts pauses the queue, as its live passes
/// need the Neural Engine to themselves; the recording being read goes back to the front and is read again once the
/// queue resumes.
public struct RefineQueue<Job: Identifiable & Sendable>: Sendable {
    public private(set) var waiting: [Job] = []
    public private(set) var running: Job?
    public private(set) var isPaused = false

    public init() {}

    /// Adds a recording and returns it when it should start now. A recording already waiting takes its new place.
    public mutating func add(_ job: Job) -> Job? {
        waiting.removeAll { $0.id == job.id }
        if running?.id == job.id { running = nil }
        waiting.append(job)
        return next()
    }

    /// Stops the queue and returns the recording that was being read, which the caller cancels.
    public mutating func pause() -> Job? {
        isPaused = true
        guard let job = running else { return nil }
        running = nil
        waiting.insert(job, at: 0)
        return job
    }

    /// Starts the queue again and returns the recording to read now.
    public mutating func resume() -> Job? {
        isPaused = false
        return next()
    }

    /// The recording `id` was read, and the next one to read now.
    public mutating func done(_ id: Job.ID) -> Job? {
        if running?.id == id { running = nil }
        return next()
    }

    private mutating func next() -> Job? {
        guard !isPaused, running == nil, !waiting.isEmpty else { return nil }
        running = waiting.removeFirst()
        return running
    }
}
