import KoeCore
import Testing

struct ClickGestureTests {
    @Test func commentIsShiftCommandClick() {
        #expect(ClickGesture.comment.displayName == "⇧⌘-click")
    }

    @Test func modifiersFollowTheMenuOrder() {
        let all = ClickGesture(modifiers: KeyCombo.command | KeyCombo.shift | KeyCombo.option | KeyCombo.control)
        #expect(all.displayName == "⌃⌥⇧⌘-click")
        #expect(ClickGesture(modifiers: 0).displayName == "-click")
    }
}
