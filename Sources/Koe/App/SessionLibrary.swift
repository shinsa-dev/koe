import AppKit
import KoeCore
import os

/// What happens to a session once it ends: saved beside its files, copied as one bundle, pasted when you asked
/// for that. Also keeps the settings and the recent sessions the menu lists.
@MainActor
@Observable
final class SessionLibrary {
    private(set) var settings: KoeSettings
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let archive: SessionArchive
    @ObservationIgnored private static let log = Logger(subsystem: "studio.shinsa.koe", category: "library")
    @ObservationIgnored var onSettingsChange: ((KoeSettings) -> Void)?
    /// The session last put on the clipboard and the words it went on with, to tell whether they are still there
    /// when the session's last words settle.
    @ObservationIgnored private var lastCopy: (id: UUID, text: String)?
    @ObservationIgnored private let paster = BundlePaster()
    /// Whether the last copy left only the words on the clipboard, with the attachments following your ⌘V.
    @ObservationIgnored private(set) var pastesTogether = false

    init(root: URL, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        archive = SessionArchive(root: root)
        settings = KoeSettings(values: defaults.dictionaryRepresentation())
        // Oldest first, so the newest win when two sessions read the same.
        for entry in archive.recent(limit: 100).reversed() {
            paster.remember(ClipboardPlan.items(for: BundleComposer().compose(entry.session), copyFiles: true))
        }
        if settings.pasteTogether { paster.watch() }
    }

    var root: URL { archive.root }

    func update(_ change: (inout KoeSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        for (key, value) in next.values { defaults.set(value, forKey: key) }
        if next.pasteTogether { paster.watch() } else { paster.stop() }
        onSettingsChange?(next)
    }

    func recent() -> [HistoryEntry] {
        archive.recent(limit: settings.recentCount)
    }

    /// Saves and copies a session that just ended, and returns what the pill should say.
    func finished(_ session: Session, folder: URL) async -> PillNotice {
        save(session, in: folder)
        let items = copy(session)
        guard !items.isEmpty else { return PillNotice(kind: .neutral, title: "Nothing to copy") }
        lastCopy = (session.id, Self.text(of: items))
        let pasted = settings.autoPaste ? await BundleWriter.paste() : false
        let summary = ClipboardPlan.summary(for: items, pasted: pasted, together: pastesTogether)
        return PillNotice(kind: .success, title: summary.title, detail: summary.detail)
    }

    /// Saves a session again once its last words settled. When the clipboard still holds the copy made when it
    /// ended, the copy is replaced with the settled one; anything you copied since is left alone.
    func refined(_ session: Session, folder: URL) {
        save(session, in: folder)
        guard let lastCopy, lastCopy.id == session.id,
              paster.clipboardReads(lastCopy.text) || paster.delivering else { return }
        self.lastCopy = (session.id, Self.text(of: copy(session)))
    }

    /// Recordings Koe never finished. Read before any session starts, so the one being recorded is never among them.
    func unfinished() -> [(folder: URL, draft: Session?)] {
        archive.unfinished()
    }

    /// Finishes recordings Koe never finished because it quit or crashed while recording: transcribes each one's audio,
    /// keeps the attachments its draft lists, and saves it to the recent sessions. Returns how many it recovered.
    func recover(_ unfinished: [(folder: URL, draft: Session?)], using transcriber: any Transcriber) async -> Int {
        var recovered = 0
        for (folder, draft) in unfinished {
            var session = draft ?? Session(startedAt: Self.created(folder))
            let audio = folder.appending(path: SessionArchive.audioName)
            do {
                session.words = try await transcriber.transcribe(file: audio)
            } catch {
                Self.log.error("Could not transcribe a recovered recording: \(error.localizedDescription, privacy: .public)")
            }
            if session.words.isEmpty {
                session.annotations.append(Annotation(
                    time: 0, kind: .file(Asset(url: audio, kind: .file)),
                    note: "Koe couldn't transcribe this, so the recording is attached."
                ))
            }
            save(session, in: folder)
            recovered += 1
        }
        return recovered
    }

    private static func created(_ folder: URL) -> Date {
        (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
    }

    private func save(_ session: Session, in folder: URL) {
        do {
            try archive.save(session, in: folder)
        } catch {
            Self.log.error("Could not save the session: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Copies a session's bundle again, as it was when it ended.
    @discardableResult
    func copy(_ session: Session) -> [ClipboardItem] {
        let items = ClipboardPlan.items(for: BundleComposer().compose(session), copyFiles: settings.copyFiles)
        pastesTogether = settings.pasteTogether && paster.arm(items)
        if !pastesTogether { BundleWriter.write(items) }
        return items
    }

    private static func text(of items: [ClipboardItem]) -> String {
        for case .text(let plain, _) in items { return plain }
        return ""
    }
}
