import AVFoundation
import Foundation
import KoeCore

/// `Koe --background --latency [--tail <s>] [count | audio files…]`, run through `scripts/sandbox.sh`: plays recordings
/// into real sessions, presses the shortcut to start and to finish each one as you would, and prints how long every
/// stage of starting and finishing took (`LatencyTrace`). Each recording plays at its own pace, then silence follows
/// until the run finishes it, as a microphone would. With no files it takes your newest recordings of 30 s or less.
/// It exits with 2 when any start or finish took more than 50 ms.
@MainActor
enum LatencyRun {
    static let isOn = Launch.has("--latency")
    /// The recording the next session plays instead of the microphone.
    nonisolated(unsafe) static var recording: URL?

    private static let longest: TimeInterval = 30
    /// Seconds after a recording's end that the run finishes it: `--tail -1.5` stops mid-sentence, as you might.
    private static var tail: TimeInterval = 0.5

    /// What a session records from: the run's recording, or `--audio-file`, or the microphone.
    nonisolated static func source(playing file: URL?) -> any AudioSource {
        if let recording { return FileSource(url: recording, holdOpen: true) }
        if let file { return FileSource(url: file) }
        return MicrophoneSource()
    }

    /// Runs once Koe has launched.
    static func start(_ app: AppDelegate) {
        guard Launch.isBackground else {
            print("Run it in the background: scripts/sandbox.sh --with-models --latency")
            exit(1)
        }
        var arguments = Array(CommandLine.arguments.drop { $0 != "--latency" }.dropFirst())
        if let flag = arguments.firstIndex(of: "--tail") {
            let value = arguments.indices.contains(flag + 1) ? Double(arguments[flag + 1]) : nil
            arguments.removeSubrange(flag...min(flag + 1, arguments.count - 1))
            guard let value else {
                print("--tail takes seconds, such as 0.5 or -1.5.")
                exit(1)
            }
            tail = value
        }
        let files = recordings(arguments)
        Task { @MainActor in exit(await run(app, files: files)) }
    }

    private static func run(_ app: AppDelegate, files: [(url: URL, length: TimeInterval)]) async -> Int32 {
        guard !files.isEmpty else {
            print("No recordings of \(Int(longest)) s or less to play.")
            return 1
        }
        guard let route = await loadedRoute(app.transcriber) else {
            print("The model didn't load in time.")
            return 1
        }
        let model = TranscriptionModel.model(route.model)
        print("\(model.name), \(files.count) recordings")
        var traces: [LatencyTrace] = []
        for file in files {
            if let trace = await session(app, playing: file) {
                traces.append(trace)
                print("\(file.url.deletingLastPathComponent().lastPathComponent)  \(trace.summary)")
            } else {
                print("\(file.url.deletingLastPathComponent().lastPathComponent)  wasn't copied")
            }
        }
        let report = LatencyReport(traces)
        for line in report.lines + report.verdict(model: model.name) { print(line) }
        return report.meetsBudget ? 0 : 2
    }

    /// One session: starts it, lets the recording play out, finishes it and waits for the copy.
    private static func session(_ app: AppDelegate, playing file: (url: URL, length: TimeInterval)) async -> LatencyTrace? {
        _ = LatencyLog.shared.takeFinished()
        recording = file.url
        app.toggleSession()
        try? await Task.sleep(for: .seconds(max(1, file.length + tail)))
        app.toggleSession()
        for _ in 0..<300 {
            if let trace = LatencyLog.shared.takeFinished().last {
                recording = nil
                // The next session starts from rest, as yours do; meanwhile the last pass may refine the copy.
                try? await Task.sleep(for: .seconds(1))
                return LatencyLog.shared.lastCopied ?? trace
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        recording = nil
        return nil
    }

    /// Waits until Koe has launched and the model it streams with (`ModelPlan`) has loaded, so no session falls back
    /// to Apple's meanwhile.
    private static func loadedRoute(_ transcriber: ActiveTranscriber) async -> TranscriberRoute? {
        let deleted = KoeSettings(values: Launch.defaults.dictionaryRepresentation()).deletedModels
        let chosen = ModelStore().plan(deleted: deleted).liveCandidate
        for _ in 0..<600 {
            let route = transcriber.currentRoute
            if route.chosen == chosen, route.fallback == nil { return route }
            if case .failedToLoad = route.fallback { return nil }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    /// The recordings named, or the newest `count` (5) of your own of at most 30 s. Read from your real home folder,
    /// as the sandbox has none.
    private static func recordings(_ arguments: [String]) -> [(url: URL, length: TimeInterval)] {
        if let first = arguments.first, Int(first) == nil {
            return arguments.map { URL(filePath: $0) }.compactMap { url in length(url).map { (url, $0) } }
        }
        let count = arguments.first.flatMap(Int.init) ?? 5
        guard let home = getpwuid(getuid())?.pointee.pw_dir.map({ String(cString: $0) }) else { return [] }
        let root = URL(filePath: home).appending(path: "Library/Application Support/Koe/Sessions")
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return folders.sorted().reversed().lazy
            .map { root.appending(path: $0).appending(path: "audio.caf") }
            .compactMap { url in length(url).map { (url, $0) } }
            .filter { $0.1 <= longest && $0.1 >= 2 }
            .prefix(count).reversed()
    }

    private static func length(_ url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
