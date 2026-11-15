import Foundation

/// A name Koe learned from this Mac, and where it found it, so Settings can say why it is in the dictionary.
public struct LearnedName: Codable, Hashable, Sendable {
    public enum Source: Codable, Hashable, Sendable {
        /// A git repository, by its folder.
        case repository(String)
        /// An installed app, by its bundle.
        case app(String)
    }

    public var name: String
    public var source: Source

    public init(_ name: String, source: Source) {
        self.name = name
        self.source = source
    }
}

/// Which names on this Mac become dictionary words, and how they are spelled. A repository gives its folder name, the
/// title of its README and the names in its package manifests; an app gives its own name. A name counts when a model
/// would likely mishear it: it has a part that isn't ordinary English and is at least three letters long. Version,
/// platform and copy suffixes come off ("kodama-old", "BuzzKit-iOS", "website-2025"), and of the spellings found for
/// one name the most deliberate wins: "BuzzKit" from a manifest over "buzzkit" from a folder.
public enum NameSources {
    /// Suffixes that say which copy or build of a project a folder holds, not what it is called.
    static let noise: Set<String> = [
        "old", "new", "backup", "bak", "copy", "tmp", "temp", "archive", "archived", "legacy", "fork", "wip",
        "monorepo", "mono", "repo", "ios", "android", "macos", "mac", "web", "app", "api", "cli", "sdk", "server",
        "client", "main", "master", "dev", "prod", "staging", "beta", "alpha", "release", "candidate", "poc", "demo",
        "example", "playground", "com", "io", "sh",
    ]
    /// The most words a name may have: longer titles are sentences, not names.
    static let maxWords = 3
    /// The shortest part that makes a name worth learning.
    static let minDistinct = 3

    /// The names a repository gives: its folder, its README's title and its manifests' names, each cleaned. A
    /// README title or manifest name of several words is a phrase ("What is OpenThread"), not a name, so only its
    /// one-word names count.
    public static func repository(folder: String, readme: String?, manifests: [String: String]) -> [String] {
        var named: [String] = []
        if let readme, let title = readmeTitle(readme) { named.append(title) }
        for (file, contents) in manifests.sorted(by: { $0.key < $1.key }) {
            if let name = manifestName(file: file, contents: contents) { named.append(name) }
        }
        return [folder].compactMap(clean) + named.compactMap(clean).filter { !$0.contains(" ") }
    }

    /// What Koe reads from a repository's git folder.
    public struct Git: Sendable, Equatable {
        /// You made a commit in it, as its reflog records.
        public var committed: Bool
        /// The owners its remotes point at, as `host/owner`.
        public var remotes: Set<String>

        public init(committed: Bool, remotes: Set<String>) {
            self.committed = committed
            self.remotes = remotes
        }
    }

    /// The repositories that are yours: one you committed in, one with no remote (a project only on this Mac), and one
    /// whose remote belongs to an owner you committed for, so a fresh clone of your own project counts. A clone of
    /// someone else's code, such as an SDK's modules, doesn't.
    public static func yours(_ repositories: [(repo: String, git: Git)]) -> Set<String> {
        let owners = repositories.filter(\.git.committed).reduce(into: Set<String>()) { $0.formUnion($1.git.remotes) }
        return Set(repositories.filter { item in
            item.git.committed || item.git.remotes.isEmpty || !item.git.remotes.isDisjoint(with: owners)
        }.map(\.repo))
    }

    /// Whether a reflog records a commit made here, not only checkouts, clones and pulls.
    public static func hasCommits(reflog: String) -> Bool {
        reflog.contains("\tcommit:") || reflog.contains("\tcommit (")
    }

    /// The owners a git config's remotes point at, as `host/owner`: `github.com/chroxify` for both
    /// `https://github.com/chroxify/kodama.git` and `git@github.com:chroxify/kodama.git`.
    public static func remoteOwners(config: String) -> Set<String> {
        var owners = Set<String>()
        for line in config.split(separator: "\n") {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("url"), let equals = line.firstIndex(of: "=") else { continue }
            var url = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if let scheme = url.range(of: "://") { url = String(url[scheme.upperBound...]) }
            if let user = url.firstIndex(of: "@") { url = String(url[url.index(after: user)...]) }
            let parts = url.split(whereSeparator: { $0 == "/" || $0 == ":" })
            if parts.count >= 3 { owners.insert("\(parts[0])/\(parts[1])".lowercased()) }
        }
        return owners
    }

    /// The name an app goes by: its bundle's file name without `.app`, cleaned.
    public static func app(bundle: String) -> String? {
        clean(bundle.hasSuffix(".app") ? String(bundle.dropLast(4)) : bundle)
    }

