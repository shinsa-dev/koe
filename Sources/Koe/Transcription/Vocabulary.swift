import AppKit
import KoeCore
import os

/// The names Koe learned from this Mac and the dictionary they make with your own words. It shows the last scan's
/// names at once from `~/Library/Application Support/Koe/LearnedNames.json`, and scans again in the background when
/// that is older than `staleAfter`, so a session never waits on a scan.
@MainActor @Observable
final class Vocabulary {
    @ObservationIgnored private static let log = Logger(subsystem: "studio.overclock.koe", category: "vocabulary")
    static let staleAfter: TimeInterval = 6 * 3600

    private(set) var learned: [LearnedName] = []
    private(set) var scannedAt: Date?
    private(set) var isScanning = false
    /// The fix sessions apply when they are copied, rebuilt whenever the words change.
    private(set) var dictionary = CustomDictionary(words: [])
    /// What Apple's model hears as hints, read when a session or a recording starts.
    @ObservationIgnored let hints = HintWords()
    @ObservationIgnored private var settings = KoeSettings()
    /// The words the dictionary was last built from, before it drops duplicates.
    @ObservationIgnored private var built: [String]?

    @ObservationIgnored private let cache: URL
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let appFolders: [URL]

    init(cache: URL = URL.applicationSupportDirectory.appending(path: "Koe/LearnedNames.json"),
         home: URL = FileManager.default.homeDirectoryForCurrentUser,
         appFolders: [URL]? = nil) {
        self.cache = cache
        self.home = home
        self.appFolders = appFolders ?? [URL(filePath: "/Applications"), home.appending(path: "Applications")]
        if let saved = try? JSONDecoder().decode(Saved.self, from: Data(contentsOf: cache)) {
            learned = saved.names
            scannedAt = saved.scannedAt
        }
    }

    /// Rebuilds the dictionary from your words and the learned names. Call it when the settings change.
    func update(settings: KoeSettings) {
        self.settings = settings
        rebuild()
    }

    private func rebuild() {
        let words = DictionaryWords.list(settings: settings, learned: learned)
        guard words != built else { return }
        built = words
        let yours = settings.dictionaryWords.count
        dictionary = CustomDictionary(words: Array(words.prefix(yours)), learned: Array(words.dropFirst(yours)),
                                      isOrdinary: OrdinaryWords.check)
        hints.words = DictionaryWords.hints(dictionary.entries)
        // The spell checker's first answer takes about 12 ms; pay it now, not in a session's copy.
        _ = OrdinaryWords.contains("koe")
        Self.log.info("Dictionary has \(words.count) words")
    }

    /// Checks every hour, for as long as Koe runs, whether the names are stale, so new repositories show up without a
    /// relaunch.
    func keepFresh() {
        refreshIfStale()
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                self?.refreshIfStale()
            }
        }
    }

    /// Scans again when the last scan is missing or stale.
    func refreshIfStale(now: Date = .now) {
        guard scannedAt.map({ now.timeIntervalSince($0) > Self.staleAfter }) ?? true else { return }
        Task { await rescan() }
    }

    /// Scans the home folder and the app folders off the main thread, then keeps and saves what counts.
    func rescan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let (home, appFolders) = (home, appFolders)
        let start = ContinuousClock.now
        let found = await Task.detached(priority: .utility) {
            NameScan().names(home: home, appFolders: appFolders)
        }.value
        learned = NameSources.learn(found, isOrdinary: OrdinaryWords.contains)
        scannedAt = .now
        rebuild()
        Self.log.info("Learned \(self.learned.count) names in \(ContinuousClock.now - start, privacy: .public)")
        save()
    }

    private func save() {
        guard let scannedAt else { return }
        do {
            try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(Saved(scannedAt: scannedAt, names: learned)).write(to: cache, options: .atomic)
        } catch {
            Self.log.error("Could not save learned names: \(error.localizedDescription, privacy: .public)")
        }
    }

    private struct Saved: Codable {
        var scannedAt: Date
        var names: [LearnedName]
    }
}

/// Whether a lowercased word is ordinary English, as the system's spell checker sees it. Answers are kept, as the
/// same words come up in every session.
@MainActor
enum OrdinaryWords {
    private static var known: [String: Bool] = [:]

    static func contains(_ word: String) -> Bool {
        if let answer = known[word] { return answer }
        let miss = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0, language: "en", wrap: false,
                                                       inSpellDocumentWithTag: 0, wordCount: nil)
        let answer = miss.location == NSNotFound
        known[word] = answer
        return answer
    }

    /// The same from any thread: the spell checker only answers on the main queue. Under `dispatchMain()` (the
    /// command line modes) the main queue runs on other threads, so it is told by a mark on the queue, not the thread.
    nonisolated static func check(_ word: String) -> Bool {
        if DispatchQueue.getSpecific(key: mainMark) != nil { return MainActor.assumeIsolated { contains(word) } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { contains(word) } }
    }

    private nonisolated static let mainMark: DispatchSpecificKey<Bool> = {
        let key = DispatchSpecificKey<Bool>()
        DispatchQueue.main.setSpecific(key: key, value: true)
        return key
    }()
}

/// `Koe --names [--home <folder>]`: scans the home folder, or the one named, and the app folders, and prints every name
/// it learned with where it came from and how long the scan took. It only reads, and saves nothing.
@MainActor
enum NamesCommand {
    static func run(_ arguments: [String]) -> Int32 {
        let home = arguments.firstIndex(of: "--home").flatMap { arguments.indices.contains($0 + 1) ? $0 + 1 : nil }
            .map { URL(filePath: arguments[$0]) } ?? FileManager.default.homeDirectoryForCurrentUser
        let apps = [URL(filePath: "/Applications"), home.appending(path: "Applications")]
        let start = ContinuousClock.now
        let found = NameScan().names(home: home, appFolders: apps)
        let scanned = ContinuousClock.now - start
        let learned = NameSources.learn(found, isOrdinary: OrdinaryWords.contains)
        for name in learned {
            switch name.source {
            case .repository(let path): print("\(name.name)\trepository \(path)")
            case .app(let path): print("\(name.name)\tapp \(path)")
            }
        }
        let repositories = Set(found.compactMap { if case .repository(let path) = $0.source { path } else { nil } })
        print("\(learned.count) names from \(repositories.count) repositories and the apps, scanned in \(scanned), "
            + "picked in \(ContinuousClock.now - start - scanned)")
        return 0
    }
}
