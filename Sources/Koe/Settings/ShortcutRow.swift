import AppKit
import KoeCore
import SwiftUI

/// One shortcut in settings. Click its keys and press new ones to change it; Esc leaves it as it was. The arrow
/// beside a changed one puts the standard shortcut back.
struct ShortcutRow: View {
    let action: ShortcutAction
    let library: SessionLibrary
    @State private var recording = false
    @State private var refusal: String?
    @State private var monitor: Any?
    @State private var hovering = false

    private var combo: KeyCombo { library.settings.shortcuts[action] }

    var body: some View {
        SettingRow(title: action.title, detail: detail) {
            if !recording, !library.settings.shortcuts.isStandard(action) {
                Button(action: reset) { IconView(icon: .retake, size: .small, color: nil) }
                    .buttonStyle(.koe(.secondary, size: .small, iconOnly: true))
                    .hint("Back to \(action.standard.displayName)")
                    .accessibilityLabel("Reset the shortcut for \(action.title)")
                    .transition(GlyphSwap())
            }
            Button(action: { recording ? stop() : start() }, label: { keys })
                .buttonStyle(.plain)
                .hint(recording ? "Esc keeps \(combo.displayName)" : "Click to change")
                .accessibilityLabel("Shortcut for \(action.title): \(combo.displayName)")
        }
        .animation(GlyphSwap.animation, value: library.settings.shortcuts.isStandard(action))
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stop() }
    }

    private var keys: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return ZStack {
            Text(recording ? "Press the keys" : combo.displayName)
                .id(recording)
                .transition(GlyphSwap())
        }
        // The size of a badge beside it: 12 medium, 20 tall.
        .font(Typography.label)
        .foregroundStyle(recording ? Palette.actionText : Palette.fg3)
        .padding(.horizontal, 6)
        .frame(minWidth: 20, minHeight: 20)
        .background(Palette.surface, in: shape)
        .overlay(shape.strokeBorder(recording ? Palette.action : hovering ? Palette.ringHover : .clear, lineWidth: 1))
        .contentShape(shape)
        .onHover { hovering = $0 }
        .animation(GlyphSwap.animation, value: recording)
    }

    private var detail: String? {
        if let refusal { return refusal }
        if recording { return nil }
        return ShortcutCenter.shared.taken.contains(action) ? "Another app already uses this shortcut." : nil
    }

    private func start() {
        refusal = nil
        recording = true
        ShortcutCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            pressed(event)
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        ShortcutCenter.shared.resume()
    }

    private func pressed(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        if event.keyCode == 53, flags.isEmpty { return stop() }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= KeyCombo.command }
        if flags.contains(.option) { modifiers |= KeyCombo.option }
        if flags.contains(.shift) { modifiers |= KeyCombo.shift }
        if flags.contains(.control) { modifiers |= KeyCombo.control }
        set(KeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers))
    }

    private func reset() {
        refusal = nil
        set(action.standard)
    }

    private func set(_ combo: KeyCombo) {
        var shortcuts = library.settings.shortcuts
        do {
            try shortcuts.set(combo, for: action)
            refusal = nil
            library.update { $0.shortcuts = shortcuts }
            stop()
        } catch Shortcuts.Refusal.usedBy(let other) {
            refusal = "\(combo.displayName) is already the shortcut for \"\(other.title)\"."
        } catch Shortcuts.Refusal.reserved {
            refusal = "\(combo.displayName) already cancels, confirms or plays. Pick another key."
        } catch {
            refusal = "Add ⌘, ⌃ or ⌥ to it."
        }
    }
}
