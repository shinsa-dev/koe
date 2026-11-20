import CryptoKit
import Darwin
import Foundation
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

    /// Matches as Hugging Face's client does, with `fnmatch` and no flags.
    private func fetched(_ snapshot: HubSnapshot) -> Set<String> {
        Set(repository.filter { file in snapshot.globs.contains { fnmatch($0, file, 0) == 0 } })
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

    @Test func fluidSpeechProPinsAHashForEveryFileOfItsFourModels() throws {
        let snapshot = try #require(ModelID.fluidSpeechPro.snapshot)
        let paths = Set(snapshot.files.map(\.path))
        #expect(paths.count == snapshot.files.count)
        for model in ["Preprocessor", "Encoder", "Decoder", "JointDecision"] {
            for file in ["coremldata.bin", "model.mil", "metadata.json", "weights/weight.bin"] {
                #expect(paths.contains("\(model).mlmodelc/\(file)"))
            }
        }
        #expect(snapshot.files.allSatisfy { $0.sha256.count == 64 && $0.sha256.allSatisfy(\.isHexDigit) })
        let total = snapshot.files.reduce(0) { $0 + $1.bytes }
        #expect(abs(total - TranscriptionModel.fluidSpeechPro.bytes) < 1_000_000)
    }

    @Test func modelsFluidAudioOrWhisperKitFetchHaveNoSnapshot() {
        for id in [ModelID.parakeetV3, .parakeetV2, .whisperTurbo, .apple] {
            #expect(id.snapshot == nil)
        }
    }

    // MARK: - Verifying a download

    private func downloaded(_ contents: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "hub-\(UUID().uuidString)")
        for (path, text) in contents {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        return root
    }

    private func pinned(_ contents: [String: String]) -> HubSnapshot {
        let files = contents.map { path, text in
            HubSnapshot.File(path, bytes: Int64(text.utf8.count),
                             sha256: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined())
        }
        return HubSnapshot(repository: "a/b", revision: String(repeating: "0", count: 40), files: files)
    }

    private let model = ["Encoder.mlmodelc/weights/weight.bin": "weights", "vocab.json": "{}"]

    @Test func aDownloadWithThePinnedFilesPasses() throws {
        let root = try downloaded(model)
        defer { try? FileManager.default.removeItem(at: root) }
        try pinned(model).verify(in: root)
    }

    @Test func aChangedFileOfTheSameSizeFails() throws {
        let root = try downloaded(model.merging(["Encoder.mlmodelc/weights/weight.bin": "WEIGHTS"]) { $1 })
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: HubSnapshot.Mismatch(path: "Encoder.mlmodelc/weights/weight.bin")) {
            try pinned(model).verify(in: root)
        }
    }

    @Test func aMissingOrCutShortFileFails() throws {
        let missing = try downloaded(["vocab.json": "{}"])
        let short = try downloaded(model.merging(["vocab.json": "{"]) { $1 })
        defer { [missing, short].forEach { try? FileManager.default.removeItem(at: $0) } }
        #expect(throws: HubSnapshot.Mismatch(path: "Encoder.mlmodelc/weights/weight.bin")) {
            try pinned(model).verify(in: missing)
        }
        #expect(throws: HubSnapshot.Mismatch(path: "vocab.json")) { try pinned(model).verify(in: short) }
    }
}
