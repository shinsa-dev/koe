import Foundation
import KoeCore

/// `Koe --bench [count | audio files…]`: replays recorded sessions through the live window, fed 0.9 s at a time as
/// the microphone would, and checks each ends with the same words as one decode of the whole recording. It reads the
/// newest sessions on this Mac with the default model; nothing leaves it.
@MainActor
enum TailBench {
    static func run(_ arguments: [String]) async -> Int32 {
        let files = recordings(arguments)
        guard !files.isEmpty else {
            print("No recordings to replay.")
            return 1
        }
        let model = TranscriptionModel.standard
        let store = ModelStore()
        guard store.isInstalled(model.id), let transcriber = WindowedTranscriber.parakeet(model.id, store: store) else {
            print("Download \(model.name) in Koe's settings first.")
            return 1
        }
        var results: [TailScore.Result] = []
        for file in files {
            do {
                let samples = try SampleBuffer.read(file)
                let live = try await replay(samples, decoder: transcriber.decoder)
                let whole = try await transcriber.transcribe(file: file).map(\.text).joined(separator: " ")
                let result = TailScore.compare(live: live, reference: whole)
                results.append(result)
                let mark = result.isComplete ? "ok  " : "CUT "
                print("\(mark)\(file.deletingLastPathComponent().lastPathComponent)  live: …\(result.live.joined(separator: " "))"
                    + "  whole: …\(result.reference.joined(separator: " "))")
            } catch {
                print("skip \(file.path): \(error.localizedDescription)")
            }
        }
        print("Endings complete: \(TailScore.total(results))")
        return 0
    }

    /// The live transcript a session of `samples` ends with, stepped as `WindowedTranscriber` steps a session.
    static func replay(_ samples: [Float], decoder: any WindowDecoder) async throws -> String {
        try await decoder.load()
        let buffer = SampleBuffer()
        var window = RollingWindow()
        var transcript = LiveTranscript()
        let chunk = Int(0.9 * WindowedTranscriber.rate)
        var fed = 0
        while true {
            if fed < samples.count {
                buffer.append(Array(samples[fed..<min(fed + chunk, samples.count)]))
                fed += chunk
            } else {
                buffer.end()
            }
            let (updates, ended) = try await WindowedTranscriber.step(&window, buffer: buffer, decoder: decoder)
            for update in updates { transcript.apply(update) }
            if ended { return transcript.text }
        }
    }

    /// The files named, or the newest `count` (40 when not given) recorded sessions.
    private static func recordings(_ arguments: [String]) -> [URL] {
        if let first = arguments.first, Int(first) == nil {
            return arguments.map { URL(filePath: $0) }
        }
        let count = arguments.first.flatMap(Int.init) ?? 40
        let root = SessionController.defaultRoot
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return folders.sorted().reversed()
            .map { root.appending(path: $0).appending(path: "audio.caf") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .prefix(count).reversed()
    }
}
