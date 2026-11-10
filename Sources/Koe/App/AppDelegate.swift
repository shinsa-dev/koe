import AVFoundation
import AppKit
import KoeCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let permissions = PermissionCenter()
    private let transcriber = AppleSpeechTranscriber()
    private lazy var sessions = SessionController(transcriber: transcriber) { [audioFile] in
        if let audioFile { FileSource(url: audioFile) } else { MicrophoneSource() }
    }
    private lazy var tools = ToolCoordinator(
        sessions: sessions, permissions: permissions,
        ensureSession: { [weak self] in self?.ensureSession() ?? false },
        presentSetup: { [weak self] in self?.openSetup() }
    )
    private lazy var library = SessionLibrary(root: SessionController.defaultRoot)
    private lazy var settingsWindow: SettingsWindowController = {
        let controller = SettingsWindowController(
            library: library, permissions: permissions, openSessions: { [weak self] in self?.showSessions() }
        )
        // Back to a menu bar app once the window is gone.
        controller.onClose = { NSApp.setActivationPolicy(.accessory) }
        return controller
    }()
    /// Sessions that ended but are still being saved and copied; the pill stays up for their confirmation.
    private var copiesInFlight = 0
    /// The sessions the menu listed when it last opened, so a click copies the one you saw.
    private var listed: [HistoryEntry] = []
    private lazy var pill: PillController = PillController(sessions: sessions, tools: PillTools(
        status: tools.status,
        comment: { [weak self] in self?.addComment() },
        screenshot: { [weak self] in self?.takeScreenshot() },
        clip: { [weak self] in self?.recordClip() },
        drop: { [weak self] urls in self?.tools.drop(urls) },
        attachments: { [weak self] in self?.pill.toggleAttachments() }
    ))
    /// The shortcuts another app already holds, which the menu points out.
    private var takenHotKeys: Set<KeyCombo> = []

    /// `--audio-file <path>` plays a recording into each session instead of the microphone.
    private let audioFile: URL? = Launch.value(after: "--audio-file").map { URL(fileURLWithPath: $0) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Typography.registerFonts()
        applyAppearance()
        NSApp.mainMenu = MainMenu.build(target: self)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Icon.microphone.image(side: 16)
        item.button?.setAccessibilityLabel("Koe")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        wireSessions()
        if audioFile == nil, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            MicrophoneSource.prewarm()
        }
        recoverUnfinished()
        library.onSettingsChange = { [weak self] _ in self?.applyAppearance() }
        let hotKeys: [(KeyCombo, () -> Void)] = [
            (.toggleSession, { [weak self] in self?.toggleSession() }),
            (.comment, { [weak self] in self?.addComment() }),
            (.screenshot, { [weak self] in self?.takeScreenshot() }),
            (.clip, { [weak self] in self?.recordClip() }),
        ]
        for (combo, handler) in hotKeys where HotKeys.shared.register(combo, handler: handler) == nil {
            takenHotKeys.insert(combo)
        }
        if let path = Launch.value(after: "--backdrop"), let image = NSImage(contentsOfFile: path) {
            tools.backdrop = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        tools.freezesScreen = { [weak self] in self?.library.settings.freezeScreen ?? true }
        tools.clipFile = Launch.value(after: "--clip-file").map { URL(fileURLWithPath: $0) }

        if audioFile == nil, !permissions.checklist.isReady || Launch.has("--setup") {
            openSetup()
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
                openSetup()
                return
            }
        }
        sessions.toggle()
    }

    @objc func addComment() { tools.comment() }

    @objc func takeScreenshot() { tools.screenshot() }

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
        Task { [sessions] in
            for step in steps {
                while sessions.phase.isActive, sessions.currentTime < step.time {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard sessions.phase.isActive else { return }
                await run(step)
            }
        }
    }

    private func run(_ step: ScriptedStep) async {
        switch step.action {
        case .screenshot(let rect, let note, let talk): tools.screenshot(preset: rect, note: note, talk: talk, holds: step.holds)
        case .comment(let spot, let note, let talk): tools.comment(at: spot, note: note, talk: talk, holds: step.holds)
        case .drop(let path): tools.drop([URL(fileURLWithPath: path)])
        case .clip(let rect, let seconds, let picks):
            tools.clip(preset: ClipScript(region: rect, seconds: seconds, picks: picks, holds: step.holds))
        case .pause(let seconds):
            sessions.pause()
            try? await Task.sleep(for: .seconds(seconds))
            sessions.resume()
        case .attachments: pill.toggleAttachments()
        case .finish: sessions.finish()
        case .cancel: sessions.cancel()
        }
    }

    /// Readies the speech model so the first session's audio reaches it at once, then finishes any recording a crash
    /// or quit left behind.
    private func recoverUnfinished() {
        let unfinished = library.unfinished()
        Task { [transcriber, library, sessions, pill] in
            await transcriber.prewarm()
            let recovered = await library.recover(unfinished, using: transcriber)
            guard recovered > 0, !sessions.phase.isActive else { return }
            sessions.post(PillNotice(
                kind: .success, title: "Recording saved",
                detail: recovered == 1 ? "A recording is in Recent sessions" : "\(recovered) recordings are in Recent sessions"
            ))
            pill.show()
            pill.hide(after: .seconds(4)) { sessions.phase != .idle }
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
            // A session started meanwhile owns the pill: its waveform stays up and the copy says nothing.
            guard !sessions.phase.isActive else { return }
            sessions.post(message)
            pill.show()
            lingerThenHide()
        }
    }

    private func wireSessions() {
        sessions.onPhaseChange = { [weak self] phase in self?.phaseChanged(phase) }
        sessions.onFinish = { [weak self] session, folder in self?.sessionEnded(session, folder: folder) }
        sessions.onRefine = { [weak self] session, folder in self?.library.refined(session, folder: folder) }
        sessions.onCancel = { [weak self] in
            self?.tools.sessionCancelled()
            self?.lingerThenHide()
        }
        sessions.onCopyPending = { [weak self] in self?.copyPending() }
        sessions.onLateNotice = { [weak self] in
            guard let self, !sessions.phase.isActive else { return }
            pill.show()
            lingerThenHide()
        }
    }

    /// You finished before the model had its first words: the pill says it's copied at once, and the copy lands as soon
    /// as the words do, well before you can press ⌘V.
    private func copyPending() {
        let summary = ClipboardPlan.summary(for: [], pasted: false)
        sessions.post(PillNotice(kind: .success, title: summary.title, detail: summary.detail))
    }

    @objc func copyRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let entry = listed.first(where: { $0.id == id }) else { return }
        let items = library.copy(entry.session)
        guard !sessions.phase.isActive else { return }
        if items.isEmpty {
            sessions.post(PillNotice(kind: .neutral, title: "Nothing to copy"))
        } else {
            let summary = ClipboardPlan.summary(for: items, pasted: false)
            sessions.post(PillNotice(kind: .success, title: summary.title, detail: summary.detail))
        }
        pill.show()
        lingerThenHide()
    }

    private func lingerThenHide() {
        pill.hide(after: .seconds(2.5)) { [weak self] in
            guard let self else { return false }
            return sessions.phase != .idle || copiesInFlight > 0
        }
    }

    @objc func openSettings() { present() }

    @objc func openSetup() { present() }

    /// A window open means Koe is an app you switch to: it joins the Dock and ⌘Tab until the window closes.
    private func present() {
        NSApp.setActivationPolicy(.regular)
        settingsWindow.present()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !settingsWindow.isOpen { openSettings() }
        return true
    }

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
