/// A model Koe fetches from one Hugging Face repository at a pinned commit, so a later push there can't change what
/// Koe runs without a release.
public struct HubSnapshot: Sendable, Equatable {
    public let repository: String
    public let revision: String
    /// Glob patterns for the files to fetch: the Core ML models and their vocabulary, not the examples or images.
    public let files: [String]

    /// Where the snapshot lands inside the model's folder, as Hugging Face's client lays it out.
    public var folder: String { "models/\(repository)" }
}

extension ModelID {
    /// FluidVoice's Core ML build of Fluid Speech Pro (CC BY 4.0). FluidAudio downloads the other Parakeet models itself.
    public var snapshot: HubSnapshot? {
        switch self {
        case .fluidSpeechPro:
            HubSnapshot(repository: "FluidVoice-Labs/fluid-speech-pro-coreml",
                        revision: "3b9d38a93d606f84011e5a0a669b7ea146375a22",
                        files: ["*.mlmodelc/*", "parakeet_vocab.json"])
        case .parakeetV3, .parakeetV2, .whisperTurbo, .apple:
            nil
        }
    }
}
