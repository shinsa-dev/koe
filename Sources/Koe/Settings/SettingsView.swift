import KoeCore
import SwiftUI

/// Koe's settings on one page, in the order you meet them: permissions, starting, the speech model, the tools while
/// you dictate, what happens when you finish, and the rest.
struct SettingsPage: View {
    let library: SessionLibrary
    let permissions: PermissionCenter
    let models: ModelStore
    let updater: Updater
    let openSessions: () -> Void

    var body: some View {
        let checklist = permissions.checklist
        let canPaste = checklist.status(of: .accessibility) == .granted
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                // The system's own rendering of the Icon Composer icon, as the Dock draws it.
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: -1) {
                    Text("Koe").font(Typography.pageTitle).foregroundStyle(Palette.fg4)
                    Text("Talk, point and paste. Everything stays on this Mac.")
                        .font(Typography.body)
                        .foregroundStyle(Palette.fg2)
                }
            }
            SettingsGroup(title: checklist.isReady ? "Permissions" : "Allow these three to start") {
                ForEach(Permission.allCases, id: \.self) { permission in
                    PermissionRow(permission: permission, status: checklist.status(of: permission),
                                  isNext: checklist.nextStep == permission, center: permissions)
                }
                PermissionRow(systemAudio: permissions.systemAudio, center: permissions)
            }
            SettingsGroup(title: "Dictation", description: "Click a shortcut, then press the keys you want.") {
                ShortcutRow(action: .toggleSession, library: library)
                SettingRow(title: "Comment with ⇧⌘-click",
                           detail: "Say the comment after the click. Off, the click goes to the app, such as a new tab.") {
                    Toggle("Comment with ⇧⌘-click", isOn: binding(\.clickToComment)).toggleStyle(.koe)
                }
            }
            TranscriptionGroup(library: library, models: models)
            SettingsGroup(title: "While you dictate",
                          description: "These shortcuts only work during a session.") {
                ForEach(ShortcutAction.allCases.filter(\.isSessionOnly), id: \.self) { action in
                    ShortcutRow(action: action, library: library)
                }
                SettingRow(title: "Freeze the screen while you pick",
                           detail: "Off, the screen keeps moving and the picture is taken when you attach it.") {
                    Toggle("Freeze the screen while you pick", isOn: binding(\.freezeScreen)).toggleStyle(.koe)
                }
                PauseAudioRow(isOn: binding(\.pauseMedia), access: permissions.systemAudio, center: permissions)
            }
            SettingsGroup(title: "When you finish") {
                SettingRow(title: "Copy attachments with the text",
                           detail: "Screenshots, clips and files paste in after your words.") {
                    Toggle("Copy attachments with the text", isOn: binding(\.copyFiles)).toggleStyle(.koe)
                }
                SettingRow(title: "Paste everything with one ⌘V", detail: canPaste
                    ? "Your words go in, then Koe pastes the attachments."
                    : "Needs Accessibility, above.") {
                    Toggle("Paste everything with one ⌘V", isOn: binding(\.pasteTogether)).toggleStyle(.koe).disabled(!canPaste)
                }
                SettingRow(title: "Paste for you", detail: canPaste
                    ? "Presses ⌘V in the app you're in."
                    : "Needs Accessibility, above.") {
                    Toggle("Paste for you", isOn: binding(\.autoPaste)).toggleStyle(.koe).disabled(!canPaste)
                }
            }
            SettingsGroup(title: "General") {
                SettingRow(title: "Theme") {
                    SegmentedTabs(items: ThemeChoice.allCases.map { ($0, $0.label) }, selection: binding(\.theme))
                }
                SettingRow(title: "Recent sessions in the menu") {
                    SegmentedTabs(items: KoeSettings.recentChoices.map { ($0, "\($0)") }, selection: binding(\.recentCount))
                }
                SettingRow(title: "Sessions", detail: displayPath(library.root)) {
                    Button("Show in Finder", action: openSessions).buttonStyle(.koe(.outline, size: .small))
                }
            }
            UpdatesGroup(updater: updater)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func binding<Value>(_ path: WritableKeyPath<KoeSettings, Value>) -> Binding<Value> {
        Binding(get: { library.settings[keyPath: path] }, set: { value in library.update { $0[keyPath: path] = value } })
    }

    private func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

/// Pausing what plays needs system audio recording, the optional permission above. Turning the switch on asks for it.
private struct PauseAudioRow: View {
    @Binding var isOn: Bool
    let access: PermissionStatus
    let center: PermissionCenter

    var body: some View {
        SettingRow(title: "Pause audio while you dictate", detail: access == .granted
            ? "Music and videos pause as you start and play again when you finish."
            : "Needs System audio, above.") {
            Toggle("Pause audio while you dictate", isOn: Binding(get: { isOn }, set: { wanted in
                isOn = wanted
                if wanted, access == .notDetermined { center.requestSystemAudio() }
            })).toggleStyle(.koe)
        }
    }
}

private struct PermissionRow: View {
    let icon: Icon
    let title: String
    let detail: String
    var isOptional = false
    let status: PermissionStatus
    let isNext: Bool
    let request: () -> Void
    let openSettings: () -> Void
    var relaunch: (() -> Void)?

    init(permission: Permission, status: PermissionStatus, isNext: Bool, center: PermissionCenter) {
        icon = permission.icon
        title = permission.title
        detail = status == .denied ? permission.deniedDetail : permission.detail
        self.status = status
        self.isNext = isNext
        request = { center.request(permission) }
        openSettings = { center.openSettings(for: permission) }
        if permission == .screenRecording { relaunch = { center.relaunch() } }
    }

    /// System audio recording: only pausing what plays needs it, so it is optional and never the next step.
    init(systemAudio status: PermissionStatus, center: PermissionCenter) {
        icon = .systemAudio
        title = "System audio"
        let purpose = "To pause music and videos while you dictate."
        detail = status == .denied ? "\(purpose) Turn on Koe under System Audio Recording Only in System Settings." : purpose
        isOptional = true
        self.status = status
        isNext = false
        request = { center.requestSystemAudio() }
        openSettings = { center.openSystemAudioSettings() }
    }

    var body: some View {
        HStack(spacing: 12) {
            IconView(icon: icon, size: .small, color: status == .granted ? Tone.green.ink : Palette.icon2)
                .frame(width: 28, height: 28)
                .background(status == .granted ? Tone.green.tint : Palette.press,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title).foregroundStyle(Palette.fg4)
                    if isOptional { Badge(title: "Optional", size: .small) }
                }
                Text(detail)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) { trailing }
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var trailing: some View {
        switch status {
        case .granted:
            Badge(title: "Allowed", tone: .green, icon: .checkmark)
        case .notDetermined:
            Button("Allow", action: request).buttonStyle(.koe(isNext ? .primary : .outline, size: .small))
        case .denied:
            if let relaunch {
                Button("Reopen Koe", action: relaunch).buttonStyle(.koe(.outline, size: .small))
            }
            Button("Open System Settings", action: openSettings).buttonStyle(.koe(.outline, size: .small))
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

    var deniedDetail: String {
        switch self {
        case .microphone: "\(detail) Turn on Koe under Microphone in System Settings."
        case .screenRecording: "\(detail) After you turn on Koe in System Settings, reopen it."
        case .accessibility: "\(detail) Turn on Koe under Accessibility in System Settings."
        }
    }

    var detail: String {
        switch self {
        case .microphone: "To transcribe what you say, on device."
        case .screenRecording: "To take screenshots and record clips while you talk."
        case .accessibility: "To start with Fn, comment with ⇧⌘-click and paste."
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
