import Foundation

/// Seconds into a session's audio: the clock every word and annotation shares.
public typealias AudioTime = TimeInterval

/// One spoken word and when it was said. Punctuation the transcriber puts after a word belongs to it.
public struct TimedWord: Codable, Sendable, Equatable {
    public var text: String
    public var start: AudioTime
    public var end: AudioTime

    public init(_ text: String, start: AudioTime, end: AudioTime) {
        self.text = text
        self.start = start
        self.end = max(start, end)
    }

    /// Whether the word closes a sentence, which makes the gap after it a natural place for an attachment.
    public var endsSentence: Bool {
        guard let last = text.last(where: { !Self.closers.contains($0) }) else { return false }
        return ".?!…".contains(last)
    }

    private static let closers: Set<Character> = ["\"", "'", "”", "’", ")", "]"]
}

/// A file Koe keeps for a session: a screenshot, a recorded clip or a file you dropped.
public struct Asset: Codable, Sendable, Equatable {
    public var url: URL
    public var kind: AssetKind

    public init(url: URL, kind: AssetKind? = nil) {
        self.url = url
        self.kind = kind ?? AssetKind(inferringFrom: url)
    }
}

public enum AssetKind: String, Codable, Sendable {
    case image
    case video
    case file

    public init(inferringFrom url: URL) {
        let ext = url.pathExtension.lowercased()
        if Self.imageExtensions.contains(ext) {
            self = .image
        } else if Self.videoExtensions.contains(ext) {
            self = .video
        } else {
            self = .file
        }
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tif", "tiff", "bmp"]
    private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "webm"]
}

/// Where a capture came from, so the agent knows which app you were looking at.
public struct CaptureSource: Codable, Sendable, Equatable {
    public var app: String
    public var window: String?

    public init(app: String, window: String? = nil) {
        self.app = app
        self.window = window
    }
}

/// Where a frame picked out of a clip comes from.
public struct ClipFrame: Codable, Sendable, Equatable {
    public var clipID: UUID
    /// Seconds into the clip.
    public var time: AudioTime

    public init(clipID: UUID, time: AudioTime) {
        self.clipID = clipID
        self.time = max(0, time)
    }
}

/// A stretch of the session's audio you spoke about one attachment: the words said in it become its note
/// instead of running on in the transcript.
public struct VoiceSpan: Codable, Sendable, Equatable {
    public var start: AudioTime
    public var end: AudioTime

    public init(start: AudioTime, end: AudioTime) {
        self.start = max(0, start)
        self.end = max(self.start, end)
    }

    /// A word belongs to the span when its middle falls inside it.
    public func contains(_ word: TimedWord) -> Bool {
        let middle = (word.start + word.end) / 2
        return middle >= start && middle <= end
    }
}

/// Something you added while talking, stamped with the audio time at the moment you started it.
public struct Annotation: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: Codable, Sendable, Equatable {
        case screenshot(Asset)
        case clip(Asset)
        case file(Asset)
        /// A typed note on its own, with nothing attached.
        case note
    }

    public var id: UUID
    public var time: AudioTime
    public var kind: Kind
    public var note: String?
    public var source: CaptureSource?
    /// For a frame picked out of a clip: which clip, and when in it.
    public var frame: ClipFrame?
    /// When you spoke about this attachment alone; what you said there is its note.
    public var voice: VoiceSpan?

    public init(id: UUID = UUID(), time: AudioTime, kind: Kind, note: String? = nil, source: CaptureSource? = nil,
                frame: ClipFrame? = nil, voice: VoiceSpan? = nil) {
        self.id = id
        self.time = max(0, time)
        self.kind = kind
        self.note = note
        self.source = source
        self.frame = frame
        self.voice = voice
    }

    public var asset: Asset? {
        switch kind {
        case .screenshot(let asset), .clip(let asset), .file(let asset): asset
        case .note: nil
        }
    }

    /// The note without surrounding whitespace, or nil when there is nothing to say.
    public var trimmedNote: String? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// One recording: what you said and everything you added while saying it.
public struct Session: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var words: [TimedWord]
    public var annotations: [Annotation]

    public init(id: UUID = UUID(), startedAt: Date = Date(), words: [TimedWord] = [], annotations: [Annotation] = []) {
        self.id = id
        self.startedAt = startedAt
        self.words = words
        self.annotations = annotations
    }

    public mutating func add(_ annotation: Annotation) {
        annotations.append(annotation)
    }

    /// The transcriber reports words as runs of text with one time range; this splits a run into words.
    public mutating func appendTranscript(_ text: String, start: AudioTime, end: AudioTime) {
        words.appendRun(text, start: start, end: end)
    }

    /// How long the session has run, as far as its words and annotations show.
    public var duration: AudioTime {
        max(words.last?.end ?? 0, annotations.map(\.time).max() ?? 0)
    }
}

extension [TimedWord] {
    /// Splits `text` on whitespace and shares the run's time range between the words by length.
    /// A token of punctuation alone ("," or ".") joins the word before it, even one from an earlier run.
    /// With `joiningPrevious`, a run that starts mid-word ("'t" after "don") continues the last word.
    public mutating func appendRun(_ text: String, start: AudioTime, end: AudioTime, joiningPrevious: Bool = false) {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let totalLength = tokens.reduce(0) { $0 + $1.count }
        guard totalLength > 0 else { return }
        let span = Swift.max(0, end - start)
        let continuesWord = joiningPrevious && !(text.first?.isWhitespace ?? true)
        var cursor = start
        for (index, token) in tokens.enumerated() {
            let tokenEnd = cursor + span * Double(token.count) / Double(totalLength)
            let glues = token.allSatisfy({ $0.isPunctuation }) || (index == 0 && continuesWord)
            if glues, var previous = last {
                previous.text += token
                previous.end = Swift.max(previous.end, tokenEnd)
                self[endIndex - 1] = previous
            } else {
                append(TimedWord(token, start: cursor, end: tokenEnd))
            }
            cursor = tokenEnd
        }
    }
}
