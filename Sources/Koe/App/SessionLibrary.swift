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

    init(root: URL, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        archive = SessionArchive(root: root)
        settings = KoeSettings(values: defaults.dictionaryRepresentation())
    }

    var root: URL { archive.root }

    func update(_ change: (inout KoeSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        for (key, value) in next.values { defaults.set(value, forKey: key) }
        onSettingsChange?(next)
    }

    func recent() -> [HistoryEntry] {
        archive.recent(limit: settings.recentCount)
    }

    /// Saves and copies a session that just ended, and returns what the pill should say.
    func finished(_ session: Session, folder: URL) async -> String {
        do {
            try archive.save(session, in: folder)
        } catch {
            Self.log.error("Could not save the session: \(error.localizedDescription, privacy: .public)")
        }
        let items = copy(session)
        guard !items.isEmpty else { return "Nothing to copy." }
        let pasted = settings.autoPaste ? await BundleWriter.paste() : false
        return ClipboardPlan.confirmation(for: items, pasted: pasted)
    }

    /// Copies a session's bundle again, as it was when it ended.
    @discardableResult
    func copy(_ session: Session) -> [ClipboardItem] {
        let items = ClipboardPlan.items(for: BundleComposer().compose(session), copyFiles: settings.copyFiles)
        BundleWriter.write(items)
        return items
    }
}
