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
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refresh()
    }

    func refresh() {
        let statuses = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, status(of: $0)) })
        let next = SetupChecklist(statuses: statuses)
        if next != checklist { checklist = next }
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

    private func status(of permission: Permission) -> PermissionStatus {
        switch permission {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : asked(permission)
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : asked(permission)
        }
    }

    private func asked(_ permission: Permission) -> PermissionStatus {
        defaults.bool(forKey: askedKey(permission)) ? .denied : .notDetermined
    }

    private func markAsked(_ permission: Permission) {
        defaults.set(true, forKey: askedKey(permission))
    }

    private func askedKey(_ permission: Permission) -> String { "asked.\(permission.rawValue)" }
}
