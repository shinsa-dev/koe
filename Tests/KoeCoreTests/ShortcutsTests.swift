import KoeCore
import Testing

struct ShortcutsTests {
    @Test func everyActionStartsOnItsStandardShortcut() {
        let shortcuts = Shortcuts()
        for action in ShortcutAction.allCases {
            #expect(shortcuts[action] == action.standard)
            #expect(shortcuts.isStandard(action))
        }
        #expect(shortcuts.values.isEmpty)
    }

    @Test func aChangedShortcutRoundTripsThroughItsValues() throws {
        var shortcuts = Shortcuts()
        let combo = KeyCombo(keyCode: 2, modifiers: KeyCombo.control | KeyCombo.option)
        try shortcuts.set(combo, for: .comment)
        #expect(shortcuts[.comment] == combo)
        #expect(!shortcuts.isStandard(.comment))
        #expect(Shortcuts(values: shortcuts.values) == shortcuts)
        #expect(shortcuts.values["shortcut.comment"] as? String == "2:6144")
    }

    @Test func aShortcutAnotherActionHasIsRefused() {
        var shortcuts = Shortcuts()
        #expect(throws: Shortcuts.Refusal.usedBy(.screenshot)) { try shortcuts.set(.screenshot, for: .clip) }
        #expect(shortcuts[.clip] == .clip)
    }

    @Test func aKeyWithoutCommandControlOrOptionIsRefused() {
        var shortcuts = Shortcuts()
        #expect(throws: Shortcuts.Refusal.needsModifier) {
            try shortcuts.set(KeyCombo(keyCode: 1, modifiers: KeyCombo.shift), for: .clip)
        }
        #expect(throws: Shortcuts.Refusal.needsModifier) { try shortcuts.set(KeyCombo(keyCode: 1, modifiers: 0), for: .clip) }
    }

    @Test func aFunctionKeyNeedsNoModifier() throws {
        var shortcuts = Shortcuts()
        try shortcuts.set(KeyCombo(keyCode: 96, modifiers: 0), for: .toggleSession)
        #expect(shortcuts[.toggleSession].displayName == "F5")
    }

    @Test func settingTheStandardShortcutAgainForgetsTheChange() throws {
        var shortcuts = Shortcuts()
        try shortcuts.set(KeyCombo(keyCode: 2, modifiers: KeyCombo.command), for: .clip)
        try shortcuts.reset(.clip)
        #expect(shortcuts == Shortcuts())
    }

    @Test func resetIsRefusedWhileAnotherActionHoldsTheStandardShortcut() throws {
        var shortcuts = Shortcuts()
        try shortcuts.set(KeyCombo(keyCode: 2, modifiers: KeyCombo.command), for: .clip)
        try shortcuts.set(.clip, for: .comment)
        #expect(throws: Shortcuts.Refusal.usedBy(.comment)) { try shortcuts.reset(.clip) }
    }

    @Test func unreadableOrClashingValuesFallBackToTheStandard() {
        let shortcuts = Shortcuts(values: [
            "shortcut.comment": "nonsense", "shortcut.clip": "1:2560", "shortcut.screenshot": "1:512",
        ])
        #expect(shortcuts == Shortcuts())
    }

    @Test func settingsCarryTheirShortcuts() throws {
        var settings = KoeSettings()
        try settings.shortcuts.set(KeyCombo(keyCode: 49, modifiers: KeyCombo.control), for: .toggleSession)
        #expect(KoeSettings(values: settings.values) == settings)
    }

    @Test func namesPunctuationArrowsAndFunctionKeys() {
        #expect(KeyCombo(keyCode: 47, modifiers: KeyCombo.command).displayName == "⌘.")
        #expect(KeyCombo(keyCode: 123, modifiers: KeyCombo.control | KeyCombo.option).displayName == "⌃⌥←")
    }
}
