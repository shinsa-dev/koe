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
    /// ⌥⇧S: freezes the screen to take a screenshot of a region or a window.
    public static let screenshot = KeyCombo(keyCode: 1, modifiers: option | shift)
    /// ⌥⇧A: freezes the screen to pin a comment on anything you click.
    public static let comment = KeyCombo(keyCode: 0, modifiers: option | shift)
    /// ⌥⇧C: picks a region to record a clip of, and stops the recording.
    public static let clip = KeyCombo(keyCode: 8, modifiers: option | shift)

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
        var names: [UInt32: String] = [49: "Space", 36: "↩", 53: "Esc", 48: "⇥"]
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
