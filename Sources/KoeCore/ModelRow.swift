import Foundation

/// What a model's row in Settings shows and offers, worked out from its download, the chosen model and the one
/// that runs.
public struct ModelRow: Sendable, Equatable {
    /// The one button a row leads with.
    public enum Action: Sendable, Equatable {
        case download, cancel, use, retry
    }

    public let model: TranscriptionModel
    public let action: Action?
    /// Transcribes the next session. Apple's model is in use whenever the chosen one can't run.
    public let inUse: Bool
    public let canDelete: Bool
    /// Size and languages, the download's progress, or why it stopped.
    public let detail: String
    /// 0 to 1 while it downloads.
    public let fraction: Double?
    public let isError: Bool

    public init(_ model: TranscriptionModel, install: ModelInstall, chosen: ModelID, running: ModelID,
                canDownload: Bool) {
        self.model = model
        inUse = running == model.id
        canDelete = model.needsDownload && install.isInstalled
        var fraction: Double?
        var isError = false
        let summary = "\(model.sizeLabel) · \(model.languages)"
        switch install {
        case _ where !model.needsDownload:
            action = inUse ? nil : .use
            detail = summary
        case .downloading(let done):
            action = .cancel
            fraction = done
            let bytes = ByteCountFormatter.string(fromByteCount: Int64(done * Double(model.bytes)), countStyle: .file)
            detail = "Downloading, \(bytes) of \(model.sizeLabel)"
        case .failed(let message):
            action = .retry
            isError = true
            detail = message
        case .notInstalled where !canDownload:
            action = nil
            detail = "Needs a Mac with Apple silicon."
        case .notInstalled:
            action = .download
            detail = summary
        case .installed:
            action = chosen == model.id ? nil : .use
            detail = summary
        }
        self.fraction = fraction
        self.isError = isError
    }
}
