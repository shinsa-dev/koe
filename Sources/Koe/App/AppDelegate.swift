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
    private lazy var library = SessionLibrary(root: SessionController.defaultRoot)
    private lazy var settingsWindow = SettingsWindowController(
        library: library, permissions: permissions, openSessions: { [weak self] in self?.showSessions() }
    )
    /// Sessions that ended but are still being saved and copied; the pill stays up for their confirmation.
    private var copiesInFlight = 0
    /// The sessions the menu listed when it last opened, so a click copies the one you saw.
    private var listed: [HistoryEntry] = []
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
        sessions.onFinish = { [weak self] session, folder in self?.sessionEnded(session, folder: folder) }
        library.onSettingsChange = { [weak self] _ in self?.applyAppearance() }
        let hotKeys: [(KeyCombo, () -> Void)] = [
            (.toggleSession, { [weak self] in self?.toggleSession() }),
            (.screenshot, { [weak self] in self?.takeScreenshot() }),
            (.note, { [weak self] in self?.addNote() }),
            (.clip, { [weak self] in self?.recordClip() }),
        ]
        for (combo, handler) in hotKeys where HotKeys.shared.register(combo, handler: handler) == nil {
            takenHotKeys.insert(combo)
        }
        if let path = Launch.value(after: "--backdrop"), let image = NSImage(contentsOfFile: path) {
            tools.backdrop = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        tools.clipFile = Launch.value(after: "--clip-file").map { URL(fileURLWithPath: $0) }

        if audioFile == nil, !permissions.checklist.isReady || Launch.has("--setup") {
            setup.present()
        }
        // For screenshots: opens the menu as if clicked, since the status item can't be clicked by script.
        if Launch.has("--open-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { item.button?.performClick(nil) }
        }
        if Launch.has("--settings") { openSettings() }
        if Launch.has("--start") { toggleSession() }
        if let script = Launch.value(after: "--script") { play(script) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        permissions.refresh()
        listed = library.recent()
        StatusMenu.build(menu, state: StatusMenu.State(
            checklist: permissions.checklist, phase: sessions.phase, recordingClip: tools.isRecordingClip,
            takenHotKeys: takenHotKeys, recent: listed
        ), target: self)
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

    @objc func recordClip() { tools.clip() }

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
                case .clip(let rect, let seconds, let picks):
                    tools.clip(preset: ClipScript(region: rect, seconds: seconds, picks: picks, holds: step.holds))
                }
            }
        }
    }

    /// Saves and copies the session, then shows what was copied in the pill for a moment.
    private func sessionEnded(_ session: Session, folder: URL) {
        copiesInFlight += 1
        Task {
            let message = await library.finished(session, folder: folder)
            copiesInFlight -= 1
            if Launch.has("--print-session") {
                FileHandle.standardOutput.write(Data((BundleComposer().compose(session).text + "\n").utf8))
            }
            sessions.post(notice: message)
            if !sessions.phase.isActive { lingerThenHide() }
        }
    }

    @objc func copyRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let entry = listed.first(where: { $0.id == id }) else { return }
        let items = library.copy(entry.session)
        guard !sessions.phase.isActive else { return }
        sessions.post(notice: items.isEmpty ? "Nothing to copy." : ClipboardPlan.confirmation(for: items, pasted: false))
        pill.show()
        lingerThenHide()
    }

    private func lingerThenHide() {
        pill.hide(after: .seconds(2.5)) { [weak self] in
            guard let self else { return false }
            return sessions.phase != .idle || copiesInFlight > 0
        }
    }

    @objc func openSettings() { settingsWindow.present() }

    private func showSessions() {
        try? FileManager.default.createDirectory(at: library.root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(library.root)
    }

    private func phaseChanged(_ phase: RecorderPhase) {
        if phase == .idle {
            if copiesInFlight > 0 {
                // The copy's confirmation hides the pill once it shows.
            } else if sessions.notice != nil {
                lingerThenHide()
            } else {
                pill.hide()
            }
        } else {
            pill.show()
        }
        if phase == .finishing { tools.sessionStopping() }
        if case .recording = phase {
            statusItem?.button?.contentTintColor = Tokens.redText
        } else {
            statusItem?.button?.contentTintColor = nil
        }
    }

    /// The theme from settings. `-appearance light|dark` at launch pins one too, as it shares the defaults key.
    private func applyAppearance() {
        switch library.settings.theme {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
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
