import AppKit
import KoeCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let permissions = PermissionCenter()
    private lazy var setup = SetupWindowController(center: permissions)
    private lazy var sessions = SessionController(transcriber: AppleSpeechTranscriber()) { [audioFile] in
        if let audioFile { FileSource(url: audioFile) } else { MicrophoneSource() }
    }
    private lazy var pill = PillController(sessions: sessions)
    private var toggleHotKeyTaken = false

    /// `--audio-file <path>` plays a recording into each session instead of the microphone.
    private let audioFile: URL? = Launch.value(after: "--audio-file").map { URL(fileURLWithPath: $0) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Typography.registerFonts()
        applyAppearance()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Icon.microphone.image(side: 16)
        item.button?.setAccessibilityLabel("Koe")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        sessions.onPhaseChange = { [weak self] phase in self?.phaseChanged(phase) }
        sessions.onFinish = { session in
            guard Launch.has("--print-session") else { return }
            FileHandle.standardOutput.write(Data((BundleComposer().compose(session).text + "\n").utf8))
        }
        toggleHotKeyTaken = HotKeys.shared.register(.toggleSession) { [weak self] in self?.toggleSession() } == nil

        if audioFile == nil, !permissions.checklist.isReady || Launch.has("--setup") {
            setup.present()
        }
        // For screenshots: opens the menu as if clicked, since the status item can't be clicked by script.
        if Launch.has("--open-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { item.button?.performClick(nil) }
        }
        if Launch.has("--start") { toggleSession() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        permissions.refresh()
        StatusMenu.build(menu, checklist: permissions.checklist, phase: sessions.phase,
                         hotKeyTaken: toggleHotKeyTaken, target: self)
    }

    @objc func toggleSession() {
        if sessions.phase.toggleIntent == .start, audioFile == nil {
            permissions.refresh()
            guard permissions.checklist.status(of: .microphone) == .granted else {
                setup.present()
                return
            }
        }
        sessions.toggle()
    }

    private func phaseChanged(_ phase: RecorderPhase) {
        if phase == .idle { pill.hide() } else { pill.show() }
        if case .recording = phase {
            statusItem?.button?.contentTintColor = Tokens.redText
        } else {
            statusItem?.button?.contentTintColor = nil
        }
    }

    /// `defaults write studio.shinsa.koe appearance light|dark` (or `-appearance dark` at launch) pins a theme;
    /// unset, Koe follows the system.
    private func applyAppearance() {
        switch UserDefaults.standard.string(forKey: "appearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    @objc func openSetup() { setup.present() }

    @objc func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

enum Launch {
    static func has(_ flag: String) -> Bool { CommandLine.arguments.contains(flag) }

    static func value(after flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag), CommandLine.arguments.indices.contains(index + 1)
        else { return nil }
        return CommandLine.arguments[index + 1]
    }
}
