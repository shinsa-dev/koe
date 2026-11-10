import Foundation

/// What a shortcut does. Starting and finishing dictation works everywhere; the tools' shortcuts are held only
/// while a session runs. Every one carries ⌘, ⌃ or ⌥, so you can type and use your apps while you dictate.
public enum ShortcutAction: String, CaseIterable, Sendable {
    case toggleSession, comment, screenshot, clip

    /// Whether its shortcut is only held while you dictate.
    public var isSessionOnly: Bool { self != .toggleSession }

    public var title: String {
        switch self {
        case .toggleSession: "Start or finish dictation"
        case .comment: "Comment on something"
        case .screenshot: "Take a screenshot"
        case .clip: "Record a clip"
        }
    }

    public var standard: KeyCombo {
        switch self {
        case .toggleSession: .toggleSession
        case .comment: .comment
        case .screenshot: .screenshot
        case .clip: .clip
        }
    }
}

/// The shortcut for each action. One you haven't changed is its standard one; no two actions share a combo.
public struct Shortcuts: Sendable, Equatable {
    public enum Refusal: Error, Equatable {
        /// It has no ⌘, ⌃ or ⌥, so it would take a key away from typing all the time.
        case needsModifier
        case usedBy(ShortcutAction)
    }

    private var changed: [ShortcutAction: KeyCombo] = [:]

    public init() {}

    /// From `values`: each changed action as "keyCode:modifiers" under its key. Anything unreadable, unusable or
    /// clashing is left at its standard.
    public init(values: [String: Any]) {
        for action in ShortcutAction.allCases {
            guard let raw = values[Self.key(action)] as? String else { continue }
            let parts = raw.split(separator: ":").compactMap { UInt32($0) }
            guard parts.count == 2 else { continue }
            try? set(KeyCombo(keyCode: parts[0], modifiers: parts[1]), for: action)
        }
    }

    public static func key(_ action: ShortcutAction) -> String { "shortcut.\(action.rawValue)" }

    /// Only the changed ones; a standard shortcut has no value.
    public var values: [String: Any] {
        Dictionary(uniqueKeysWithValues: changed.map { (Self.key($0.key), "\($0.value.keyCode):\($0.value.modifiers)") })
    }

    public subscript(action: ShortcutAction) -> KeyCombo { changed[action] ?? action.standard }

    public func isStandard(_ action: ShortcutAction) -> Bool { changed[action] == nil }

    public func action(using combo: KeyCombo) -> ShortcutAction? {
        ShortcutAction.allCases.first { self[$0] == combo }
    }

    public mutating func set(_ combo: KeyCombo, for action: ShortcutAction) throws(Refusal) {
        guard combo.isUsable else { throw .needsModifier }
        if let other = self.action(using: combo), other != action { throw .usedBy(other) }
        changed[action] = combo == action.standard ? nil : combo
    }

    /// Back to the standard shortcut, unless another action has taken it meanwhile.
    public mutating func reset(_ action: ShortcutAction) throws(Refusal) {
        try set(action.standard, for: action)
    }
}
