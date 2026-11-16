import Foundation

public enum ThemeChoice: String, CaseIterable, Sendable {
    case system, light, dark
}

/// What you can change in Koe's settings. Each value is its own defaults key, so `defaults write studio.overclock.koe`
/// and `-appearance dark` at launch reach it too. A missing or mistyped value falls back to the default.
public struct KoeSettings: Sendable, Equatable {
    /// Put the screenshots, clips and files on the clipboard beside the text, so pasting brings them in.
    public var copyFiles = true
    /// Press ⌘V for you in the app you're in once the bundle is copied. Needs Accessibility.
    public var autoPaste = false
    /// One ⌘V pastes your words and then the attachments, as two pastes Koe makes for you. Needs Accessibility.
    public var pasteTogether = true
    public var theme: ThemeChoice = .system
    /// How many past sessions the menu lists.
    public var recentCount = 5
    /// Hold the screen still while you pick what to screenshot or comment on. Off, the screen keeps moving and the
    /// picture is taken when you attach it.
    public var freezeScreen = true
    /// ⌘⇧-click anywhere to comment there. Off, the click goes to the app under it, as browsers use it for new tabs.
    public var clickToComment = true
    /// Pause music and videos while you dictate, and play them again when you finish. Needs system audio access.
    public var pauseMedia = true
    /// The releases Koe updates to. Unset, it follows the channel of the installed build (`UpdateChannel(version:)`).
    public var updateChannel: UpdateChannel?
    public var shortcuts = Shortcuts()
    /// Models you deleted. Koe picks and downloads models by itself (`ModelPlan`), but never one of these again until
    /// you download it yourself.
    public var deletedModels: Set<ModelID> = []
    /// Words you added to the dictionary, spelled as you want them copied.
    public var dictionaryWords: [String] = []
    /// Add the names Koe learns from this Mac (repositories and apps) to the dictionary.
    public var learnedNames = true
    /// Learned names you removed, kept out even when Koe finds them again.
    public var removedNames: [String] = []

    public static let recentChoices = [3, 5, 10]

    public enum Key {
        public static let copyFiles = "copyFiles"
        public static let autoPaste = "autoPaste"
        public static let pasteTogether = "pasteTogether"
        public static let theme = "appearance"
        public static let recentCount = "recentCount"
        public static let freezeScreen = "freezeScreen"
        public static let clickToComment = "clickToComment"
        public static let pauseMedia = "pauseMedia"
        public static let updateChannel = "updateChannel"
        public static let deletedModels = "deletedModels"
        public static let dictionaryWords = "dictionaryWords"
        public static let learnedNames = "learnedNames"
        public static let removedNames = "removedNames"
    }

    public init() {}

    /// The channel Koe checks: the one you picked, else the one this build came from.
    public func updateChannel(forVersion version: String) -> UpdateChannel {
        updateChannel ?? UpdateChannel(version: version)
    }

    public init(values: [String: Any]) {
        if let copyFiles = values[Key.copyFiles] as? Bool { self.copyFiles = copyFiles }
        if let autoPaste = values[Key.autoPaste] as? Bool { self.autoPaste = autoPaste }
        if let pasteTogether = values[Key.pasteTogether] as? Bool { self.pasteTogether = pasteTogether }
        if let raw = values[Key.theme] as? String, let theme = ThemeChoice(rawValue: raw) { self.theme = theme }
        if let freezeScreen = values[Key.freezeScreen] as? Bool { self.freezeScreen = freezeScreen }
        if let clickToComment = values[Key.clickToComment] as? Bool { self.clickToComment = clickToComment }
        if let pauseMedia = values[Key.pauseMedia] as? Bool { self.pauseMedia = pauseMedia }
        updateChannel = (values[Key.updateChannel] as? String).flatMap(UpdateChannel.init(rawValue:))
        if let count = values[Key.recentCount] as? Int, Self.recentChoices.contains(count) { recentCount = count }
        if let raw = values[Key.deletedModels] as? [String] { deletedModels = Set(raw.compactMap(ModelID.init(rawValue:))) }
        shortcuts = Shortcuts(values: values)
        readDictionary(values)
    }

    private mutating func readDictionary(_ values: [String: Any]) {
        if let words = values[Key.dictionaryWords] as? [String] { dictionaryWords = words }
        if let learned = values[Key.learnedNames] as? Bool { learnedNames = learned }
        if let removed = values[Key.removedNames] as? [String] { removedNames = removed }
    }

    public var values: [String: Any] {
        [Key.copyFiles: copyFiles, Key.autoPaste: autoPaste, Key.theme: theme.rawValue, Key.recentCount: recentCount,
         Key.freezeScreen: freezeScreen, Key.pasteTogether: pasteTogether, Key.clickToComment: clickToComment,
         Key.pauseMedia: pauseMedia, Key.deletedModels: deletedModels.map(\.rawValue).sorted(),
         Key.dictionaryWords: dictionaryWords,
         Key.learnedNames: learnedNames, Key.removedNames: removedNames]
            .merging(updateChannel.map { [Key.updateChannel: $0.rawValue] } ?? [:]) { current, _ in current }
            .merging(shortcuts.values) { current, _ in current }
    }
}
