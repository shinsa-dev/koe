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
    private lazy var tools = ToolCoordinator(
        sessions: sessions, permissions: permissions,
        ensureSession: { [weak self] in self?.ensureSession() ?? false },
        presentSetup: { [weak self] in self?.setup.present() }
    )
    private lazy var pill = PillController(sessions: sessions) { [weak self] urls in self?.tools.drop(urls) }
    /// The shortcuts another app already holds, which the menu points out.
    private var takenHotKeys: Set<KeyCombo> = []

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
        let hotKeys: [(KeyCombo, () -> Void)] = [
            (.toggleSession, { [weak self] in self?.toggleSession() }),
            (.screenshot, { [weak self] in self?.takeScreenshot() }),
            (.note, { [weak self] in self?.addNote() }),
        ]
        for (combo, handler) in hotKeys where HotKeys.shared.register(combo, handler: handler) == nil {
            takenHotKeys.insert(combo)
        }
        if let path = Launch.value(after: "--backdrop"), let image = NSImage(contentsOfFile: path) {
            tools.backdrop = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }

        if audioFile == nil, !permissions.checklist.isReady || Launch.has("--setup") {
            setup.present()
        }
        // For screenshots: opens the menu as if clicked, since the status item can't be clicked by script.
        if Launch.has("--open-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { item.button?.performClick(nil) }
        }
        if Launch.has("--start") { toggleSession() }
        if let script = Launch.value(after: "--script") { play(script) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        permissions.refresh()
        StatusMenu.build(menu, checklist: permissions.checklist, phase: sessions.phase,
                         takenHotKeys: takenHotKeys, target: self)
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

    @objc func takeScreenshot() { tools.screenshot() }

    @objc func addNote() { tools.note() }

    /// Starts a session for a tool used while none runs, and says whether one is running now.
    private func ensureSession() -> Bool {
        if sessions.phase.toggleIntent == .start { toggleSession() }
        return sessions.phase.isActive
    }

    /// `--script`: plays `ScriptedStep`s into the session at their audio times, for trying the tools hands-free.
    private func play(_ script: String) {
        let steps: [ScriptedStep]
        do {
            steps = try ScriptedStep.parse(script)
        } catch {
            FileHandle.standardError.write(Data("Bad --script: \(error)\n".utf8))
            return
        }
        Task { [sessions, tools] in
            for step in steps {
                while sessions.phase.isActive, sessions.currentTime < step.time {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard sessions.phase.isActive else { return }
                switch step.action {
                case .screenshot(let rect, let note): tools.screenshot(preset: rect, note: note, holds: step.holds)
                case .note(let text): tools.note(text: text, holds: step.holds)
                case .drop(let path): tools.drop([URL(fileURLWithPath: path)])
                }
            }
        }
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
