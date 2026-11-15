import Foundation

/// What the Dictionary card in Settings shows, and the changes its buttons make to the settings.
public struct DictionaryCard: Equatable, Sendable {
    public struct LearnedRow: Equatable, Sendable, Identifiable {
        public var name: String
        /// Where Koe found it: "Repository in ~/Developer/kodama", or "App".
        public var detail: String
        public var id: String { name }
    }

    /// Your words, newest first.
    public var words: [String]
    /// The learned names still in the dictionary, in alphabetical order. Empty while learning is off.
    public var learned: [LearnedRow]
    public var removedCount: Int
    public var isLearning: Bool
    /// The line under the learning switch.
    public var learningDetail: String

    public init(settings: KoeSettings, learned names: [LearnedName], home: String) {
        words = settings.dictionaryWords.reversed()
        isLearning = settings.learnedNames
        let removed = Set(settings.removedNames.map(Self.letters))
        let kept = names.filter { !removed.contains(Self.letters($0.name)) }
        removedCount = names.count - kept.count
        learned = settings.learnedNames
            ? kept.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { LearnedRow(name: $0.name, detail: Self.detail($0.source, home: home)) }
            : []
        learningDetail = Self.learningDetail(kept, isLearning: settings.learnedNames)
    }

    /// The word as typed, trimmed and with single spaces, or nil when it is empty or already one of your words.
    public static func cleaned(_ text: String, adding settings: KoeSettings) -> String? {
        let word = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !word.isEmpty else { return nil }
        let key = letters(word)
        guard !key.isEmpty, !settings.dictionaryWords.contains(where: { letters($0) == key }) else { return nil }
        return word
    }

    /// Adds a word you typed. Adding a learned name you removed brings it back as yours.
    public static func add(_ text: String, to settings: inout KoeSettings) {
        guard let word = cleaned(text, adding: settings) else { return }
        settings.dictionaryWords.append(word)
        settings.removedNames.removeAll { letters($0) == letters(word) }
    }

    public static func remove(word: String, from settings: inout KoeSettings) {
        settings.dictionaryWords.removeAll { $0 == word }
    }

    /// Keeps a learned name out, even when the next scan finds it again.
    public static func remove(learned name: String, from settings: inout KoeSettings) {
        guard !settings.removedNames.contains(where: { letters($0) == letters(name) }) else { return }
        settings.removedNames.append(name)
    }

    public static func restoreRemoved(in settings: inout KoeSettings) {
        settings.removedNames = []
    }

    static func detail(_ source: LearnedName.Source, home: String) -> String {
        switch source {
        case .repository(let path):
            let home = home.hasSuffix("/") ? String(home.dropLast()) : home
            let shown = path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
            return "Repository in \(shown)"
        case .app: return "App"
        }
    }

    static func learningDetail(_ names: [LearnedName], isLearning: Bool) -> String {
        guard isLearning else { return "Off. Only the words you add are in the dictionary." }
        let repositories = names.filter { if case .repository = $0.source { true } else { false } }.count
        let apps = names.count - repositories
        guard !names.isEmpty else { return "Names of your git repositories and apps. None found yet." }
        return "\(count(repositories, "name")) from your repositories and \(count(apps, "name")) from your apps."
    }

    private static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }

    private static func letters(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
