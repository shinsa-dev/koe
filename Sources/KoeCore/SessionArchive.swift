import Foundation

/// Keeps each finished session as `session.json` in its own folder, beside its screenshots and files, so the menu
/// can copy it again later, after a relaunch too.
public struct SessionArchive: Sendable {
    public static let fileName = "session.json"
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func save(_ session: Session, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(session).write(to: folder.appending(path: Self.fileName), options: .atomic)
    }

    /// The newest sessions first, at most `limit`. A folder without a readable `session.json` is skipped.
    public func recent(limit: Int) -> [HistoryEntry] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        )) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var entries: [HistoryEntry] = []
        for folder in folders.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            guard entries.count < limit else { break }
            guard let data = try? Data(contentsOf: folder.appending(path: Self.fileName)),
                  let session = try? decoder.decode(Session.self, from: data) else { continue }
            entries.append(HistoryEntry(session: session, folder: folder))
        }
        return entries.sorted { $0.session.startedAt > $1.session.startedAt }
    }
}

/// A past session as the menu lists it.
public struct HistoryEntry: Sendable, Equatable, Identifiable {
    public var session: Session
    public var folder: URL

    public init(session: Session, folder: URL) {
        self.session = session
        self.folder = folder
    }

    public var id: UUID { session.id }

    public var attachmentCount: Int { session.annotations.count }

    /// The start of what you said, cut at a word with "…", or what the session holds when you said nothing.
    public func title(limit: Int = 44) -> String {
        let text = session.words.map(\.text).joined(separator: " ")
        guard !text.isEmpty else {
            return attachmentCount == 1 ? "1 attachment" : "\(attachmentCount) attachments"
        }
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return atWord.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "…"
    }

    /// "Today at 6:15 PM · 3 attachments", "Yesterday at 9:02 AM", "Nov 2 at 6:15 PM".
    public func detail(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let time = session.startedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale,
                                                                calendar: calendar, timeZone: calendar.timeZone))
        let day: String
        if calendar.isDate(session.startedAt, inSameDayAs: now) {
            day = "Today"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(session.startedAt, inSameDayAs: yesterday) {
            day = "Yesterday"
        } else {
            day = session.startedAt.formatted(Date.FormatStyle(locale: locale, calendar: calendar,
                                                               timeZone: calendar.timeZone).month(.abbreviated).day())
        }
        let when = "\(day) at \(time)"
        return switch attachmentCount {
        case 0: when
        case 1: "\(when) · 1 attachment"
        default: "\(when) · \(attachmentCount) attachments"
        }
    }
}
