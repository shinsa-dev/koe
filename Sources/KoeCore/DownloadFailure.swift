import Foundation

/// Why a model download stopped, in a sentence for its row in Settings. The error itself goes to the log: what the
/// downloaders throw ("Offline mode error: Repository not available locally") means nothing to the person reading it.
public enum DownloadFailure: Equatable, Sendable {
    case offline, timedOut, mismatch, other

    /// `online` is whether the Mac had a network when the download stopped. Without one, any error is the missing
    /// connection: Hugging Face's client then throws its own offline error rather than a `URLError`.
    public init(_ error: any Error, online: Bool) {
        if error is HubSnapshot.Mismatch {
            self = .mismatch
        } else if !online {
            self = .offline
        } else if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                self = .offline
            case .timedOut:
                self = .timedOut
            default:
                self = .other
            }
        } else {
            self = .other
        }
    }

    public var message: String {
        switch self {
        case .offline: "The download needs an internet connection. Try again once you're online."
        case .timedOut: "Hugging Face took too long to answer. Try again in a moment."
        case .mismatch: "The downloaded files weren't the ones Koe expects, so Koe deleted them. Try again."
        case .other: "The download didn't finish. Try again in a moment."
        }
    }
}
