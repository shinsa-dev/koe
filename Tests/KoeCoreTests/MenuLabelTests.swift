import KoeCore
import Testing

struct MenuLabelTests {
    @Test func commentShowsTheClickWhileItIsOn() {
        let label = Shortcuts().menuLabel(for: .comment, taken: [], clickToComment: true)
        #expect(label == "⇧⌘-click")
    }

    @Test func commentShowsItsShortcutOnceTheClickIsOff() {
        #expect(Shortcuts().menuLabel(for: .comment, taken: [], clickToComment: false) == "⌥⇧C")
        var shortcuts = Shortcuts()
        try? shortcuts.set(KeyCombo(keyCode: 9, modifiers: KeyCombo.option | KeyCombo.command), for: .comment)
        #expect(shortcuts.menuLabel(for: .comment, taken: [], clickToComment: false) == "⌥⌘V")
    }

    @Test func theClickShowsEvenWhenAnotherAppHoldsTheShortcut() {
        #expect(Shortcuts().menuLabel(for: .comment, taken: [.comment], clickToComment: true) == "⇧⌘-click")
    }

    @Test func otherToolsShowTheirShortcut() {
        let shortcuts = Shortcuts()
        #expect(shortcuts.menuLabel(for: .screenshot, taken: [], clickToComment: true) == "⌥⇧S")
        #expect(shortcuts.menuLabel(for: .clip, taken: [], clickToComment: true) == "⌥⇧R")
    }

    @Test func aTakenShortcutOrFnShowsNothing() {
        let shortcuts = Shortcuts()
        #expect(shortcuts.menuLabel(for: .screenshot, taken: [.screenshot], clickToComment: true) == nil)
        #expect(shortcuts.menuLabel(for: .toggleSession, taken: [], clickToComment: true) == nil)
    }
}
