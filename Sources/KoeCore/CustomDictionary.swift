import Foundation

/// Your own words and the names Koe learned, and the fix that spells them right after a model decoded them. Models
/// hear a name they don't know as the words it sounds like ("Shinza", "shin za"), so each heard word, or run of up to
/// `maxSpan` words, is compared with every entry by how it sounds (`soundKey`). A run that sounds exactly like an entry
/// becomes it. One that only comes close becomes it only when it is a single word that isn't ordinary English, so
/// "shine" never turns into "Shinsa". A learned name is a guess at what you might say, so it never replaces a run made
/// only of ordinary words ("can" stays, not Kanna); one you added yourself does ("shins" becomes Shinsa). Each replaced
/// word keeps its times, so attachments still land between words.
public struct CustomDictionary: Sendable {
    /// The longest run of heard words one entry can replace: "pay wall next" for `paywall-next`.
    public static let maxSpan = 4
    /// The shortest sound key matched by sound at all. Shorter keys ("Koe" is "k") match too many words; they only
    /// fix the casing of the word itself.
    public static let minKey = 3
    /// The shortest sound key a near match may reach: below it, one letter off is another word.
    public static let minNearKey = 5

    /// The words to spell, in the order given: the first of two entries that sound alike wins.
    public let entries: [String]
    /// How many of `entries`, from the first, are your own words; the rest were learned.
    private let yours: Int
    private let exact: [String: Int]
    private let neighbours: [Key: [Int]]
    private let entryKeys: [Key]
    /// Every start of an entry's sound key, so a run of heard words stops growing once no entry could still match it.
    private let prefixes: Set<String>
    /// The lengths of heard sound keys a near match could reach, so most words skip the search.
    private let nearLengths: Set<Int>
    private let isOrdinary: @Sendable (String) -> Bool

    private typealias Key = [UInt8]

