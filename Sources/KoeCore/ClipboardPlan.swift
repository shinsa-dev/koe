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

    /// What the pill shows once the bundle is on the clipboard: "Copied" or "Pasted", then what it held.
    public static func summary(for items: [ClipboardItem], words: Int, pasted: Bool) -> (title: String, detail: String) {
        let files = items.filter { if case .file = $0 { true } else { false } }.count
        var parts: [String] = []
        if words > 0 { parts.append(words == 1 ? "1 word" : "\(words) words") }
        if files > 0 { parts.append(files == 1 ? "1 file" : "\(files) files") }
        let detail = parts.isEmpty ? "The transcript" : parts.joined(separator: " and ")
        return (pasted ? "Pasted" : "Copied", detail)
    }
}
