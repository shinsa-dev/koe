import Foundation

/// What Koe uses a model for.
public enum ModelRole: Sendable, Hashable {
    /// It transcribes while you talk.
    case live
    /// It reads the recording again after the copy (`RefinePlan`).
    case refine
}

/// Koe's own choice of models, from what is on this Mac: which one streams, which one downloads next, and what each is
/// for. Nobody picks a model; you can only delete a download, and a model you deleted stays deleted until you ask
/// for it again.
public struct ModelPlan: Sendable, Equatable {
    /// The order Koe downloads in: the live model first, then the one only the refine uses.
    public static let downloadOrder: [ModelID] = [.fluidSpeechPro, .whisperTurbo]

    public let installs: [ModelID: ModelInstall]
    public let deleted: Set<ModelID>
    /// Whether this Mac runs the downloaded models at all (Apple silicon).
    public let canDownload: Bool

    public init(installs: [ModelID: ModelInstall], deleted: Set<ModelID> = [], canDownload: Bool) {
        self.installs = installs
        self.deleted = deleted
        self.canDownload = canDownload
    }

    public func install(_ id: ModelID) -> ModelInstall {
        TranscriptionModel.model(id).needsDownload ? installs[id] ?? .notInstalled : .installed
    }

    /// Will be on this Mac without you asking: installed, or due in the download order.
    public func isComing(_ id: ModelID) -> Bool {
        install(id).isInstalled || canDownload && Self.downloadOrder.contains(id) && !deleted.contains(id)
    }

    /// The model sessions stream with once it has loaded: the first of the Parakeet family on this Mac (Fluid Speech
    /// Pro, else a Parakeet v3 or v2 left from before), else Fluid Speech Pro on its way. Until it can run,
    /// `TranscriberRoute` hands sessions to Apple's model.
    public var liveCandidate: ModelID {
        guard canDownload else { return .apple }
        if let installed = ModelID.parakeetFamily.first(where: { install($0).isInstalled }) { return installed }
        return isComing(.fluidSpeechPro) ? .fluidSpeechPro : .apple
    }

    /// The download to start now, or nil while one runs or none is due. One that failed waits for Try again or the
    /// next launch, so the next in line still comes.
    public var nextDownload: ModelID? {
        guard canDownload, !installs.values.contains(where: { $0.isDownloading || $0 == .preparing }) else {
            return nil
        }
        return Self.downloadOrder.first { install($0) == .notInstalled && !deleted.contains($0) }
    }

    /// What Koe uses `id` for, or will once it is in. `inUse` is the model that streams now.
    public func roles(_ id: ModelID, inUse: ModelID) -> Set<ModelRole> {
        var roles = Set<ModelRole>()
        let streams = id == liveCandidate || id == .fluidSpeechPro && isComing(.fluidSpeechPro)
        if id == inUse || streams && id != .apple { roles.insert(.live) }
        let coming = Set(TranscriptionModel.catalog.map(\.id).filter(isComing))
        if RefinePlan.readers(installed: coming).contains(id) { roles.insert(.refine) }
        return roles
    }
}
