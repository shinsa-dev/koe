@preconcurrency import AVFoundation
import KoeCore
import Synchronization

/// Where a session's audio comes from. A source converts what it hears into the format the transcriber asks for,
/// and counts what it has delivered, which is the session's clock.
protocol AudioSource: AnyObject, Sendable {
    /// Starts delivering audio in `format`. `deliver` runs on an audio thread; `finish` runs once, when the audio ends.
    /// A source stopped before it starts finishes at once.
    func start(format: AVAudioFormat, deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
               finish: @escaping @Sendable () -> Void) throws
    func stop()
    /// Seconds of audio delivered so far: the time an annotation added now is stamped with.
    var currentTime: AudioTime { get }
}

enum AudioSourceError: LocalizedError {
    case noMicrophone
    case unconvertible

    var errorDescription: String? {
        switch self {
        case .noMicrophone: "Koe can't find a microphone. Plug one in or pick one in System Settings."
        case .unconvertible: "Koe can't read audio in this format."
        }
    }
}

/// The delivered-frame count and the finish callback, shared between the caller and the audio thread.
final class AudioClock: Sendable {
    private struct State {
        var frames: AVAudioFramePosition = 0
        var sampleRate: Double = 0
        var finish: (@Sendable () -> Void)?
        var stopped = false
    }

    private let state = Mutex(State())

    var currentTime: AudioTime {
        state.withLock { $0.sampleRate > 0 ? Double($0.frames) / $0.sampleRate : 0 }
    }

    /// Records the finish callback, or returns false when the source was already stopped and has finished.
    func begin(sampleRate: Double, finish: @escaping @Sendable () -> Void) -> Bool {
        let stopped = state.withLock { state in
            state.sampleRate = sampleRate
            if !state.stopped { state.finish = finish }
            return state.stopped
        }
        if stopped { finish() }
        return !stopped
    }

    func count(_ frames: AVAudioFrameCount) {
        state.withLock { $0.frames += AVAudioFramePosition(frames) }
    }

    var isStopped: Bool { state.withLock(\.stopped) }

    /// Marks the source stopped and runs the finish callback once.
    func end() {
        let finish = state.withLock { state -> (@Sendable () -> Void)? in
            state.stopped = true
            defer { state.finish = nil }
            return state.finish
        }
        finish?()
    }
}

enum AudioConversion {
    /// Converts one buffer. The converter keeps its own state between calls, so one converter serves a whole stream.
    static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        // The converter asks for input synchronously, inside convert(to:), so this flag never crosses threads.
        nonisolated(unsafe) var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            inputStatus.pointee = supplied ? .noDataNow : .haveData
            defer { supplied = true }
            return supplied ? nil : buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }
}