    /// The README's title: its first heading, or the alt text of the logo many READMEs open with.
    public static func readmeTitle(_ text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).prefix(40) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("# ") { return title(String(line.dropFirst(2))) }
            if let heading = between(line, "<h1", "</h1>") { return title(stripTags("<h1" + heading)) }
            if line.contains("<img"), let alt = between(line, "alt=\"", "\""), !alt.isEmpty { return title(alt) }
        }
        return nil
    }

    /// The package's name in a manifest Koe knows: `package.json`, `Package.swift`, `Cargo.toml` or `pyproject.toml`.
    public static func manifestName(file: String, contents: String) -> String? {
        let name: String?
        switch file {
        case "package.json":
            let object = try? JSONSerialization.jsonObject(with: Data(contents.utf8)) as? [String: Any]
            name = (object?["name"] as? String).map { $0.split(separator: "/").last.map(String.init) ?? $0 }
        case "Package.swift":
            name = between(contents, "name: \"", "\"")
        case "Cargo.toml", "pyproject.toml":
            name = contents.split(separator: "\n").lazy
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.hasPrefix("name") && $0.contains("=") }
                .flatMap { between($0, "\"", "\"") }
        default:
            name = nil
        }
        return name?.isEmpty == false ? name : nil
    }

    /// The name without its noise: cut at the first part with a digit, then copy, platform and build suffixes off.
    /// Parts joined by hyphens or underscores stay hyphenated; spaces stay spaces.
    public static func clean(_ raw: String) -> String? {
        let bare = raw.range(of: "(").map { String(raw[..<$0.lowerBound]) } ?? raw
        let trimmed = bare.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let spaced = trimmed.contains(" ")
        var parts = trimmed.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " || $0 == "." })
            .map(String.init)
        if let digit = parts.firstIndex(where: { $0.contains(where: \.isNumber) }) { parts = Array(parts[..<digit]) }
        while let last = parts.last, parts.count > 1, noise.contains(last.lowercased()) { parts.removeLast() }
        guard !parts.isEmpty, parts.count <= maxWords,
              parts.allSatisfy({ $0.allSatisfy { $0.isLetter || $0 == "'" } }) else { return nil }
        if parts.count == 1, noise.contains(parts[0].lowercased()) { return nil }
        return parts.joined(separator: spaced ? " " : "-")
    }

    /// Whether a cleaned name is worth learning: one of its parts is three letters or more and not ordinary English.
    /// `isOrdinary` gets each part lowercased.
    public static func counts(_ name: String, isOrdinary: (String) -> Bool) -> Bool {
        let parts = name.split(whereSeparator: { $0 == "-" || $0 == " " }).map { $0.lowercased() }
        return parts.contains { $0.count >= minDistinct && !isOrdinary($0) }
    }

    /// The names worth learning, one spelling each: the most deliberate one, then the first found. Names are
    /// compared by their letters alone, so "buzzkit", "BuzzKit" and "Buzz-Kit" are one name.
    public static func learn(_ found: [LearnedName], isOrdinary: (String) -> Bool) -> [LearnedName] {
        var chosen: [String: LearnedName] = [:]
        var order: [String] = []
        for item in found {
            guard counts(item.name, isOrdinary: isOrdinary) else { continue }
            let key = item.name.lowercased().filter(\.isLetter)
            if let current = chosen[key] {
                if care(item.name) > care(current.name) { chosen[key]?.name = item.name }
            } else {
                chosen[key] = LearnedName(spelled(item.name), source: item.source)
                order.append(key)
            }
        }
        return order.compactMap { chosen[$0] }
    }

    /// How deliberately a spelling was cased: capitals inside it ("BuzzKit") beat a capital first ("Kodama"), which
    /// beats none ("kodama").
    private static func care(_ name: String) -> Int {
        if name.dropFirst().contains(where: \.isUppercase) { return 2 }
        return name.first?.isUppercase == true ? 1 : 0
    }

    /// A one-word name in lower case, as folders are named, is a name all the same: it gets its capital.
    private static func spelled(_ name: String) -> String {
        guard name.allSatisfy({ $0.isLowercase }) else { return name }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// A heading as a name: the part before a colon or a dash, without markdown, emoji or links.
    private static func title(_ text: String) -> String? {
        var title = stripTags(text)
        for separator in [":", " - ", " – ", " — ", " | ", "(", "["] {
            if let range = title.range(of: separator) { title = String(title[..<range.lowerBound]) }
        }
        title = String(title.unicodeScalars.filter { CharacterSet.letters.union(.decimalDigits)
            .union(CharacterSet(charactersIn: " -_'.")).contains($0) })
        title = title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[*`]", with: "", options: .regularExpression)
    }

    private static func between(_ text: String, _ open: String, _ close: String) -> String? {
        guard let start = text.range(of: open),
              let end = text.range(of: close, range: start.upperBound..<text.endIndex) else { return nil }
        return String(text[start.upperBound..<end.lowerBound])
    }
}
