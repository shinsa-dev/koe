import Foundation

/// The language a session is spoken in, worked out once. Whisper guesses it again on every pass otherwise, which costs
/// a decoder step each time and can flip on a short or quiet window; a guess only counts once enough audio backs it.
public struct LanguageLock: Sendable, Equatable {
    /// The language every later pass decodes in, once one is settled.
    public private(set) var language: String?
    /// How much audio a pass must have read for its guess to settle the language.
    public var minimumAudio: AudioTime

    public init(minimumAudio: AudioTime = 4) {
        self.minimumAudio = minimumAudio
    }

    /// Takes the language a pass over `heard` seconds of audio detected, unless one is already settled.
    public mutating func observe(_ detected: String?, heard: AudioTime) {
        guard language == nil, heard >= minimumAudio, let detected, !detected.isEmpty else { return }
        language = detected
    }
}
