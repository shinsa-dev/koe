import Foundation

/// One item Koe puts on the clipboard. Chat boxes read the text from the first item and take every file they find
/// as an attachment, so the text comes first and each file is an item of its own, in marker order.
public enum ClipboardItem: Sendable, Equatable {
    case text(plain: String, html: String)
    case file(URL)
}

public enum ClipboardPlan {
    /// The items for a bundle. Files that no longer exist are left out, since a paste would fail on them, and a
    /// file named twice goes on once. Without `copyFiles` only the text goes on; its footer still lists the paths.
    public static func items(for bundle: ComposedBundle, copyFiles: Bool,
                             exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> [ClipboardItem] {
        var items: [ClipboardItem] = []
        if !bundle.text.isEmpty { items.append(.text(plain: bundle.text, html: bundle.html)) }
        guard copyFiles else { return items }
        var seen: Set<URL> = []
        for item in bundle.assets {
            let url = item.asset.url.standardizedFileURL
            guard !seen.contains(url), exists(url) else { continue }
            seen.insert(url)
            items.append(.file(url))
        }
        return items
    }

    /// What the pill shows once the bundle is on the clipboard, then what to do with it. `together` is when one ⌘V
    /// brings the attachments in after the words.
    public static func summary(for items: [ClipboardItem], pasted: Bool,
                               together: Bool = false) -> (title: String, detail: String) {
        let files = items.filter { if case .file = $0 { true } else { false } }.count
        let attachments = files == 0 ? "" : files == 1 ? " and 1 attachment" : " and \(files) attachments"
        if pasted { return ("Pasted for you", "Your words\(attachments) went straight in") }
        if together, files > 0 {
            return ("Copied to clipboard", "Press ⌘V once for your words\(attachments)")
        }
        return ("Copied to clipboard", "Press ⌘V to paste your words\(attachments) anywhere")
    }
}

/// How one ⌘V becomes the whole bundle. A chat box given text and files in one paste keeps one and drops the other,
/// so Koe leaves only your words on the clipboard and, when you paste them, follows with the files as a second paste.
public enum PastePlan {
    public struct Split: Sendable, Equatable {
        /// What sits on the clipboard for your ⌘V.
        public let words: ClipboardItem
        /// What Koe pastes right after it.
        public let files: [URL]
    }

    /// Nil when there is nothing to follow with: no words, or no files.
    public static func split(_ items: [ClipboardItem]) -> Split? {
        guard let words = items.first(where: { if case .text = $0 { true } else { false } }) else { return nil }
        let files = items.compactMap { item -> URL? in
            if case .file(let url) = item { url } else { nil }
        }
        return files.isEmpty ? nil : Split(words: words, files: files)
    }

    /// A terminal pastes a file as its path, and the words already end with every path, so the files stay out.
    public static func takesFiles(appWithBundleID id: String?) -> Bool {
        guard let id = id?.lowercased() else { return true }
        return !terminals.contains { id == $0 || id.hasPrefix($0 + ".") }
    }

    private static let terminals = [
        "com.apple.terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.warp-stable", "dev.warp.warp",
        "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper", "org.tabby",
    ]
}

/// Every bundle Koe copied lately, found again by its words. The clipboard may no longer be the one Koe wrote: you
/// copied other things since, or pasted the words out of a clipboard history. As long as what you paste reads the
/// same, its files still follow.
public struct PasteIndex: Sendable {
    public let limit: Int
    private var splits: [String: PastePlan.Split] = [:]
    private var order: [String] = []

    public init(limit: Int = 200) {
        self.limit = limit
    }

    public mutating func remember(_ split: PastePlan.Split) {
        guard case .text(let plain, _) = split.words, let key = Self.key(plain) else { return }
        order.removeAll { $0 == key }
        order.append(key)
        splits[key] = split
        while order.count > limit { splits[order.removeFirst()] = nil }
    }

    /// The bundle whose words these are, or nil when Koe never copied them.
    public func split(pasting text: String?) -> PastePlan.Split? {
        text.flatMap(Self.key).flatMap { splits[$0] }
    }

    public static func matches(_ pasted: String?, _ text: String) -> Bool {
        guard let pasted, let key = key(pasted) else { return false }
        return key == Self.key(text)
    }

    /// A clipboard history may trim the ends or change the line endings; nothing else may differ.
    static func key(_ text: String) -> String? {
        let key = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }
}
