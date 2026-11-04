import KoeCore
import SwiftUI

/// The width every pane shares, so switching tabs only changes the height.
private let paneWidth: CGFloat = 500

/// A pane's page: Shinsa's canvas, its type and its blue on the system's own controls.
private struct Pane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) { content }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(width: paneWidth, alignment: .topLeading)
            .font(Typography.body)
            .foregroundStyle(Palette.fg4)
            .tint(Palette.action)
            .background(Palette.canvas)
    }
}

struct GeneralPane: View {
    let library: SessionLibrary
    let permissions: PermissionCenter
    let openSessions: () -> Void

    var body: some View {
        let canPaste = permissions.checklist.status(of: .accessibility) == .granted
        Pane {
            SettingsGroup(
                title: "When you stop",
                description: "Koe always copies the transcript, with a marker where each attachment goes."
            ) {
                SettingRow(title: "Copy files with the text",
                           detail: "Screenshots, clips and files paste in as attachments.") {
                    Toggle("Copy files with the text", isOn: binding(\.copyFiles)).toggleStyle(.koe)
                }
                SettingRow(title: "Paste for you", detail: canPaste
                    ? "Presses ⌘V in the app you're in once the bundle is copied."
                    : "Needs Accessibility, which you can allow in Permissions.") {
                    Toggle("Paste for you", isOn: binding(\.autoPaste)).toggleStyle(.koe).disabled(!canPaste)
                }
            }
            SettingsGroup(title: "Appearance") {
                SettingRow(title: "Theme") {
                    SegmentedTabs(items: ThemeChoice.allCases.map { ($0, $0.label) }, selection: binding(\.theme))
                }
            }
            SettingsGroup(title: "Sessions") {
                SettingRow(title: "Recent sessions in the menu") {
                    SegmentedTabs(items: KoeSettings.recentChoices.map { ($0, "\($0)") }, selection: binding(\.recentCount))
                }
                SettingRow(title: "Saved on this Mac", detail: displayPath(library.root)) {
                    Button("Show in Finder", action: openSessions).buttonStyle(.koe(.outline, size: .small))
                }
            }
        }
    }

    private func binding<Value>(_ path: WritableKeyPath<KoeSettings, Value>) -> Binding<Value> {
        Binding(get: { library.settings[keyPath: path] }, set: { value in library.update { $0[keyPath: path] = value } })
    }

    private func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

struct PermissionsPane: View {
    let center: PermissionCenter

    var body: some View {
        let checklist = center.checklist
        Pane {
            SettingsGroup(
                title: checklist.isReady ? "Koe is ready" : "Allow the microphone and screen recording to start",
                description: "Koe hears you and sees your screen on this Mac only. Nothing you say or capture leaves it."
            ) {
                ForEach(Permission.allCases, id: \.self) { permission in
                    PermissionRow(permission: permission, status: checklist.status(of: permission),
                                  isNext: checklist.nextStep == permission, center: center)
                }
            }
        }
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let status: PermissionStatus
    let isNext: Bool
    let center: PermissionCenter

    var body: some View {
        HStack(spacing: 12) {
            IconView(icon: permission.icon, size: .small, color: status == .granted ? Tone.green.ink : Palette.icon2)
                .frame(width: 28, height: 28)
                .background(status == .granted ? Tone.green.tint : Palette.press,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(permission.title).foregroundStyle(Palette.fg4)
                    if !permission.isRequired { Text("Optional").font(Typography.meta).foregroundStyle(Palette.fg1) }
                }
                Text(detail)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) { trailing }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        guard status == .denied else { return permission.detail }
        return switch permission {
        case .microphone: "\(permission.detail) Turn on Koe under Microphone in System Settings."
        case .screenRecording: "\(permission.detail) After you turn on Koe in System Settings, reopen it."
        case .accessibility: "\(permission.detail) Turn on Koe under Accessibility in System Settings."
        }
    }

    @ViewBuilder private var trailing: some View {
        switch status {
        case .granted:
            HStack(spacing: 4) {
                IconView(icon: .checkmark, size: .small, color: nil, weight: .bold)
                Text("Allowed").font(Typography.label)
            }
            .foregroundStyle(Tone.green.ink)
        case .notDetermined:
            Button("Allow") { center.request(permission) }
                .buttonStyle(.koe(isNext ? .primary : .outline, size: .small))
        case .denied:
            if permission == .screenRecording {
                Button("Reopen Koe") { center.relaunch() }.buttonStyle(.koe(.outline, size: .small))
            }
            Button("Open Settings") { center.openSettings(for: permission) }
                .buttonStyle(.koe(.outline, size: .small))
        }
    }
}

struct ShortcutsPane: View {
    private static let shortcuts: [(title: String, combo: KeyCombo)] = [
        ("Start or stop dictation", .toggleSession),
        ("Take a screenshot", .screenshot),
        ("Add a note", .note),
        ("Record a clip", .clip),
    ]

    var body: some View {
        Pane {
            SettingsGroup(title: "Shortcuts", description: "They work in every app. You can't change them yet.") {
                ForEach(Self.shortcuts, id: \.title) { shortcut in
                    SettingRow(title: shortcut.title) { Kbd(shortcut.combo.displayName) }
                }
            }
        }
    }
}

extension ThemeChoice {
    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

extension Permission {
    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .screenRecording: "Screen recording"
        case .accessibility: "Accessibility"
        }
    }

    var detail: String {
        switch self {
        case .microphone: "To transcribe what you say, on device."
        case .screenRecording: "To take screenshots and record clips while you talk."
        case .accessibility: "To paste the bundle for you when a session ends."
        }
    }

    var icon: Icon {
        switch self {
        case .microphone: .microphone
        case .screenRecording: .screenCapture
        case .accessibility: .accessibility
        }
    }
}
