import AppKit
import AVFoundation
import KoeCore
import os
@preconcurrency import ScreenCaptureKit

/// Records one region of one screen to a movie, with the pointer and without Koe's own windows.
@MainActor
final class ClipRecorder {
    enum Failure: LocalizedError {
        case noDisplay

        var errorDescription: String? { "Koe couldn't find the screen to record." }
    }

    private let stream: SCStream
    private let output: SCRecordingOutput
    private let events: RecordingEvents

    private init(stream: SCStream, output: SCRecordingOutput, events: RecordingEvents) {
        self.stream = stream
        self.output = output
        self.events = events
    }

    /// Starts recording `region` (in the screen's own space) and returns once the first frame is being written.
    static func start(region: CGRect, on screen: NSScreen, to url: URL) async throws -> ClipRecorder {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == number }) else { throw Failure.noDisplay }
        let koe = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: koe, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.sourceRect = region
        let pixels = ScreenGeometry.recordingPixels(of: region.size, scale: screen.backingScaleFactor)
        config.width = pixels.width
        config.height = pixels.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        config.capturesAudio = false
        config.queueDepth = 8

        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = url
        recording.outputFileType = .mov
        recording.videoCodecType = .h264

        let events = RecordingEvents()
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let output = SCRecordingOutput(configuration: recording, delegate: events)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()
        do {
            try await events.started.wait()
        } catch {
            try? await stream.stopCapture()
            throw error
        }
        return ClipRecorder(stream: stream, output: output, events: events)
    }

    /// Stops and returns once the movie is complete on disk.
    func stop() async throws {
        try await stream.stopCapture()
        try await events.finished.wait()
    }
}

/// SCRecordingOutput's delegate calls, as two signals the recorder can await.
private final class RecordingEvents: NSObject, SCRecordingOutputDelegate, Sendable {
    let started = Signal()
    let finished = Signal()

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        started.fire(.success(()))
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        started.fire(.failure(error))
        finished.fire(.failure(error))
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finished.fire(.success(()))
    }
}

/// Fires once; a wait before or after the fire gets the same result.
final class Signal: Sendable {
    private struct State {
        var result: Result<Void, any Error>?
        var waiters: [CheckedContinuation<Void, any Error>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func fire(_ result: Result<Void, any Error>) {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, any Error>] in
            guard state.result == nil else { return [] }
            state.result = result
            defer { state.waiters = [] }
            return state.waiters
        }
        waiters.forEach { $0.resume(with: result) }
    }

    func wait() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let result = state.withLock { state -> Result<Void, any Error>? in
                if state.result == nil { state.waiters.append(continuation) }
                return state.result
            }
            if let result { continuation.resume(with: result) }
        }
    }
}
