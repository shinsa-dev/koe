import AVFoundation
import Foundation
import KoeCore

/// `Koe --background --latency [--model <id>] [count | audio files…]`, run through `scripts/sandbox.sh`: plays recordings
/// into real sessions, presses the shortcut to start and to finish each one as you would, and prints how long every
/// stage of starting and finishing took (`LatencyTrace`). Each recording plays at its own pace, then silence follows
/// until the run finishes it, as a microphone would. With no files it takes your newest recordings of 30 s or less.
@MainActor
enum LatencyRun {
    static let isOn = Launch.has("--latency")
    /// The recording the next session plays instead of the microphone.
    nonisolated(unsafe) static var recording: URL?

    private static let longest: TimeInterval = 30

    /// What a session records from: the run's recording, or `--audio-file`, or the microphone.
    nonisolated static func source(playing file: URL?) -> any AudioSource {
        if let recording { return FileSource(url: recording, holdOpen: true) }
        if let file { return FileSource(url: file) }
        return MicrophoneSource()
    }

    /// Picks the model before Koe reads its settings, then runs once Koe has launched.
    static func start(_ app: AppDelegate) {
        guard Launch.isBackground else {
            print("Run it in the background: scripts/sandbox.sh --with-models --latency")
            exit(1)
        }
        var arguments = Array(CommandLine.arguments.drop { $0 != "--latency" }.dropFirst())
        if let flag = arguments.firstIndex(of: "--model") {
            let id = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : ""
            arguments.removeSubrange(flag...min(flag + 1, arguments.count - 1))
            guard ModelID(rawValue: id) != nil else {
                print("No model named \(id).")
                exit(1)
            }
            Launch.defaults.set(id, forKey: KoeSettings.Key.transcriptionModel)
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
        for line in report.lines { print(line) }
        return 0
    }

    /// One session: starts it, lets the recording play out, finishes it and waits for the copy.
    private static func session(_ app: AppDelegate, playing file: (url: URL, length: TimeInterval)) async -> LatencyTrace? {
        _ = LatencyLog.shared.takeFinished()
        recording = file.url
        app.toggleSession()
        try? await Task.sleep(for: .seconds(file.length + 0.5))
        app.toggleSession()
        for _ in 0..<300 {
            if let trace = LatencyLog.shared.takeFinished().last {
                recording = nil
                // The next session starts from rest, as yours do.
                try? await Task.sleep(for: .seconds(1))
                return trace
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        recording = nil
        return nil
    }

    /// Waits until Koe has launched and the chosen model has loaded, so no session falls back to Apple's meanwhile.
    private static func loadedRoute(_ transcriber: ActiveTranscriber) async -> TranscriberRoute? {
        let chosen = KoeSettings(values: Launch.defaults.dictionaryRepresentation()).transcriptionModel
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
