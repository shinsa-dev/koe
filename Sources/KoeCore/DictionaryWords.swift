import Foundation

/// Which words the dictionary spells, and which of them the models hear as hints before they decode.
public enum DictionaryWords {
    /// The most characters of hints Apple's model gets, so a long list of learned names never crowds out your words.
    public static let hintLimit = 400

    /// Your words first, then the names Koe learned unless you turned them off or removed them. A name is matched to
    /// a removed one by its letters alone, so "buzzkit" keeps "BuzzKit" out.
    public static func list(settings: KoeSettings, learned: [LearnedName]) -> [String] {
        guard settings.learnedNames else { return settings.dictionaryWords }
        let removed = Set(settings.removedNames.map(letters))
        return settings.dictionaryWords + learned.map(\.name).filter { !removed.contains(letters($0)) }
    }

    /// As many words as fit in `limit` characters joined with ", ", in order, so yours come first.
    public static func hints(_ words: [String], limit: Int = hintLimit) -> [String] {
        var used = 0
        var hints: [String] = []
        for word in words {
            let cost = word.count + (hints.isEmpty ? 0 : 2)
            guard used + cost <= limit else { break }
            used += cost
            hints.append(word)
        }
        return hints
    }

    private static func letters(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// The hints the models read when a session or a recording starts. The app sets them whenever the dictionary changes;
/// the transcribers read them from their own threads.
public final class HintWords: @unchecked Sendable {
    private let lock = NSLock()
    private var current: [String] = []

    public init(_ words: [String] = []) {
        current = words
    }

    public var words: [String] {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}
