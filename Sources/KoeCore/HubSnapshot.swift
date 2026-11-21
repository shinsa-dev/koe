import CryptoKit
import Foundation

/// A model Koe fetches from one Hugging Face repository at a pinned commit, file by file, and checks against the
/// sizes and SHA-256 hashes it was pinned with, so neither a later push there nor a bad download changes what Koe runs.
public struct HubSnapshot: Sendable, Equatable {
    public struct File: Sendable, Equatable {
        public let path: String
        public let bytes: Int64
        public let sha256: String

        public init(_ path: String, bytes: Int64, sha256: String) {
            self.path = path
            self.bytes = bytes
            self.sha256 = sha256
        }
    }

    /// A downloaded file that is missing or isn't the one pinned.
    public struct Mismatch: Error, Equatable {
        public let path: String

        public init(path: String) { self.path = path }
    }

    public let repository: String
    public let revision: String
    /// Every file to fetch: the Core ML models and their vocabulary, not the examples or images.
    public let files: [File]

    public init(repository: String, revision: String, files: [File]) {
        self.repository = repository
        self.revision = revision
        self.files = files
    }

    /// Where the snapshot lands inside the model's folder, as Hugging Face's client lays it out.
    public var folder: String { "models/\(repository)" }

    /// The patterns Hugging Face's client fetches by: each file's exact path.
    public var globs: [String] { files.map(\.path) }

    /// Throws `Mismatch` for the first file in `root` that is missing, has another size or hashes differently.
    public func verify(in root: URL) throws {
        for file in files {
            let url = root.appending(path: file.path)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
            guard size == file.bytes, try Self.sha256(of: url) == file.sha256 else {
                throw Mismatch(path: file.path)
            }
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension ModelID {
    /// FluidVoice's Core ML build of Fluid Speech Pro (CC BY 4.0). FluidAudio downloads the other Parakeet models itself.
    public var snapshot: HubSnapshot? {
        switch self {
        case .fluidSpeechPro:
            HubSnapshot(repository: "FluidVoice-Labs/fluid-speech-pro-coreml",
                        revision: "3b9d38a93d606f84011e5a0a669b7ea146375a22",
                        files: HubSnapshot.fluidSpeechProFiles)
        case .parakeetV3, .parakeetV2, .whisperTurbo, .apple:
            nil
        }
    }
}

extension HubSnapshot {
    /// The hashes Hugging Face lists for the large files at the pinned commit, and those of the small ones read from it.
    static let fluidSpeechProFiles: [File] = [
        File("Decoder.mlmodelc/analytics/coremldata.bin", bytes: 243,
             sha256: "d172cb80cbf3a2cd768952557164db1b50b9c6aef16af3653d2fd7c03d9fe8e5"),
        File("Decoder.mlmodelc/coremldata.bin", bytes: 491,
             sha256: "5059c27aa8cc44eb735247d335e18da599d15e30d67b3d2d5633679fc5806f8a"),
        File("Decoder.mlmodelc/metadata.json", bytes: 3311,
             sha256: "47ee2ad3514945b6ee3ccd4171ed3b2318e38f3b929e4398ce33b50aca606083"),
        File("Decoder.mlmodelc/model.mil", bytes: 11823,
             sha256: "9d605291dfdaef07ef88b8d3dbf0702766f1ceea5649d5d6dee4d2322d8fa678"),
        File("Decoder.mlmodelc/weights/weight.bin", bytes: 23_604_992,
             sha256: "7b3e3a4e3fbb580ae990613915f8ea2309226d85999ae37120912b8352d1df9e"),
        File("Encoder.mlmodelc/analytics/coremldata.bin", bytes: 243,
             sha256: "ac53d09c1b1f7f00fd1a07a630d57c4193089b19fe0d3b1571a3ecf91be62aa4"),
        File("Encoder.mlmodelc/coremldata.bin", bytes: 427,
             sha256: "abfbc09cc0b8aba7911e38390390f1c5850e3665862238035052e015659ebb74"),
        File("Encoder.mlmodelc/metadata.json", bytes: 2758,
             sha256: "cc74be4442be9fe7d6428aa238364d40e91d3c0ca4ce3cfa2f4fef4ad7a42cee"),
        File("Encoder.mlmodelc/model.mil", bytes: 621_903,
             sha256: "f71d68afe10e227c39d43af07c1aa1a88dd0eb2f63109a3e03711066e38a2e9d"),
        File("Encoder.mlmodelc/weights/weight.bin", bytes: 613_088_448,
             sha256: "4abdc3b4af2ff9b2843105f29677f0e674d2b08638b1ce6feac60876c235c659"),
        File("JointDecision.mlmodelc/analytics/coremldata.bin", bytes: 243,
             sha256: "3dd0d66c51f69d683c587d5c88f3256d5e1690105ecf9d8ca4b0c2b8e1c883c7"),
        File("JointDecision.mlmodelc/coremldata.bin", bytes: 462,
             sha256: "febdb37a5ad1a119539c33cf68fac1c51f80f40f82c90b6ef312033191ff4063"),
        File("JointDecision.mlmodelc/metadata.json", bytes: 2728,
             sha256: "36fa268dd3c132c7305bbe1f17b5891a00f91caf0a883782375c35a97e2f4ada"),
        File("JointDecision.mlmodelc/model.mil", bytes: 7178,
             sha256: "618bc532db01d5d80da27d0137e4b50cf2f56dde54e0686a4a1e732d74c1a55c"),
        File("JointDecision.mlmodelc/weights/weight.bin", bytes: 12_642_764,
             sha256: "f0939e8807dded497926a7c3634af698557ec8b155d804f8f40e367e97f90849"),
        File("Preprocessor.mlmodelc/analytics/coremldata.bin", bytes: 243,
             sha256: "886396da81b6b29d60d79d903bd5d1f00077a7a4323f40cd2e9214d4205d8e6b"),
        File("Preprocessor.mlmodelc/coremldata.bin", bytes: 429,
             sha256: "38f130eac9ffde8c684043d76e3eecdd3b6f9564d9efa59f7a87a34a272a4901"),
        File("Preprocessor.mlmodelc/metadata.json", bytes: 2606,
             sha256: "c25d98c19a181b7fa65ee50c34f5066f67172c22f0bf116a42b59443ee4bc37d"),
        File("Preprocessor.mlmodelc/model.mil", bytes: 11891,
             sha256: "71d4ad016334b3ad73ea7b69b6813feefe3b81f59e0b5e924f90f088cb02a7c9"),
        File("Preprocessor.mlmodelc/weights/weight.bin", bytes: 2_150_580,
             sha256: "44180071e400951080786feb46452bffc4fb26363a703655ebadb760c8ad4030"),
        File("parakeet_vocab.json", bytes: 151_122,
             sha256: "7ec60e05f1b24480736ec0eed40900f4626bce1fa9a60fd700ec7e2a59198735"),
    ]
}
