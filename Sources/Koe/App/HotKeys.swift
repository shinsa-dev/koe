import AppKit
import ApplicationServices
import Carbon.HIToolbox
import KoeCore
import Observation

/// Global shortcuts through Carbon's RegisterEventHotKey, the one system-wide hotkey API that needs no
/// Accessibility permission.
@MainActor
final class HotKeys {
    static let shared = HotKeys()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = "KOE!".utf8.reduce(0) { $0 << 8 | OSType($1) }

    private init() {}

    /// Returns an id for `unregister`, or nil when another app already holds the combo.
    @discardableResult
    func register(_ combo: KeyCombo, handler: @escaping () -> Void) -> UInt32? {
        installHandler()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, EventHotKeyID(signature: signature, id: id), GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return nil }
        refs[id] = ref
        handlers[id] = handler
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }

    private func fire(_ id: UInt32) { handlers[id]?() }

    private func installHandler() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKey = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey
            )
            guard status == noErr else { return status }
            let id = hotKey.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeys.shared.fire(id) } }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}

/// Fn pressed and let go on its own, which no hotkey API holds. Koe watches the key itself: it fires on the
/// release, and only when no other key went down meanwhile, so Fn with an arrow or an F-key stays the app's. Seeing
/// keys in other apps needs Accessibility.
@MainActor
final class FnKey {
    static let shared = FnKey()

    private var handler: (() -> Void)?
    private var monitors: [Any] = []
    private var down = false
    private var spoilt = false

    private init() {}

    var canWatch: Bool { AXIsProcessTrusted() }

    func watch(_ handler: @escaping () -> Void) {
        self.handler = handler
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.seen(event) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.seen(event) }
            return event
        }) { monitors.append(local) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        handler = nil
        down = false
    }

    private func seen(_ event: NSEvent) {
        if event.type == .keyDown {
            if down { spoilt = true }
            return
        }
        guard event.keyCode == 63 else {
            if down { spoilt = true }
            return
        }
        let others = event.modifierFlags.intersection([.command, .option, .shift, .control])
        if event.modifierFlags.contains(.function) {
            down = true
            spoilt = !others.isEmpty
        } else if down {
            down = false
            if !spoilt, others.isEmpty { handler?() }
        }
    }
}

/// The shortcuts as they are now, registered system-wide. Views read a shortcut's name from here, so a tooltip or
/// menu always shows the one you chose.
@MainActor
@Observable
final class ShortcutCenter {
    static let shared = ShortcutCenter()

    private(set) var shortcuts = Shortcuts()
    /// The actions whose shortcut another app already holds.
    private(set) var taken: Set<ShortcutAction> = []
    /// The actions on Fn while Koe can't see keys in other apps yet.
    private(set) var needsAccessibility: Set<ShortcutAction> = []
    @ObservationIgnored var handlers: [ShortcutAction: () -> Void] = [:]
    @ObservationIgnored private var ids: [ShortcutAction: UInt32] = [:]
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var dictating = false

    private init() {}

    func name(_ action: ShortcutAction) -> String { shortcuts[action].displayName }

    func apply(_ shortcuts: Shortcuts) {
        self.shortcuts = shortcuts
        register()
    }

    /// While a new shortcut is being pressed in settings, the old ones must reach the window, not fire.
    func suspend() {
        suspended = true
        register()
    }

    func resume() {
        suspended = false
        register()
    }

    /// The tools' shortcuts are held only while a session runs.
    func setDictating(_ dictating: Bool) {
        guard dictating != self.dictating else { return }
        self.dictating = dictating
        register()
    }

    private func register() {
        ids.values.forEach(HotKeys.shared.unregister)
        ids = [:]
        FnKey.shared.stop()
        guard !suspended else { return }
        var taken: Set<ShortcutAction> = []
        var needsAccessibility: Set<ShortcutAction> = []
        for action in ShortcutAction.allCases where dictating || !action.isSessionOnly {
            if shortcuts[action].isFn {
                FnKey.shared.watch { [weak self] in self?.handlers[action]?() }
                if !FnKey.shared.canWatch { needsAccessibility.insert(action) }
                continue
            }
            let id = HotKeys.shared.register(shortcuts[action]) { [weak self] in self?.handlers[action]?() }
            if let id { ids[action] = id } else { taken.insert(action) }
        }
        self.taken = taken
        self.needsAccessibility = needsAccessibility
    }
}
