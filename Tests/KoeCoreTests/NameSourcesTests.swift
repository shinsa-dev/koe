import Foundation
import KoeCore
import Testing

struct NameSourcesTests {
    private static let english: Set<String> = [
        "website", "prints", "machine", "outpost", "device", "screen", "studio", "visual", "code", "campaign",
        "pay", "wall", "next", "safari", "notes", "the", "monorepo",
    ]
    private func ordinary(_ word: String) -> Bool { Self.english.contains(word) }

    @Test func aReadmeTitleIsItsFirstHeading() {
        #expect(NameSources.readmeTitle("# Madori\n\nMadori is a workspace.") == "Madori")
        #expect(NameSources.readmeTitle("Intro\n# Lue: the backend\n") == "Lue")
        #expect(NameSources.readmeTitle("# **BuzzKit** - haptics for iOS") == "BuzzKit")
        #expect(NameSources.readmeTitle("No heading here.") == nil)
    }

    @Test func aReadmeThatOpensWithALogoIsTitledByItsAltText() {
        let readme = """
        <div align="center">
          <a href="https://shinsa.dev">
            <img src="./icon.png" alt="Shinsa" height="96" />
        """
        #expect(NameSources.readmeTitle(readme) == "Shinsa")
        #expect(NameSources.readmeTitle("<h1 align=\"center\">Kodama</h1>") == "Kodama")
    }

