import Foundation
import KoeCore
import Observation
import Sparkle

/// Koe's updates through Sparkle: each channel has its own appcast at shinsa.dev/koe, and every update is checked
/// against the EdDSA key in Info.plist before it installs. A build without a version (`./build.sh` alone) checks only
/// when you ask, so a development build never replaces itself on its own.
@MainActor
@Observable
final class Updater: NSObject {
    let version: String
    let build: String
    private(set) var canCheck = false
    private(set) var lastChecked: Date?
    @ObservationIgnored private let library: SessionLibrary
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    @ObservationIgnored private let bundle: Bundle

    init(library: SessionLibrary, bundle: Bundle = .main) {
        self.library = library
        self.bundle = bundle
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0-dev"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// Starts Sparkle, which then checks on its schedule. It needs an app bundle; `swift run` has none.
    func start() {
        guard controller == nil, bundle.bundleURL.pathExtension == "app",
              bundle.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self,
                                                      userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        canCheck = updater.canCheckForUpdates
        lastChecked = updater.lastUpdateCheckDate
        observations = [
            updater.observe(\.canCheckForUpdates) { [weak self] updater, _ in
                let can = updater.canCheckForUpdates
                Task { @MainActor in self?.canCheck = can }
            },
            updater.observe(\.lastUpdateCheckDate) { [weak self] updater, _ in
                let date = updater.lastUpdateCheckDate
                Task { @MainActor in self?.lastChecked = date }
            },
        ]
    }

    var isDevelopmentBuild: Bool { build == "0" }

    var channel: UpdateChannel { library.settings.updateChannel(forVersion: version) }

    /// Picks the channel; the next check, which comes soon after, reads its appcast.
    func choose(_ channel: UpdateChannel) {
        guard channel != self.channel || library.settings.updateChannel == nil else { return }
        library.update { $0.updateChannel = channel }
        controller?.updater.resetUpdateCycleAfterShortDelay()
    }

    /// Checks now and shows what Sparkle finds, an update or that Koe is up to date.
    func checkNow() {
        controller?.checkForUpdates(nil)
    }
}

extension Updater: SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        MainActor.assumeIsolated { channel.feedURL.absoluteString }
    }
}
