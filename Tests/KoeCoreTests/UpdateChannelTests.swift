import Foundation
import KoeCore
import Testing

struct UpdateChannelTests {
    @Test(arguments: [
        ("1.2.0", UpdateChannel.stable),
        ("0.0.0-dev", .stable),
        ("1.2.0-beta.3", .stable),
        ("1.2.0-canary.41", .canary),
        ("1.2.0-canary.41+abc1234", .canary),
        ("", .stable),
    ])
    func aBuildFollowsTheChannelItCameFrom(version: String, channel: UpdateChannel) {
        #expect(UpdateChannel(version: version) == channel)
    }

    @Test func eachChannelHasItsOwnAppcast() {
        #expect(UpdateChannel.stable.feedURL.absoluteString == "https://shinsa.dev/koe/appcast/stable.xml")
        #expect(UpdateChannel.canary.feedURL.absoluteString == "https://shinsa.dev/koe/appcast/canary.xml")
    }

    @Test func aPickedChannelWinsOverTheBuildsAndIsKept() {
        var settings = KoeSettings()
        #expect(settings.updateChannel(forVersion: "1.2.0-canary.3") == .canary)
        settings.updateChannel = .stable
        #expect(settings.updateChannel(forVersion: "1.2.0-canary.3") == .stable)
        let reloaded = KoeSettings(values: settings.values)
        #expect(reloaded.updateChannel == .stable)
    }

    @Test func anUnknownChannelFollowsTheBuild() {
        let settings = KoeSettings(values: [KoeSettings.Key.updateChannel: "nightly"])
        #expect(settings.updateChannel == nil)
        #expect(KoeSettings(values: [KoeSettings.Key.updateChannel: "beta"]).updateChannel == nil)
        #expect(KoeSettings().values[KoeSettings.Key.updateChannel] == nil)
    }
}
