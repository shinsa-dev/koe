import Foundation

/// Which model transcribes now: the one `ModelPlan` streams with (`liveCandidate`) when it can run, otherwise Apple's
/// built-in model, with the reason Settings shows.
public struct TranscriberRoute: Sendable, Equatable {
    public enum Fallback: Sendable, Equatable {
        case notDownloaded
        case downloading
        case preparing
        case needsAppleSilicon
        case failedToLoad(String)
    }

    public let chosen: ModelID
    public let fallback: Fallback?

    /// The model that runs.
    public var model: ModelID { fallback == nil ? chosen : .apple }

    /// `isLoaded` is whether the chosen model has loaded in this run: until it has, a session would wait on its load,
    /// which takes minutes when macOS has to compile it again (after an update), so Apple's model runs meanwhile.
    public static func resolve(chosen: ModelID, install: ModelInstall, canRun: Bool, loadError: String?,
                               isLoaded: Bool = true) -> TranscriberRoute {
        let model = TranscriptionModel.model(chosen)
        guard model.needsDownload else { return TranscriberRoute(chosen: chosen, fallback: nil) }
        let fallback: Fallback? = if !canRun {
            .needsAppleSilicon
        } else if install.isDownloading {
            .downloading
        } else if install == .preparing {
            .preparing
        } else if !install.isInstalled {
            .notDownloaded
        } else if let loadError {
            .failedToLoad(loadError)
        } else if !isLoaded {
            .preparing
        } else {
            nil
        }
        return TranscriberRoute(chosen: chosen, fallback: fallback)
    }

    /// Why Apple's model runs instead of the live candidate, or nil when the candidate runs.
    public var reason: String? {
        guard let fallback else { return nil }
        let name = TranscriptionModel.model(chosen).name
        return switch fallback {
        case .notDownloaded: "Koe uses Apple's model until \(name) is downloaded."
        case .downloading: "Koe uses Apple's model until \(name) finishes downloading."
        case .preparing: "Koe uses Apple's model while \(name) gets ready for this Mac."
        case .needsAppleSilicon: "\(name) needs a Mac with Apple silicon, so Koe uses Apple's model."
        case .failedToLoad(let error): "\(name) didn't load, so Koe uses Apple's model. \(error)"
        }
    }
}
