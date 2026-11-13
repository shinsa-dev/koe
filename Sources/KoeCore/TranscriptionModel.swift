import Foundation

/// The code that runs a model: FluidAudio for Parakeet, WhisperKit for Whisper, and the system's SpeechAnalyzer.
public enum TranscriptionEngine: String, Sendable {
    case parakeet, whisper, apple
}

/// Names a model in the settings and on disk.
public enum ModelID: String, CaseIterable, Sendable {
    case parakeetV3 = "parakeet-v3"
    case parakeetV2 = "parakeet-v2"
    case whisperTurbo = "whisper-large-v3-turbo"
    case apple
}

/// A speech model Koe can transcribe with. Every one runs on this Mac; the downloaded ones come from Hugging Face.
public struct TranscriptionModel: Sendable, Equatable, Identifiable {
    public let id: ModelID
    public let name: String
    public let languages: String
    public let engine: TranscriptionEngine
    /// What the download takes on disk. Zero for a model the system already has.
    public let bytes: Int64
    public let isRecommended: Bool

    public var needsDownload: Bool { bytes > 0 }

    public var sizeLabel: String {
        needsDownload ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : "Built in"
    }

    public static let parakeetV3 = TranscriptionModel(
        id: .parakeetV3, name: "Parakeet v3", languages: "25 European languages", engine: .parakeet,
        bytes: 483_000_000, isRecommended: true)
    public static let parakeetV2 = TranscriptionModel(
        id: .parakeetV2, name: "Parakeet v2", languages: "English", engine: .parakeet,
        bytes: 464_000_000, isRecommended: false)
    public static let whisperTurbo = TranscriptionModel(
        id: .whisperTurbo, name: "Whisper large-v3 turbo", languages: "99 languages", engine: .whisper,
        bytes: 650_000_000, isRecommended: false)
    public static let apple = TranscriptionModel(
        id: .apple, name: "Apple on-device", languages: "Your system language", engine: .apple,
        bytes: 0, isRecommended: false)

    /// In the order the settings list them: the recommended model first, the built-in fallback last.
    public static let catalog: [TranscriptionModel] = [.parakeetV3, .parakeetV2, .whisperTurbo, .apple]

    public static let standard = parakeetV3

    public static func model(_ id: ModelID) -> TranscriptionModel {
        catalog.first { $0.id == id } ?? standard
    }
}

/// Where a model's download stands.
public enum ModelInstall: Sendable, Equatable {
    case notInstalled
    /// `fraction` is 0 to 1. FluidAudio reports no progress, so it is measured from the bytes already on disk.
    case downloading(fraction: Double)
    case installed
    case failed(String)

    /// Bytes on disk over the bytes expected, held under 1 until the download says it is done: the folder can
    /// outgrow the estimate, and the model still compiles after its last file lands.
    public static func progress(onDisk: Int64, expected: Int64) -> ModelInstall {
        guard expected > 0 else { return .downloading(fraction: 0) }
        return .downloading(fraction: min(max(Double(onDisk) / Double(expected), 0), 0.99))
    }

    public var isInstalled: Bool { self == .installed }

    public var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}
