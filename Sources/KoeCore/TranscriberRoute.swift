import Foundation

/// Which model transcribes now: the one chosen in Settings when it can run, otherwise Apple's built-in model, with
/// the reason Settings shows.
public struct TranscriberRoute: Sendable, Equatable {
    public enum Fallback: Sendable, Equatable {
        case notDownloaded
        case downloading
        case needsAppleSilicon
        case failedToLoad(String)
    }

    public let chosen: ModelID
    public let fallback: Fallback?

    /// The model that runs.
    public var model: ModelID { fallback == nil ? chosen : .apple }

    public static func resolve(chosen: ModelID, install: ModelInstall, canRun: Bool, loadError: String?)
        -> TranscriberRoute {
        let model = TranscriptionModel.model(chosen)
        guard model.needsDownload else { return TranscriberRoute(chosen: chosen, fallback: nil) }
        let fallback: Fallback? = if !canRun {
            .needsAppleSilicon
        } else if install.isDownloading {
            .downloading
        } else if !install.isInstalled {
            .notDownloaded
        } else if let loadError {
            .failedToLoad(loadError)
        } else {
            nil
        }
        return TranscriberRoute(chosen: chosen, fallback: fallback)
    }

    /// Why Apple's model runs instead of the chosen one, or nil when the chosen one runs.
    public var reason: String? {
        guard let fallback else { return nil }
        let name = TranscriptionModel.model(chosen).name
        return switch fallback {
        case .notDownloaded: "\(name) isn't downloaded, so Koe uses Apple's model."
        case .downloading: "Koe uses Apple's model until \(name) finishes downloading."
        case .needsAppleSilicon: "\(name) needs a Mac with Apple silicon, so Koe uses Apple's model."
        case .failedToLoad(let error): "\(name) didn't load, so Koe uses Apple's model. \(error)"
        }
    }
}
