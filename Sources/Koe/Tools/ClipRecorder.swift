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
    private let writer: ClipWriter

    private init(stream: SCStream, writer: ClipWriter) {
        self.stream = stream
        self.writer = writer
    }

    /// Starts recording `region` (in the screen's own space) and returns once the first frame is being written.
    static func start(region: CGRect, on screen: NSScreen, to url: URL) async throws -> ClipRecorder {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == number }) else { throw Failure.noDisplay }
        let koe = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: koe, exceptingWindows: [])

        let rate = ClipQuality.frameRate(ofScreen: screen.maximumFramesPerSecond)
        let config = SCStreamConfiguration()
        config.sourceRect = region
        let pixels = ScreenGeometry.recordingPixels(of: region.size, scale: screen.backingScaleFactor)
        config.width = pixels.width
        config.height = pixels.height
        config.captureResolution = .best
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(rate))
        config.showsCursor = true
        config.capturesAudio = false
        config.queueDepth = 8

        let writer = try ClipWriter(url: url, width: pixels.width, height: pixels.height, frameRate: rate)
        let stream = SCStream(filter: filter, configuration: config, delegate: writer)
        try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.queue)
        try await stream.startCapture()
        do {
            try await writer.started.wait()
        } catch {
            try? await stream.stopCapture()
            throw error
        }
        return ClipRecorder(stream: stream, writer: writer)
    }

    /// Stops and returns once the movie is complete on disk.
    func stop() async throws {
        try? await stream.stopCapture()
        try await writer.finish()
    }
}

/// Encodes the stream's frames itself, since the system's own recording output picks a bit rate too low for
/// stepping through a clip frame by frame. Everything but `started` is touched on `queue` alone.
private final class ClipWriter: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    enum Failure: LocalizedError {
        case nothingRecorded

        var errorDescription: String? { "Koe couldn't record the clip." }
    }

    let started = Signal()
    let queue = DispatchQueue(label: "studio.shinsa.koe.clip", qos: .userInitiated)
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var begun = false

    init(url: URL, width: Int, height: Int, frameRate: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let codec: AVVideoCodecType = ClipQuality.fitsH264(width: width, height: height) ? .h264 : .hevc
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: ClipQuality.bitRate(width: width, height: height, frameRate: frameRate),
                AVVideoExpectedSourceFrameRateKey: frameRate,
                // A key frame each second keeps stepping to an exact frame quick.
                AVVideoMaxKeyFrameIntervalKey: frameRate
            ] as [String: Any]
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sample.isValid, Self.isComplete(sample) else { return }
        if !begun {
            guard writer.startWriting() else {
                started.fire(.failure(writer.error ?? Failure.nothingRecorded))
                return
            }
            writer.startSession(atSourceTime: sample.presentationTimeStamp)
            begun = true
            started.fire(.success(()))
        }
        if input.isReadyForMoreMediaData { input.append(sample) }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        started.fire(.failure(error))
    }

    func finish() async throws {
        let failure: (any Error)? = await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard begun, writer.status == .writing else {
                    continuation.resume(returning: writer.error ?? Failure.nothingRecorded)
                    return
                }
                input.markAsFinished()
                writer.finishWriting { [self] in
                    let done = writer.status == .completed
                    continuation.resume(returning: done ? nil : writer.error ?? Failure.nothingRecorded)
                }
            }
        }
        if let failure { throw failure }
    }

    /// The stream also sends idle and blank buffers; only a complete frame has a picture.
    private static func isComplete(_ sample: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int else { return false }
        return SCFrameStatus(rawValue: raw) == .complete
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
