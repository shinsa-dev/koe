import Foundation

/// A global shortcut, as Carbon's RegisterEventHotKey takes it: a virtual key code and a Carbon modifier mask.
/// The values are Carbon's (HIToolbox `kVK_*`, `cmdKey`…), spelled out so KoeCore needs no system framework.
public struct KeyCombo: Sendable, Equatable, Hashable, Codable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let command: UInt32 = 0x0100
    public static let shift: UInt32 = 0x0200
    public static let option: UInt32 = 0x0800
    public static let control: UInt32 = 0x1000

    /// ⌥Space: starts and stops a session.
    public static let toggleSession = KeyCombo(keyCode: 49, modifiers: option)
    /// ⌃⌥S, while you dictate: freezes the screen to take a screenshot of a region or a window.
    public static let screenshot = KeyCombo(keyCode: 1, modifiers: control | option)
    /// ⌃⌥C, while you dictate: freezes the screen to pin a comment on anything you click.
    public static let comment = KeyCombo(keyCode: 8, modifiers: control | option)
    /// ⌃⌥R, while you dictate: picks a region to record a clip of, and stops the recording.
    public static let clip = KeyCombo(keyCode: 15, modifiers: control | option)

    private static let functionKeys: Set<UInt32> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    /// Whether it can be a global shortcut: it holds ⌘, ⌃ or ⌥ (⇧ alone would take a letter away from typing), or
    /// it is a function key.
    public var isUsable: Bool {
        modifiers & (Self.command | Self.control | Self.option) != 0 || Self.functionKeys.contains(keyCode)
    }

    /// How macOS writes it in menus: modifiers in the order ⌃⌥⇧⌘, then the key.
    public var displayName: String {
        var name = ""
        if modifiers & Self.control != 0 { name += "⌃" }
        if modifiers & Self.option != 0 { name += "⌥" }
        if modifiers & Self.shift != 0 { name += "⇧" }
        if modifiers & Self.command != 0 { name += "⌘" }
        return name + (Self.keyNames[keyCode] ?? "Key \(keyCode)")
    }

    private static let keyNames: [UInt32: String] = {
        var names: [UInt32: String] = [
            49: "Space", 36: "↩", 53: "Esc", 48: "⇥", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
            27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
            109: "F10", 103: "F11", 111: "F12",
        ]
        let letters: [(UInt32, String)] = [
            (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"), (5, "G"), (4, "H"), (34, "I"), (38, "J"),
            (40, "K"), (37, "L"), (46, "M"), (45, "N"), (31, "O"), (35, "P"), (12, "Q"), (15, "R"), (1, "S"),
            (17, "T"), (32, "U"), (9, "V"), (13, "W"), (7, "X"), (16, "Y"), (6, "Z"),
            (29, "0"), (18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"), (22, "6"), (26, "7"), (28, "8"), (25, "9"),
        ]
        for (code, name) in letters { names[code] = name }
        return names
    }()
}