    /// `isOrdinary` says whether a lowercased word is ordinary English. The app asks the system's spell checker.
    /// `learned` follow `words` and only replace runs that hold a word that isn't ordinary.
    public init(words: [String], learned: [String] = [],
                isOrdinary: @escaping @Sendable (String) -> Bool = { _ in false }) {
        var seen = Set<String>()
        let clean = { (list: [String]) in
            list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        }
        let own = clean(words)
        yours = own.count
        entries = own + clean(learned)
        var exact: [String: Int] = [:]
        var neighbours: [Key: [Int]] = [:]
        var prefixes = Set<String>()
        var entryKeys: [Key] = []
        var nearLengths = Set<Int>()
        for (index, entry) in entries.enumerated() {
            let letters = Self.letters(of: entry)
            let key = Self.fold(letters)
            entryKeys.append(key)
            for end in key.indices { prefixes.insert(Self.string(key[...end])) }
            guard !key.isEmpty else { continue }
            let name = Self.string(key)
            if exact[name] == nil { exact[name] = index }
            guard key.count >= Self.minNearKey else { continue }
            nearLengths.formUnion((key.count - 2)...(key.count + 2))
            for variant in Self.deletions(of: key) + [key] { neighbours[variant, default: []].append(index) }
        }
        self.exact = exact
        self.neighbours = neighbours
        self.prefixes = prefixes
        self.entryKeys = entryKeys
        self.nearLengths = nearLengths
        self.isOrdinary = isOrdinary
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// The session with its words spelled by the dictionary, its attachments as they were.
    public func apply(to session: Session) -> Session {
        var session = session
        session.words = apply(session.words)
        return session
    }

    /// The transcript with every run of words that sounds like an entry spelled as the entry.
    public func apply(_ words: [TimedWord]) -> [TimedWord] {
        guard !entries.isEmpty else { return words }
        let letters = words.map { Self.heardLetters($0.text) }
        let sounds = letters.map { Self.string(Self.fold($0)) }
        let pauses = words.map { $0.text.last.map { ",.;:?!".contains($0) } ?? false }
        var result: [TimedWord] = []
        result.reserveCapacity(words.count)
        var index = 0
        while index < words.count {
            if let (entry, span) = match(at: index, letters: letters, sounds: sounds, pauses: pauses) {
                result.append(Self.replace(words[index..<index + span], with: entry))
                index += span
            } else {
                result.append(words[index])
                index += 1
            }
        }
        return result
    }

    /// The entry the words from `index` sound like, and how many words it takes: the longest run first. `sounds`
    /// holds each word's own sound key, so a word that can't start an entry costs one lookup. A run stops at a word
    /// that ends in punctuation, and at one that adds nothing to its sound ("Shinza you" sounds like "Shinza").
    private func match(at index: Int, letters: [Key], sounds: [String], pauses: [Bool]) -> (String, Int)? {
        let first = sounds[index]
        guard !first.isEmpty else { return nil }
        var keys = [first]
        if prefixes.contains(first) {
            var run = letters[index]
            for offset in 1..<min(Self.maxSpan, letters.count - index) {
                let word = letters[index + offset]
                guard !word.isEmpty, !pauses[index + offset - 1] else { break }
                run += word
                let key = Self.string(Self.fold(run))
                guard key != keys.last else { break }
                guard prefixes.contains(key) else { break }
                keys.append(key)
            }
        }
        if let found = exactMatch(keys, at: index, letters: letters) { return found }
        guard first.utf8.count >= Self.minNearKey, nearLengths.contains(first.utf8.count) else { return nil }
        // The spell checker is the slow part, so it is only asked about a word that comes close to an entry.
        guard let entry = near(Array(first.utf8)), !isOrdinary(Self.string(letters[index])) else { return nil }
        return (entry, 1)
    }

    /// The entry a run from `index` sounds exactly like, the longest run first; `keys` holds each run's sound key.
    private func exactMatch(_ keys: [String], at index: Int, letters: [Key]) -> (String, Int)? {
        for span in stride(from: keys.count, through: 1, by: -1) {
            let key = keys[span - 1]
            guard let found = exact[key] else { continue }
            let entry = entries[found]
            if span == 1 && letters[index] == Self.letters(of: entry) { return (entry, span) }
            guard key.utf8.count >= Self.minKey else { continue }
            if found >= yours, (index..<index + span).allSatisfy({ isOrdinary(Self.string(letters[$0])) }) { continue }
            return (entry, span)
        }
        return nil
    }

    /// The entry whose sound key is one edit from `key` (two for long keys), the closest first.
    private func near(_ key: Key) -> String? {
        let limit = key.count >= 9 ? 2 : 1
        var best: (entry: Int, distance: Int)?
        var tried = Set<Int>()
        for variant in [key] + Self.deletions(of: key) {
            for entry in neighbours[variant] ?? [] where tried.insert(entry).inserted {
                let distance = Self.distance(key, entryKeys[entry])
                if distance <= limit, distance < best?.distance ?? .max { best = (entry, distance) }
            }
        }
        return best.map { entries[$0.entry] }
    }

    /// How a word sounds, roughly: lower case letters and digits, with the spellings that sound alike folded
    /// together (z and s, c and k, ph and f), doubled letters and silent final vowels dropped. "Shinsa", "Shinza",
    /// "Shinz" and "shins" all come out as "shins".
    public static func soundKey(_ text: String) -> String {
        string(fold(letters(of: text)))
    }

    /// The word's letters and digits in lower case, as bytes; letters outside ASCII stay as their UTF-8 bytes.
    private static func letters(of text: String) -> Key {
        text.lowercased().utf8.filter { $0 >= 0x80 || (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) }
    }

    /// A heard word's letters, without a possessive 's: what `letters(of: split(text).core)` gives, without the
    /// string work for the plain ASCII words most transcripts are made of.
    private static func heardLetters(_ text: String) -> Key {
        let bytes = Array(text.utf8)
        guard bytes.allSatisfy({ $0 < 0x80 }) else { return letters(of: split(text).core) }
        var end = bytes.count
        while end > 0, !isLetter(bytes[end - 1]) { end -= 1 }
        if end > 3, bytes[end - 1] | 0x20 == UInt8(ascii: "s"), bytes[end - 2] == UInt8(ascii: "'") { end -= 2 }
        var letters: Key = []
        letters.reserveCapacity(end)
        for byte in bytes[..<end] where isLetter(byte) {
            letters.append((0x41...0x5A).contains(byte) ? byte | 0x20 : byte)
        }
        return letters
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (0x61...0x7A).contains(byte | 0x20) || (0x30...0x39).contains(byte)
    }

    private static func fold(_ letters: Key) -> Key {
        var key: Key = []
        key.reserveCapacity(letters.count)
        var index = 0
        while index < letters.count {
            let next = index + 1 < letters.count ? letters[index + 1] : 0
            var folded = letters[index]
            switch (folded, next) {
            case (UInt8(ascii: "p"), UInt8(ascii: "h")): folded = UInt8(ascii: "f"); index += 1
            case (UInt8(ascii: "c"), UInt8(ascii: "k")): folded = UInt8(ascii: "k"); index += 1
            case (UInt8(ascii: "c"), UInt8(ascii: "e")), (UInt8(ascii: "c"), UInt8(ascii: "i")),
                 (UInt8(ascii: "c"), UInt8(ascii: "y")), (UInt8(ascii: "z"), _): folded = UInt8(ascii: "s")
            case (UInt8(ascii: "c"), _), (UInt8(ascii: "q"), _): folded = UInt8(ascii: "k")
            default: break
            }
            if folded != key.last { key.append(folded) }
            index += 1
        }
        while key.count > 1, let last = key.last, isVowel(last) { key.removeLast() }
        return key
    }

    private static func string<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        String(bytes: bytes, encoding: .utf8) ?? ""
    }

