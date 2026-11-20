import Darwin
import KoeCore
import Testing

struct HubSnapshotTests {
    /// The files in FluidVoice's repository at the pinned commit, shortened to one of each kind.
    private let repository = [
        "Decoder.mlmodelc/coremldata.bin", "Encoder.mlmodelc/weights/weight.bin", "JointDecision.mlmodelc/model.mil",
        "Preprocessor.mlmodelc/metadata.json", "parakeet_vocab.json", "parakeet_v3_vocab.json", "config.json",
        "README.md", "assets/another-voice.png", "examples/swift/Package.swift",
        "examples/swift/Sources/transcribe/main.swift",
    ]

    /// Matches as Hugging Face's client does, with `fnmatch` and no flags, so `*` crosses folders.
    private func fetched(_ snapshot: HubSnapshot) -> Set<String> {
        Set(repository.filter { file in snapshot.files.contains { fnmatch($0, file, 0) == 0 } })
    }

    @Test func fluidSpeechProIsPinnedToOneCommit() throws {
        let snapshot = try #require(ModelID.fluidSpeechPro.snapshot)
        #expect(snapshot.repository == "FluidVoice-Labs/fluid-speech-pro-coreml")
        #expect(snapshot.revision.count == 40)
        #expect(snapshot.revision.allSatisfy { $0.isHexDigit })
        #expect(snapshot.folder == "models/FluidVoice-Labs/fluid-speech-pro-coreml")
    }

    @Test func fluidSpeechProFetchesTheModelsAndVocabularyOnly() throws {
        let snapshot = try #require(ModelID.fluidSpeechPro.snapshot)
        #expect(fetched(snapshot) == [
            "Decoder.mlmodelc/coremldata.bin", "Encoder.mlmodelc/weights/weight.bin",
            "JointDecision.mlmodelc/model.mil", "Preprocessor.mlmodelc/metadata.json", "parakeet_vocab.json",
        ])
    }

    @Test func modelsFluidAudioOrWhisperKitFetchHaveNoSnapshot() {
        for id in [ModelID.parakeetV3, .parakeetV2, .whisperTurbo, .apple] {
            #expect(id.snapshot == nil)
        }
    }
}
