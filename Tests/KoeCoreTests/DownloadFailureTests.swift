import Foundation
import KoeCore
import Testing

struct DownloadFailureTests {
    /// What Hugging Face's client throws when the Mac has no network: its own error, not a `URLError`.
    private struct HubOffline: LocalizedError {
        var errorDescription: String? { "Offline mode error: Repository not available locally" }
    }

    private let offline = "The download needs an internet connection. Try again once you're online."

    @Test func aFirstDownloadWithNoNetworkSaysSoInASentence() {
        let failure = DownloadFailure(HubOffline(), online: false)
        #expect(failure == .offline)
        #expect(failure.message == offline)
        #expect(!failure.message.contains("Offline mode error"))
    }

    @Test func aConnectionThatDropsMidDownloadIsOfflineToo() {
        #expect(DownloadFailure(URLError(.notConnectedToInternet), online: true) == .offline)
        #expect(DownloadFailure(URLError(.networkConnectionLost), online: true) == .offline)
        #expect(DownloadFailure(URLError(.badServerResponse), online: false) == .offline)
    }

    @Test func otherFailuresKeepTheirOwnSentence() {
        #expect(DownloadFailure(URLError(.timedOut), online: true) == .timedOut)
        #expect(DownloadFailure(HubSnapshot.Mismatch(path: "vocab.json"), online: true) == .mismatch)
        #expect(DownloadFailure(HubSnapshot.Mismatch(path: "vocab.json"), online: false) == .mismatch)
        #expect(DownloadFailure(HubOffline(), online: true).message == "The download didn't finish. Try again in a moment.")
    }

    @Test func theOfflineRowOffersTryAgain() {
        let plan = ModelPlan(installs: [.fluidSpeechPro: .failed(DownloadFailure(HubOffline(), online: false).message)],
                             deleted: [], canDownload: true)
        let row = ModelStatus(plan: plan, inUse: .apple).rows.first { $0.id == .fluidSpeechPro }
        #expect(row?.state == offline)
        #expect(row?.action == .retry)
        #expect(row?.isError == true)
    }
}
