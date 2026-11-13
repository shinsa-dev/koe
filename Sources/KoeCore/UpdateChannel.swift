import Foundation

/// Which releases Koe updates to. Every channel is the same app, so switching keeps your settings and sessions; each
/// has its own appcast at shinsa.dev/koe, written by the Release workflow.
public enum UpdateChannel: String, CaseIterable, Sendable {
    case stable, canary

    public static let feedRoot = URL(string: "https://shinsa.dev/koe/appcast")!

    public var feedURL: URL { Self.feedRoot.appendingPathComponent("\(rawValue).xml") }

    /// The channel a build came from, by its version's prerelease part: `1.2.0-canary.41` is a canary, anything else
    /// stable. Until you pick one, Koe stays on the channel it was installed from.
    public init(version: String) {
        let prerelease = version.split(separator: "-", maxSplits: 1).dropFirst().first ?? ""
        self = Self.allCases.first { $0 != .stable && prerelease.hasPrefix($0.rawValue) } ?? .stable
    }
}
