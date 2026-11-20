import Foundation

/// What the Transcription card shows: a read-only row per model, saying what Koe uses it for and where it stands, and
/// the downloads you can delete. The only buttons are Try again after a failure and Download for a model you deleted.
public struct ModelStatus: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        case download, retry
    }

    public struct Row: Sendable, Equatable, Identifiable {
        public let id: ModelID
        public let title: String
        /// What Koe uses it for ("Live", "Refine", "Live and refine"), or nil when it uses it for nothing.
        public let role: String?
        public let state: String
        /// 0 to 1 while it downloads.
        public let fraction: Double?
        public let action: Action?
        public let isError: Bool
    }

    /// A download a menu deletes, with its size.
    public struct Download: Sendable, Equatable, Identifiable {
        public let id: ModelID
        public let title: String
        public let size: String
    }

    public let rows: [Row]
    public let deletable: [Download]

    /// `inUse` is the model that streams now; `loadErrors` the models that didn't load in this run.
    public init(plan: ModelPlan, inUse: ModelID, loadErrors: [ModelID: String] = [:]) {
        // Fluid Speech Pro replaced NVIDIA's Parakeet models: they show only while one is on this Mac.
        let listed = TranscriptionModel.catalog.filter { model in
            ![.parakeetV3, .parakeetV2].contains(model.id) || plan.install(model.id) != .notInstalled
        }
        rows = listed.map { Self.row($0, plan: plan, inUse: inUse, loadError: loadErrors[$0.id]) }
        deletable = TranscriptionModel.catalog
            .filter { $0.needsDownload && plan.install($0.id).isInstalled }
            .map { Download(id: $0.id, title: $0.name, size: $0.sizeLabel) }
    }

    static func roleLabel(_ roles: Set<ModelRole>) -> String? {
        switch (roles.contains(.live), roles.contains(.refine)) {
        case (true, true): "Live and refine"
        case (true, false): "Live"
        case (false, true): "Refine"
        case (false, false): nil
        }
    }

    private static func row(_ model: TranscriptionModel, plan: ModelPlan, inUse: ModelID, loadError: String?) -> Row {
        var fraction: Double?
        var action: Action?
        var isError = false
        let state: String
        switch plan.install(model.id) {
        case _ where !model.needsDownload:
            state = inUse == .apple && plan.liveCandidate != .apple
                ? "Built in. Koe uses it until \(TranscriptionModel.model(plan.liveCandidate).name) is ready."
                : "Built in."
        case .installed where loadError != nil:
            isError = true
            state = "Didn't load. \(loadError ?? "")"
        case .installed where model.id == plan.liveCandidate && inUse != model.id:
            state = "Loading."
        case .installed:
            state = "Ready."
        case .downloading(let done):
            fraction = done
            let bytes = Int64(done * Double(model.bytes))
            state = bytes < 1_000_000
                ? "Starting the \(model.sizeLabel) download."
                : "Downloading, \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) of \(model.sizeLabel)."
        case .preparing:
            state = "Preparing it for this Mac. This happens once and takes a few minutes."
        case .failed(let message):
            action = .retry
            isError = true
            state = message
        case .notInstalled where !plan.canDownload:
            state = "Needs a Mac with Apple silicon."
        case .notInstalled where plan.deleted.contains(model.id) || !plan.isComing(model.id):
            action = .download
            state = "Not downloaded. \(model.sizeLabel)."
        case .notInstalled:
            let ahead = ModelPlan.downloadOrder.prefix { $0 != model.id }.first { other in
                let install = plan.install(other)
                return install.isDownloading || install == .preparing
                    || install == .notInstalled && !plan.deleted.contains(other)
            }
            state = ahead.map { "Downloads after \(TranscriptionModel.model($0).name)." }
                ?? "Downloads soon. \(model.sizeLabel)."
        }
        let roles = plan.roles(model.id, inUse: inUse)
        return Row(id: model.id, title: model.name, role: roleLabel(roles), state: state, fraction: fraction,
                   action: action, isError: isError)
    }
}