    private static func isVowel(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a"), UInt8(ascii: "e"), UInt8(ascii: "i"), UInt8(ascii: "o"), UInt8(ascii: "u"),
             UInt8(ascii: "y"): true
        default: false
        }
    }

    /// The word without the punctuation around it or a possessive 's.
    private struct Parts {
        var lead: String, core: String, trail: String
    }

    private static func split(_ text: String) -> Parts {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { CharacterSet.alphanumerics.contains($0) }),
              let last = scalars.lastIndex(where: { CharacterSet.alphanumerics.contains($0) }) else {
            return Parts(lead: text, core: "", trail: "")
        }
        var core = String(scalars[first...last])
        var trail = String(scalars[scalars.index(after: last)...])
        for possessive in ["'s", "’s"] where core.lowercased().hasSuffix(possessive) && core.count > 2 {
            core.removeLast(2)
            trail = possessive + trail
        }
        return Parts(lead: String(scalars[..<first]), core: core, trail: trail)
    }

    /// The run of words as one word spelled as the entry: the punctuation before the first word and after the last
    /// kept, a capital kept at the start of a sentence, from the first word's start to the last word's end.
    static func replace(_ run: ArraySlice<TimedWord>, with entry: String) -> TimedWord {
        guard let first = run.first, let last = run.last else { return TimedWord(entry, start: 0, end: 0) }
        let opening = split(first.text)
        var spelled = entry
        if opening.core.first?.isUppercase == true, let initial = spelled.first, initial.isLowercase {
            spelled = initial.uppercased() + spelled.dropFirst()
        }
        return TimedWord(opening.lead + spelled + split(last.text).trail, start: first.start, end: last.end)
    }

    private static func deletions(of key: Key) -> [Key] {
        key.indices.map { index in
            var shorter = key
            shorter.remove(at: index)
            return shorter
        }
    }

    /// Levenshtein distance with adjacent swaps counted as one edit.
    public static func distance(_ lhs: String, _ rhs: String) -> Int {
        distance(Array(lhs.utf8), Array(rhs.utf8))
    }

    private static func distance(_ left: Key, _ right: Key) -> Int {
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }
        var rows = [[Int]](repeating: [Int](repeating: 0, count: right.count + 1), count: left.count + 1)
        for row in 0...left.count { rows[row][0] = row }
        for column in 0...right.count { rows[0][column] = column }
        for row in 1...left.count {
            for column in 1...right.count {
                let cost = left[row - 1] == right[column - 1] ? 0 : 1
                var value = min(rows[row - 1][column] + 1, rows[row][column - 1] + 1, rows[row - 1][column - 1] + cost)
                if row > 1, column > 1, left[row - 1] == right[column - 2], left[row - 2] == right[column - 1] {
                    value = min(value, rows[row - 2][column - 2] + 1)
                }
                rows[row][column] = value
            }
        }
        return rows[left.count][right.count]
    }
}
