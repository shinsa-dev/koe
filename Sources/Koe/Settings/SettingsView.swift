import KoeCore
import SwiftUI

/// Koe's settings, laid out as the web's settings page: groups of rows on cards.
struct SettingsView: View {
    let library: SessionLibrary
    let permissions: PermissionCenter
    let openSessions: () -> Void

    var body: some View {
        let canPaste = permissions.checklist.status(of: .accessibility) == .granted
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(Typography.pageTitle)
                .foregroundStyle(Palette.fg4)
                .padding(.horizontal, 4)

            SettingsGroup(
                title: "When you stop",
                description: "Koe always copies the transcript. Its markers and the paths under it stay in the text."
            ) {
                SettingRow(title: "Copy files with the text",
                           detail: "Screenshots, clips and files paste in as attachments.") {
                    Toggle("Copy files with the text", isOn: binding(\.copyFiles)).toggleStyle(.koe)
                }
                SettingRow(title: "Paste for you", detail: canPaste
                    ? "Presses ⌘V in the app you're in once the bundle is copied."
                    : "Needs Accessibility, so Koe can press ⌘V in the app you're in.") {
                    if !canPaste {
                        Button("Allow", action: allowAccessibility).buttonStyle(.koe(.outline, size: .small))
                    }
                    Toggle("Paste for you", isOn: binding(\.autoPaste)).toggleStyle(.koe).disabled(!canPaste)
                }
            }

            SettingsGroup(title: "Appearance") {
                SettingRow(title: "Theme") {
                    SegmentedTabs(items: ThemeChoice.allCases.map { ($0, $0.label) }, selection: binding(\.theme))
                }
            }

            SettingsGroup(title: "Shortcuts", description: "They work in every app. You can't change them yet.") {
                ForEach(Self.shortcuts, id: \.title) { shortcut in
                    SettingRow(title: shortcut.title) { Kbd(shortcut.combo.displayName) }
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
        .padding(.horizontal, 24)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: 480)
        .background(Palette.canvas)
    }

    private static let shortcuts: [(title: String, combo: KeyCombo)] = [
        ("Start or stop dictation", .toggleSession),
        ("Take a screenshot", .screenshot),
        ("Add a note", .note),
        ("Record a clip", .clip),
    ]

    private func binding<Value>(_ path: WritableKeyPath<KoeSettings, Value>) -> Binding<Value> {
        Binding(get: { library.settings[keyPath: path] }, set: { value in library.update { $0[keyPath: path] = value } })
    }

    private func allowAccessibility() {
        let status = permissions.checklist.status(of: .accessibility)
        if status == .denied { permissions.openSettings(for: .accessibility) } else { permissions.request(.accessibility) }
    }

    private func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
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
