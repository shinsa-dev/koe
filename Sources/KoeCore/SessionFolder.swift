import Foundation

/// The folder a session's files live in, and the names they get. Names never repeat in a folder, and carry no spaces,
/// so a path pasted into a terminal agent stays one word.
public struct SessionFolder: Sendable, Equatable {
    public let url: URL
    private var taken: Set<String> = []
    private var screenshots = 0
    private var clips = 0

    public init(url: URL) {
        self.url = url
    }

    /// `2026-11-04-181500-1A2B`: sorts by time, and the id's start keeps two sessions in one second apart.
    public static func name(startedAt: Date, id: UUID, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: startedAt)
        let stamp = String(format: "%04d-%02d-%02d-%02d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
                           parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        return "\(stamp)-\(id.uuidString.prefix(4))"
    }

    public mutating func nextScreenshot() -> URL {
        screenshots += 1
        return reserve("screenshot-\(screenshots).png")
    }

    public mutating func nextClip() -> URL {
        clips += 1
        return reserve("clip-\(clips).mov")
    }

    /// A frame picked out of a clip: `clip-1-frame-25.png`.
    public mutating func frame(_ index: Int, of clip: URL) -> URL {
        reserve("\(clip.deletingPathExtension().lastPathComponent)-frame-\(index + 1).png")
    }

    /// A file you dropped keeps its name, made safe and unique: `spec sheet.pdf` → `spec-sheet.pdf`, then `spec-sheet-2.pdf`.
    public mutating func reserve(_ preferred: String) -> URL {
        let safe = Self.safeName(preferred)
        let base = (safe as NSString).deletingPathExtension
        let ext = (safe as NSString).pathExtension
        var candidate = safe
        var counter = 2
        while taken.contains(candidate.lowercased()) {
            candidate = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            counter += 1
        }
        taken.insert(candidate.lowercased())
        return url.appendingPathComponent(candidate)
    }

    static func safeName(_ name: String) -> String {
        let cleaned = name
            .split(whereSeparator: { $0.isWhitespace || $0 == "/" || $0 == ":" })
            .joined(separator: "-")
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ".-")).isEmpty ? "file" : cleaned
    }
}
