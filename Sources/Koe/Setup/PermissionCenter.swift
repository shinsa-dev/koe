import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import KoeCore

/// Reads and asks for what macOS gates. Screen recording and Accessibility only answer granted or not, so Koe
/// remembers whether it has asked: before it has, a row offers the system prompt; after, System Settings.
@MainActor
@Observable
final class PermissionCenter {
    private(set) var checklist = SetupChecklist(statuses: [:])
    /// System audio recording: only pausing what plays needs it, so it stays out of the checklist.
    private(set) var systemAudio = PermissionStatus.notDetermined
    @ObservationIgnored var onSystemAudioChange: (() -> Void)?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refresh()
    }

    func refresh() {
        apply(Self.read(defaults), audio: SystemAudioAccess.status)
    }

    /// Runs `start` behind the microphone permission, and says whether it ran. A granted answer is trusted and asked
    /// again behind the session, calling `revoked` if access is gone; any other answer is asked now.
    func startWithMicrophone(start: () -> Void, revoked: @escaping @MainActor () -> Void) -> Bool {
        switch MicrophoneGate.onStart(lastKnown: checklist.status(of: .microphone)) {
        case .startThenRecheck:
            start()
            refreshInBackground { if MicrophoneGate.isRevoked(recheck: $0.status(of: .microphone)) { revoked() } }
        case .askFirst:
            refresh()
            guard checklist.status(of: .microphone) == .granted else { return false }
            start()
        }
        return true
    }

    /// Asks macOS on another thread, as each answer takes 10 to 50 ms, and calls `then` on the main actor.
    func refreshInBackground(then: @escaping @MainActor (SetupChecklist) -> Void) {
        let defaults = UncheckedDefaults(defaults)
        DispatchQueue.global(qos: .userInitiated).async {
            let next = Self.read(defaults.value)
            let audio = SystemAudioAccess.status
            Task { @MainActor in
                self.apply(next, audio: audio)
                then(next)
            }
        }
    }

    private func apply(_ next: SetupChecklist, audio: PermissionStatus) {
        if next != checklist { checklist = next }
        if audio != systemAudio {
            systemAudio = audio
            onSystemAudioChange?()
        }
    }

    func requestSystemAudio() {
        SystemAudioAccess.request { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func openSystemAudioSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func request(_ permission: Permission) {
        switch permission {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in self.refresh() }
            }
        case .screenRecording:
            markAsked(permission)
            CGRequestScreenCaptureAccess()
        case .accessibility:
            markAsked(permission)
            let prompt = "AXTrustedCheckOptionPrompt" as CFString
            AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        }
        refresh()
    }

    func openSettings(for permission: Permission) {
        let anchor = switch permission {
        case .microphone: "Privacy_Microphone"
        case .screenRecording: "Privacy_ScreenCapture"
        case .accessibility: "Privacy_Accessibility"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// macOS applies a new screen recording grant only to a fresh process, so Koe opens a new copy of itself and quits.
    func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    nonisolated private static func read(_ defaults: UserDefaults) -> SetupChecklist {
        SetupChecklist(statuses: Dictionary(uniqueKeysWithValues: Permission.allCases.map {
            ($0, status(of: $0, defaults: defaults))
        }))
    }

    nonisolated private static func status(of permission: Permission, defaults: UserDefaults) -> PermissionStatus {
        switch permission {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : asked(permission, defaults: defaults)
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : asked(permission, defaults: defaults)
        }
    }

    nonisolated private static func asked(_ permission: Permission, defaults: UserDefaults) -> PermissionStatus {
        defaults.bool(forKey: askedKey(permission)) ? .denied : .notDetermined
    }

    private func markAsked(_ permission: Permission) {
        defaults.set(true, forKey: askedKey(permission))
    }

    private func askedKey(_ permission: Permission) -> String { Self.askedKey(permission) }
    nonisolated private static func askedKey(_ permission: Permission) -> String { "asked.\(permission.rawValue)" }
}

/// UserDefaults is thread safe, but not marked Sendable.
private struct UncheckedDefaults: @unchecked Sendable {
    let value: UserDefaults
    init(_ value: UserDefaults) { self.value = value }
}
