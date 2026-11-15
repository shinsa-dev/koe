import Foundation
import KoeCore
import Testing

struct NameScanTests {
    /// A home folder in a temporary directory, with `paths` as folders and `files` as files in it.
    private func home(folders: [String], files: [String: String] = [:]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "NameScanTests-\(UUID().uuidString)")
        for folder in folders {
            try FileManager.default.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
        }
        for (path, contents) in files {
            let file = root.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: file)
        }
        return root
    }

    @Test func findsRepositoriesAnywhereButInsideOneAnother() throws {
        let root = try home(folders: [
            "Developer/Projects/shinsa/.git", "Developer/Projects/shinsa/packages/inner/.git",
            "Code/kodama/.git", "notes/plain",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let found = NameScan().repositories(in: root).map(\.lastPathComponent)
        #expect(found == ["kodama", "shinsa"])
    }

    @Test func staysOutOfGuardedHiddenAndBuildFolders() throws {
        let root = try home(folders: [
            "Documents/secret/.git", "Desktop/draft/.git", "Library/thing/.git", ".config/hidden/.git",
            "work/node_modules/dep/.git", "work/real/.git",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(NameScan().repositories(in: root).map(\.lastPathComponent) == ["real"])
    }

    @Test func aWorktreeWithAGitFileCountsAsARepository() throws {
        let root = try home(folders: ["trees/madori-feature"], files: ["trees/madori-feature/.git": "gitdir: /x"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(NameScan().repositories(in: root).map(\.lastPathComponent) == ["madori-feature"])
    }

    @Test func neverFollowsALink() throws {
        let root = try home(folders: ["real/lue/.git"])
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: root.appending(path: "link"),
                                                   withDestinationURL: root.appending(path: "real"))
        #expect(NameScan().repositories(in: root).map(\.path).allSatisfy { !$0.contains("/link/") })
    }

    @Test func stopsAtItsDepthAndFolderLimits() throws {
        let root = try home(folders: ["a/b/c/d/deep/.git", "shallow/.git"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(NameScan(maxDepth: 3).repositories(in: root).map(\.lastPathComponent) == ["shallow"])
        #expect(NameScan(maxDepth: 6, maxFolders: 1).repositories(in: root).isEmpty)
    }

    @Test func readsARepositorysReadmeAndManifests() throws {
        let root = try home(folders: ["BuzzKit-iOS/.git"], files: [
            "BuzzKit-iOS/README.md": "# BuzzKit\n",
            "BuzzKit-iOS/package.json": #"{"name": "@buzz/haptics"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let names = NameScan().names(inRepository: root.appending(path: "BuzzKit-iOS"))
        #expect(names == ["BuzzKit", "BuzzKit", "haptics"])
    }

    @Test func findsAppsAndRepositoriesTogether() throws {
        let root = try home(folders: ["Apps/OrbStack.app/Contents", "Apps/Notes", "src/kanna/.git"])
        defer { try? FileManager.default.removeItem(at: root) }
        let found = NameScan().names(home: root.appending(path: "src"), appFolders: [root.appending(path: "Apps")])
        #expect(found.map(\.name) == ["kanna", "OrbStack"])
        #expect(found.last?.source == .app(root.appending(path: "Apps/OrbStack.app").path))
    }

    @Test func readsWhetherYouCommittedAndWhereARepositoryLives() throws {
        let root = try home(folders: ["kodama/.git/logs"], files: [
            "kodama/.git/logs/HEAD": "0 1 Me <me@x> 1 +0100\tcommit (initial): Start\n",
            "kodama/.git/config": "[remote \"origin\"]\n\turl = https://github.com/chroxify/kodama.git\n",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let git = NameScan().git(of: root.appending(path: "kodama"))
        #expect(git == NameSources.Git(committed: true, remotes: ["github.com/chroxify"]))
    }

    @Test func aWorktreeReadsItsReflogAndItsMainRepositorysConfig() throws {
        let root = try home(folders: ["main/.git/worktrees/feature/logs", "feature"], files: [
            "main/.git/config": "[remote \"origin\"]\n\turl = git@github.com:chroxify/madori.git\n",
            "main/.git/worktrees/feature/commondir": "../..\n",
            "main/.git/worktrees/feature/logs/HEAD": "0 1 Me <me@x> 1 +0100\tcommit: Work\n",
            "feature/.git": "gitdir: ../main/.git/worktrees/feature\n",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let git = NameScan().git(of: root.appending(path: "feature"))
        #expect(git == NameSources.Git(committed: true, remotes: ["github.com/chroxify"]))
    }

    @Test func someoneElsesCloneGivesNoNames() throws {
        let root = try home(folders: ["work/kodama/.git/logs", "sdk/zephyr/.git"], files: [
            "work/kodama/.git/logs/HEAD": "0 1 Me <me@x> 1 +0100\tcommit: Fix\n",
            "work/kodama/.git/config": "[remote \"origin\"]\n\turl = https://github.com/chroxify/kodama\n",
            "sdk/zephyr/.git/config": "[remote \"ncs\"]\n\turl = https://github.com/nrfconnect/sdk-zephyr\n",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(NameScan().names(home: root, appFolders: []).map(\.name) == ["kodama"])
    }
}
