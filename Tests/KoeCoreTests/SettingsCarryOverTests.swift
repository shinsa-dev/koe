import Foundation
import KoeCore
import Testing

struct SettingsCarryOverTests {
    private let old: [String: Any] = [
        "appearance": "dark",
        "transcriptionModel": "whisper-large-v3-turbo",
        "shortcut.start": "fn",
        "SUSkippedVersion": "1.1.0",
        "asked.microphone": true,
        "asked.screenRecording": true,
        "AppleFontSmoothing": 0,
        "NSWindow Frame Settings": "0 0 640 480",
        "com.apple.SwiftUI.Settings": "x",
    ]

    @Test func copiesKoesOwnSettingsAndMarksItDone() {
        let entries = SettingsCarryOver.entries(old: old, current: nil)
        #expect(Set(entries.keys) == [
            "appearance", "transcriptionModel", "shortcut.start", "SUSkippedVersion", SettingsCarryOver.doneKey,
        ])
        #expect(entries["appearance"] as? String == "dark")
        #expect(entries[SettingsCarryOver.doneKey] as? Bool == true)
    }

    @Test func leavesPermissionFlagsAndSystemKeysBehind() {
        let entries = SettingsCarryOver.entries(old: old, current: [:])
        #expect(!entries.keys.contains { $0.hasPrefix("asked.") })
        #expect(entries["AppleFontSmoothing"] == nil)
        #expect(entries["NSWindow Frame Settings"] == nil)
        #expect(entries["com.apple.SwiftUI.Settings"] == nil)
    }

    @Test func neverOverwritesWhatTheNewIdAlreadyHas() {
        let entries = SettingsCarryOver.entries(old: old, current: ["appearance": "light"])
        #expect(entries["appearance"] == nil)
        #expect(entries["transcriptionModel"] as? String == "whisper-large-v3-turbo")
    }

    @Test func runsOnlyOnce() {
        let entries = SettingsCarryOver.entries(old: old, current: [SettingsCarryOver.doneKey: true])
        #expect(entries.isEmpty)
    }

    @Test func withoutAnOldDomainItOnlyMarksItDone() {
        let entries = SettingsCarryOver.entries(old: nil, current: nil)
        #expect(Set(entries.keys) == [SettingsCarryOver.doneKey])
    }

    @Test func oldMarkerIsNeverCopiedBack() {
        let entries = SettingsCarryOver.entries(old: [SettingsCarryOver.doneKey: false], current: nil)
        #expect(entries[SettingsCarryOver.doneKey] as? Bool == true)
    }

    @Test func writesIntoTheDefaultsAndThenStops() throws {
        let suite = "studio.overclock.koe.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        SettingsCarryOver.apply(old: old, current: defaults.persistentDomain(forName: suite), to: defaults)
        #expect(defaults.string(forKey: "appearance") == "dark")
        #expect(defaults.object(forKey: "asked.microphone") == nil)
        #expect(defaults.bool(forKey: SettingsCarryOver.doneKey))

        defaults.set("light", forKey: "appearance")
        SettingsCarryOver.apply(old: old, current: defaults.persistentDomain(forName: suite), to: defaults)
        #expect(defaults.string(forKey: "appearance") == "light")
    }
}
