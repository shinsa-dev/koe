import Foundation

/// A click with modifiers held, which Koe watches for itself as no key equivalent can carry a click.
public struct ClickGesture: Sendable, Equatable {
    /// Carbon modifier masks, as `KeyCombo` keeps them.
    public let modifiers: UInt32

    public init(modifiers: UInt32) { self.modifiers = modifiers }

    /// ⇧⌘-click anywhere: leaves a comment on what you clicked (`ClickTrigger`).
    public static let comment = ClickGesture(modifiers: KeyCombo.shift | KeyCombo.command)

    /// How macOS writes it in menus: modifiers in the order ⌃⌥⇧⌘, then "-click".
    public var displayName: String {
        var name = ""
        if modifiers & KeyCombo.control != 0 { name += "⌃" }
        if modifiers & KeyCombo.option != 0 { name += "⌥" }
        if modifiers & KeyCombo.shift != 0 { name += "⇧" }
        if modifiers & KeyCombo.command != 0 { name += "⌘" }
        return name + "-click"
    }
}
