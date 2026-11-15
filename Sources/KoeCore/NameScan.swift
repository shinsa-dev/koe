import Foundation

/// Finds the names on this Mac: every git repository under the home folder and every installed app. It reads only
/// folder listings, READMEs and manifests, never leaves the start volume or follows a link, and stays out of the folders
/// macOS guards (Desktop, Documents, Downloads, Library and the media folders), so it never raises a permission prompt.
/// It stops at `maxFolders`, so a home full of files can't keep it busy. It does no work of its own on a session's path:
/// the app runs it in the background and keeps what it found.
public struct NameScan: Sendable {
    /// Folders never read: the ones macOS guards, and the ones that hold build output or other people's code.
    public static let skipped: Set<String> = [
        "Library", "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Public", "Applications",
        "node_modules", "DerivedData", "Pods", "Carthage", "vendor", "dist", "build", "target", "venv", "go",
    ]
    static let readmes = ["README.md", "readme.md", "Readme.md", "README"]
    static let manifests = ["package.json", "Package.swift", "Cargo.toml", "pyproject.toml"]
    /// The longest README or manifest read; a title and a name sit at the top.
    static let maxFileBytes = 65_536
    /// How much of the end of a reflog is read: the latest few thousand moves.
    static let maxReflogBytes = 1_048_576

    public var maxDepth = 6
    public var maxFolders = 40_000

    public init(maxDepth: Int = 6, maxFolders: Int = 40_000) {
        self.maxDepth = maxDepth
        self.maxFolders = maxFolders
    }

    /// Every name found, before `NameSources.learn` picks the ones that count.
    /// Only your own repositories give names (`NameSources.yours`), so an SDK's dozens of cloned modules don't.
    public func names(home: URL, appFolders: [URL]) -> [LearnedName] {
        let repositories = repositories(in: home)
        let yours = NameSources.yours(repositories.map { (repo: $0.path, git: git(of: $0)) })
        let named = repositories.filter { yours.contains($0.path) }.flatMap { repo in
            names(inRepository: repo).map { LearnedName($0, source: .repository(repo.path)) }
        }
        return named + apps(in: appFolders)
    }

    /// What a repository's git folder says about who works in it: whether you committed in it, from its reflog, and
    /// its remotes, from its config. A worktree's `.git` file points at its own git folder inside the main one.
    public func git(of repo: URL) -> NameSources.Git {
        var folder = repo.appending(path: ".git")
        var common = folder
        if let pointer = read(folder), pointer.hasPrefix("gitdir:") {
            let path = pointer.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            folder = Self.resolve(path, from: repo)
            common = read(folder.appending(path: "commondir"))
                .map { Self.resolve($0.trimmingCharacters(in: .whitespacesAndNewlines), from: folder) } ?? folder
        }
        let reflog = read(folder.appending(path: "logs/HEAD"), tail: Self.maxReflogBytes) ?? ""
        let config = read(common.appending(path: "config")) ?? ""
        return NameSources.Git(committed: NameSources.hasCommits(reflog: reflog),
                               remotes: NameSources.remoteOwners(config: config))
    }

    /// The git repositories under `root`, breadth first, without looking inside one once found.
    public func repositories(in root: URL) -> [URL] {
        let files = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isVolumeKey, .isPackageKey]
        var found: [URL] = []
        var level = [root]
        var visited = 0
        for _ in 0...maxDepth {
            var next: [URL] = []
            for folder in level {
                guard visited < maxFolders else { return found }
                visited += 1
                if folder != root, files.fileExists(atPath: folder.appending(path: ".git").path) {
                    found.append(folder)
                    continue
                }
                let children = (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                options: .skipsHiddenFiles)) ?? []
                for child in children where !Self.skipped.contains(child.lastPathComponent) {
                    guard let values = try? child.resourceValues(forKeys: Set(keys)), values.isDirectory == true,
                          values.isSymbolicLink != true, values.isVolume != true, values.isPackage != true
                    else { continue }
                    next.append(child)
                }
            }
            level = next.sorted { $0.path < $1.path }
        }
        return found
    }

    /// The names a repository gives: its folder, its README's title and its manifests' package names.
    public func names(inRepository repo: URL) -> [String] {
        let readme = Self.readmes.lazy.compactMap { read(repo.appending(path: $0)) }.first
        var manifests: [String: String] = [:]
        for file in Self.manifests { manifests[file] = read(repo.appending(path: file)) }
        return NameSources.repository(folder: repo.lastPathComponent, readme: readme, manifests: manifests)
    }

    /// The installed apps in `folders`, one level deep.
    public func apps(in folders: [URL]) -> [LearnedName] {
        folders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
                .filter { $0.hasSuffix(".app") }
                .compactMap { bundle in
                    NameSources.app(bundle: bundle)
                        .map { LearnedName($0, source: .app(folder.appending(path: bundle).path)) }
                }
        }
    }

    /// A path git wrote, absolute or relative to `folder`.
    private static func resolve(_ path: String, from folder: URL) -> URL {
        (path.hasPrefix("/") ? URL(filePath: path) : folder.appending(path: path)).standardizedFileURL
    }

    /// The start of a file, or with `tail` its end, up to that many bytes.
    private func read(_ file: URL, tail: Int? = nil) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        if let tail, let size = try? handle.seekToEnd(), size > UInt64(tail) {
            try? handle.seek(toOffset: size - UInt64(tail))
        } else {
            try? handle.seek(toOffset: 0)
        }
        guard let data = try? handle.read(upToCount: tail ?? Self.maxFileBytes) else { return nil }
        return String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1)
    }
}