    @Test func manifestsNameThePackage() {
        #expect(NameSources.manifestName(file: "package.json", contents: #"{"name": "@shinsa/kanna"}"#) == "kanna")
        #expect(NameSources.manifestName(file: "Package.swift", contents: "let p = Package(\n    name: \"BuzzKit\",")
            == "BuzzKit")
        #expect(NameSources.manifestName(file: "Cargo.toml", contents: "[package]\nname = \"typefit\"\n") == "typefit")
        #expect(NameSources.manifestName(file: "pyproject.toml", contents: "[project]\nname = \"eunoe\"") == "eunoe")
        #expect(NameSources.manifestName(file: "package.json", contents: "not json") == nil)
        #expect(NameSources.manifestName(file: "Gemfile", contents: "name = \"x\"") == nil)
    }

    @Test func copyPlatformAndVersionSuffixesComeOff() {
        #expect(NameSources.clean("kodama-old") == "kodama")
        #expect(NameSources.clean("BuzzKit-iOS") == "BuzzKit")
        #expect(NameSources.clean("buzzkit-monorepo") == "buzzkit")
        #expect(NameSources.clean("website-2025") == "website")
        #expect(NameSources.clean("Xcode-27.2.0-Release.Candidate") == "Xcode")
        #expect(NameSources.clean("Teamfight Tactics (PBE)") == "Teamfight Tactics")
        #expect(NameSources.clean("paywall-next") == "paywall-next")
        #expect(NameSources.clean("cs_fas_offers") == "cs-fas-offers")
        #expect(NameSources.clean("s2c") == nil)
        #expect(NameSources.readmeTitle("# Chroxify.com").flatMap(NameSources.clean) == "Chroxify")
        #expect(NameSources.clean("app") == nil)
        #expect(NameSources.clean("a-very-long-folder-name") == nil)
    }

    @Test func onlyNamesAModelWouldMishearCount() {
        #expect(NameSources.counts("Shinsa", isOrdinary: ordinary))
        #expect(NameSources.counts("paywall-next", isOrdinary: ordinary))
        #expect(!NameSources.counts("website", isOrdinary: ordinary))
        #expect(!NameSources.counts("Screen Studio", isOrdinary: ordinary))
        #expect(!NameSources.counts("campaign-os", isOrdinary: ordinary))
        #expect(!NameSources.counts("cs", isOrdinary: ordinary))
    }

    @Test func aRepositoryGivesItsFolderReadmeAndManifestNames() {
        let names = NameSources.repository(
            folder: "BuzzKit-iOS", readme: "# BuzzKit\n",
            manifests: ["Package.swift": "name: \"BuzzKit\"", "package.json": #"{"name":"buzzkit-monorepo"}"#])
        #expect(names == ["BuzzKit", "BuzzKit", "BuzzKit", "buzzkit"])
        #expect(NameSources.repository(folder: "lue", readme: nil, manifests: [:]) == ["lue"])
    }

    @Test func anAppGoesByItsBundleName() {
        #expect(NameSources.app(bundle: "OrbStack.app") == "OrbStack")
        #expect(NameSources.app(bundle: "Visual Studio Code.app") == "Visual Studio Code")
        #expect(NameSources.app(bundle: "1Password.app") == nil)
    }

    @Test func eachNameIsLearnedOnceInItsMostDeliberateSpelling() {
        let repo = LearnedName.Source.repository("/Users/me/Developer/buzzkit")
        let other = LearnedName.Source.repository("/Users/me/Developer/BuzzKit-iOS")
        let found = [
            LearnedName("buzzkit", source: repo), LearnedName("BuzzKit", source: other),
            LearnedName("kodama", source: repo), LearnedName("website", source: repo),
            LearnedName("OrbStack", source: .app("/Applications/OrbStack.app")),
            LearnedName("Screen Studio", source: .app("/Applications/Screen Studio.app")),
        ]
        let learned = NameSources.learn(found, isOrdinary: ordinary)
        #expect(learned.map(\.name) == ["BuzzKit", "Kodama", "OrbStack"])
        #expect(learned.first?.source == repo)
    }

    @Test func aHyphenatedLowerCaseNameKeepsItsSpelling() {
        let learned = NameSources.learn([LearnedName("paywall-next", source: .repository("/p"))], isOrdinary: ordinary)
        #expect(learned.map(\.name) == ["paywall-next"])
    }

    @Test func learnedNamesSurviveACacheRoundTrip() throws {
        let names = [LearnedName("Shinsa", source: .repository("/r")), LearnedName("Droppy", source: .app("/a"))]
        let data = try JSONEncoder().encode(names)
        #expect(try JSONDecoder().decode([LearnedName].self, from: data) == names)
    }

    @Test func aReadmeTitleOfSeveralWordsIsAPhraseNotAName() {
        let names = NameSources.repository(folder: "openthread", readme: "# What is OpenThread\n", manifests: [:])
        #expect(names == ["openthread"])
    }

    @Test func aReflogWithACommitMeansYouWorkedThere() {
        let clone = "0000 9133 Me <me@x> 1 +0100\tclone: from https://github.com/a/b\n"
            + "9133 1234 Me <me@x> 2 +0100\tpull: Fast-forward\n"
        #expect(!NameSources.hasCommits(reflog: clone))
        #expect(NameSources.hasCommits(reflog: clone + "1234 5678 Me <me@x> 3 +0100\tcommit: Fix it\n"))
        #expect(NameSources.hasCommits(reflog: "1 2 Me <me@x> 3 +0100\tcommit (initial): Start\n"))
    }

    @Test func remotesNameTheirOwner() {
        let config = """
        [remote "origin"]
        \turl = https://github.com/chroxify/kodama.git
        [remote "mirror"]
        \turl = git@GitHub.com:Shinsa-Dev/shinsa.git
        [branch "main"]
        \tremote = origin
        """
        #expect(NameSources.remoteOwners(config: config) == ["github.com/chroxify", "github.com/shinsa-dev"])
        #expect(NameSources.remoteOwners(config: "[core]\n\tbare = false\n").isEmpty)
    }

    @Test func onlyYourRepositoriesGiveNames() {
        let mine = NameSources.Git(committed: true, remotes: ["github.com/chroxify"])
        let freshCloneOfMine = NameSources.Git(committed: false, remotes: ["github.com/chroxify"])
        let local = NameSources.Git(committed: false, remotes: [])
        let sdk = NameSources.Git(committed: false, remotes: ["github.com/nrfconnect"])
        let yours = NameSources.yours([("kodama", mine), ("better-auth", freshCloneOfMine), ("lue", local),
                                       ("zephyr", sdk)])
        #expect(yours == ["kodama", "better-auth", "lue"])
    }
}
