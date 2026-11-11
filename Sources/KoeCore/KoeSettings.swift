import Foundation

public enum ThemeChoice: String, CaseIterable, Sendable {
    case system, light, dark
}

/// What you can change in Koe's settings. Each value is its own defaults key, so `defaults write studio.shinsa.koe`
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
    public var shortcuts = Shortcuts()
    /// The model that transcribes. Until it is downloaded, Apple's on-device model stands in.
    public var transcriptionModel: ModelID = TranscriptionModel.standard.id
    /// Koe downloads the standard model once, on first launch. After that a download is yours to start.
    public var startedFirstDownload = false

    public static let recentChoices = [3, 5, 10]

    public enum Key {
        public static let copyFiles = "copyFiles"
        public static let autoPaste = "autoPaste"
        public static let pasteTogether = "pasteTogether"
        public static let theme = "appearance"
        public static let recentCount = "recentCount"
        public static let freezeScreen = "freezeScreen"
        public static let clickToComment = "clickToComment"
        public static let transcriptionModel = "transcriptionModel"
        public static let startedFirstDownload = "startedFirstDownload"
    }

    public init() {}

    public init(values: [String: Any]) {
        if let copyFiles = values[Key.copyFiles] as? Bool { self.copyFiles = copyFiles }
        if let autoPaste = values[Key.autoPaste] as? Bool { self.autoPaste = autoPaste }
        if let pasteTogether = values[Key.pasteTogether] as? Bool { self.pasteTogether = pasteTogether }
        if let raw = values[Key.theme] as? String, let theme = ThemeChoice(rawValue: raw) { self.theme = theme }
        if let freezeScreen = values[Key.freezeScreen] as? Bool { self.freezeScreen = freezeScreen }
        if let clickToComment = values[Key.clickToComment] as? Bool { self.clickToComment = clickToComment }
        if let count = values[Key.recentCount] as? Int, Self.recentChoices.contains(count) { recentCount = count }
        if let raw = values[Key.transcriptionModel] as? String, let model = ModelID(rawValue: raw) {
            transcriptionModel = model
        }
        if let started = values[Key.startedFirstDownload] as? Bool { startedFirstDownload = started }
        shortcuts = Shortcuts(values: values)
    }

    public var values: [String: Any] {
        [Key.copyFiles: copyFiles, Key.autoPaste: autoPaste, Key.theme: theme.rawValue, Key.recentCount: recentCount,
         Key.freezeScreen: freezeScreen, Key.pasteTogether: pasteTogether, Key.clickToComment: clickToComment,
         Key.transcriptionModel: transcriptionModel.rawValue, Key.startedFirstDownload: startedFirstDownload]
            .merging(shortcuts.values) { current, _ in current }
    }
}
