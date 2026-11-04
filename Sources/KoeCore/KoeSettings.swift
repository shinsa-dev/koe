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
    public var theme: ThemeChoice = .system
    /// How many past sessions the menu lists.
    public var recentCount = 5

    public static let recentChoices = [3, 5, 10]

    public enum Key {
        public static let copyFiles = "copyFiles"
        public static let autoPaste = "autoPaste"
        public static let theme = "appearance"
        public static let recentCount = "recentCount"
    }

    public init() {}

    public init(values: [String: Any]) {
        if let copyFiles = values[Key.copyFiles] as? Bool { self.copyFiles = copyFiles }
        if let autoPaste = values[Key.autoPaste] as? Bool { self.autoPaste = autoPaste }
        if let raw = values[Key.theme] as? String, let theme = ThemeChoice(rawValue: raw) { self.theme = theme }
        if let count = values[Key.recentCount] as? Int, Self.recentChoices.contains(count) { recentCount = count }
    }

    public var values: [String: Any] {
        [Key.copyFiles: copyFiles, Key.autoPaste: autoPaste, Key.theme: theme.rawValue, Key.recentCount: recentCount]
    }
}
