import AVFoundation
import AppKit
import KoeCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let permissions = PermissionCenter()
    private let transcriber = ActiveTranscriber()
    private let models = ModelStore()
    private lazy var sessions = SessionController(transcriber: transcriber) { [audioFile] in
        if let audioFile { FileSource(url: audioFile) } else { MicrophoneSource() }
    }
    private lazy var tools = ToolCoordinator(
        sessions: sessions, permissions: permissions,
        ensureSession: { [weak self] in self?.ensureSession() ?? false },
        presentSetup: { [weak self] in self?.openSetup() }
    )
    private let clicks = ClickTrigger()
    private let nowPlaying = NowPlaying()
    /// Whether the last phase took audio, so pausing what plays follows the session opening and closing.
    private var sessionWasOpen = false
    private lazy var library = SessionLibrary(root: SessionController.defaultRoot)
    private lazy var settingsWindow: SettingsWindowController = {
        let controller = SettingsWindowController(
            library: library, permissions: permissions, models: models, openSessions: { [weak self] in self?.showSessions() }
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
    /// `--audio-file <path>` plays a recording into each session instead of the microphone.
    private let audioFile: URL? = Launch.value(after: "--audio-file").map { URL(fileURLWithPath: $0) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Typography.registerFonts()
        applyAppearance()
        NSApp.mainMenu = MainMenu.build(target: self)
        statusItem = makeStatusItem()

        wireSessions()
        if audioFile == nil, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            MicrophoneSource.prewarm()
        }
        startTranscription()
        library.onSettingsChange = { [weak self] settings in
            if let self { transcriber.update(chosen: settings.transcriptionModel, store: models) }
            self?.applyAppearance()
            self?.clicks.setActive(settings.clickToComment)
            if settings.shortcuts != ShortcutCenter.shared.shortcuts { ShortcutCenter.shared.apply(settings.shortcuts) }
        }
        ShortcutCenter.shared.handlers = [
            .toggleSession: { [weak self] in self?.toggleSession() },
            .comment: { [weak self] in self?.addComment() },
            .screenshot: { [weak self] in self?.takeScreenshot() },
            .clip: { [weak self] in self?.recordClip() },
        ]
        ShortcutCenter.shared.apply(library.settings.shortcuts)
        ShortcutCenter.shared.onTrustChange = { [weak self] in
            guard let self else { return }
            permissions.refresh()
            clicks.setActive(false)
            clicks.setActive(library.settings.clickToComment)
        }
        clicks.onClick = { [weak self] in self?.commentWhereClicked($0) ?? false }
        clicks.onOtherClick = { [weak self] in self?.tools.clickedElsewhere(at: $0) }
        clicks.setActive(library.settings.clickToComment)
        if let path = Launch.value(after: "--backdrop"), let image = NSImage(contentsOfFile: path) {
            tools.backdrop = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        tools.freezesScreen = { [weak self] in self?.library.settings.freezeScreen ?? true }
        tools.clipFile = Launch.value(after: "--clip-file").map { URL(fileURLWithPath: $0) }

        if audioFile == nil, !permissions.checklist.isReady || Launch.has("--setup") {
            openSetup()
        }
        followLaunchFlags()
    }

    /// The flags that drive Koe for screenshots and tests (README, Notes).
    private func followLaunchFlags() {
        // For screenshots: opens the menu as if clicked, since the status item can't be clicked by script.
        if Launch.has("--open-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.statusItem?.button?.performClick(nil) }
        }
        if Launch.has("--settings") { openSettings() }
        if Launch.has("--start") { toggleSession() }
        if let script = Launch.value(after: "--script") { play(script) }
        // For screenshots: `--download <model>` picks a model as the dropdown does, and `--snapshot <path>` draws the
        // whole settings page into a PNG three seconds in, since the window scrolls and a locked screen captures nothing.
        if let id = Launch.value(after: "--download").flatMap(ModelID.init(rawValue:)) { models.pick(id, in: library) }
        if let path = Launch.value(after: "--snapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.settingsWindow.snapshot(to: URL(fileURLWithPath: path))
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        permissions.refresh()
        listed = library.recent()
        StatusMenu.build(menu, state: StatusMenu.State(
            checklist: permissions.checklist, phase: sessions.phase, recordingClip: tools.isRecordingClip,
            shortcuts: ShortcutCenter.shared.shortcuts, takenHotKeys: ShortcutCenter.shared.taken, recent: listed
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

    /// You finished before the model had its first words: the pill says they are on their way, and says "Copied" only
    /// once they are on the clipboard (`sessionEnded`).
    private func copyPending() {
        sessions.post(PillNotice(kind: .neutral, title: "Copying your words", detail: "Wait a moment before you paste."))
    }

    @objc func copyRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let entry = listed.first(where: { $0.id == id }) else { return }
        let items = library.copy(entry.session)
        guard !sessions.phase.isActive else { return }
        if items.isEmpty {
            sessions.post(PillNotice(kind: .neutral, title: "Nothing to copy"))
        } else {
            let summary = ClipboardPlan.summary(for: items, pasted: false, together: library.pastesTogether)
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
        ShortcutCenter.shared.setDictating(phase.isOpen)
        if phase.isOpen != sessionWasOpen {
            sessionWasOpen = phase.isOpen
            if phase.isOpen {
                nowPlaying.sessionOpened(enabled: library.settings.pauseMedia && audioFile == nil)
            } else {
                nowPlaying.sessionClosed()
            }
        }
        // Asked again on each change, so the click is kept from the app under it once Accessibility is allowed.
        clicks.setActive(library.settings.clickToComment)
        if phase == .finishing { tools.sessionStopping() }
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

extension AppDelegate {
    // A tool takes the screen, so the list of attachments steps out of its way.
    @objc func addComment() {
        pill.closeAttachments()
        tools.comment()
    }

    @objc func takeScreenshot() {
        pill.closeAttachments()
        tools.screenshot()
    }

    @objc func recordClip() {
        pill.closeAttachments()
        tools.clip()
    }

    func commentWhereClicked(_ point: CGPoint) -> Bool {
        guard tools.canQuickComment else { return false }
        pill.closeAttachments()
        tools.quickComment(at: point)
        return true
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

extension AppDelegate {
    /// Koe's mark, the icon's curved cut and dot, as a template the menu bar tints.
    fileprivate static var menuBarMark: NSImage {
        let url = Bundle.main.resourceURL?.appendingPathComponent("KoeMark.svg")
        let image = url.flatMap(NSImage.init(contentsOf:)) ?? Icon.microphone.image(side: 16)
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}

extension AppDelegate {
    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarMark
        item.button?.setAccessibilityLabel("Koe")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        return item
    }

    /// Picks the model sessions use, and on the first launch starts downloading the recommended one; Apple's model
    /// transcribes until it is in, then Koe switches to it.
    private func startTranscription() {
        let standard = TranscriptionModel.standard.id
        models.onChange = { [weak self] id in
            guard let self else { return }
            if id == standard, models.isInstalled(id), !library.settings.startedFirstDownload {
                library.update { $0.startedFirstDownload = true }
            }
            switch ModelPicker.settle(pending: models.pending, changed: id, install: models.install(id)) {
            case .adopt:
                models.pending = nil
                library.update { $0.transcriptionModel = id }
            case .drop: models.pending = nil
            case .keep: break
            }
            transcriber.update(chosen: library.settings.transcriptionModel, store: models)
        }
        transcriber.onRouteChange = { [models] route in models.route = route }
        // Until the first download is in, every launch tries again, so quitting halfway through doesn't leave Koe
        // on Apple's model for good.
        if !library.settings.startedFirstDownload, library.settings.transcriptionModel == standard {
            models.download(standard)
        }
        transcriber.update(chosen: library.settings.transcriptionModel, store: models)
        models.route = transcriber.currentRoute
        recoverUnfinished()
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
}
