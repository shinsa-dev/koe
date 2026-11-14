import Foundation

/// Whether a transcript kept its last words: the benchmark compares how a session's live transcript ends with how a
/// single decode of the whole recording ends. Case and punctuation don't count, as models write them differently.
public enum TailScore {
    public struct Result: Sendable, Equatable {
        /// The live transcript's last words, normalised.
        public let live: [String]
        /// The reference's last words, normalised.
        public let reference: [String]
        public var isComplete: Bool { live == reference }
    }

    /// The last `count` words of `live` against those of `reference`.
    public static func compare(live: String, reference: String, count: Int = 3) -> Result {
        Result(live: Array(words(live).suffix(count)), reference: Array(words(reference).suffix(count)))
    }

    /// The words of `text` in lower case, without punctuation; a word that is only punctuation goes.
    public static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace)
            .map { String($0.lowercased().filter { $0.isLetter || $0.isNumber }) }
            .filter { !$0.isEmpty }
    }

    /// How many of `results` are complete, as "32/40".
    public static func total(_ results: [Result]) -> String {
        "\(results.filter(\.isComplete).count)/\(results.count)"
    }
}
