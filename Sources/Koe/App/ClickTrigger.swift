import AppKit
import ApplicationServices

/// ⌘⇧-click anywhere, while you dictate: leaves a comment there. With Accessibility allowed the click is kept from
/// the app under it; without, the app gets it too.
@MainActor
final class ClickTrigger {
    var onClick: ((CGPoint) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var monitor: Any?
    private var swallowingRelease = false

    func setActive(_ active: Bool) {
        if active { start() } else { stop() }
    }

    private func start() {
        guard tap == nil else { return }
        if AXIsProcessTrusted(), installTap() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            return
        }
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let flags = event.modifierFlags.intersection([.command, .shift, .control, .option])
            guard flags == [.command, .shift] else { return }
            MainActor.assumeIsolated {
                let spot = NSEvent.mouseLocation
                let mainHeight = NSScreen.screens.first?.frame.height ?? 0
                self?.onClick?(CGPoint(x: spot.x, y: mainHeight - spot.y))
            }
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        swallowingRelease = false
    }

    private func installTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue | 1 << CGEventType.leftMouseUp.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let trigger = Unmanaged<ClickTrigger>.fromOpaque(info).takeUnretainedValue()
                let flags = event.flags
                let location = event.location
                let swallow = MainActor.assumeIsolated { trigger.handle(type, flags: flags, at: location) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    /// Whether the event stops here.
    private func handle(_ type: CGEventType, flags: CGEventFlags, at location: CGPoint) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if type == .leftMouseUp, swallowingRelease {
            swallowingRelease = false
            return true
        }
        let held = flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
        guard type == .leftMouseDown, held == [.maskCommand, .maskShift] else { return false }
        swallowingRelease = true
        onClick?(location)
        return true
    }
}
