@preconcurrency import AVFoundation
import KoeCore
import os

/// Where a session's audio comes from. Capture starts the moment the session does: every buffer is written to the
/// session's audio file as it arrives and held until the transcriber attaches, so nothing said while the speech model
/// loads is lost, and a crash still leaves the recording on disk.
protocol AudioSource: AnyObject, Sendable {
    /// Starts capturing now, writing to `recording` as it goes. Throws only when there is nothing to capture from.
    func start(recordingTo recording: URL?) throws
    /// Hands everything captured so far to `deliver` in `format`, then each new buffer as it comes. `deliver` runs on
    /// an audio thread; `finish` runs once, when the audio ends.
    func attach(format: AVAudioFormat, deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
                finish: @escaping @Sendable () -> Void)
    /// The transcriber gave up: stop holding audio for it. The recording itself goes on.
    func detach()
    func pause()
    func resume()
    func stop()
    /// Seconds of audio recorded so far, pauses left out: the time an annotation added now is stamped with.
    var currentTime: AudioTime { get }
    /// How loud the last buffer was, 0...1, for the waveform.
    var level: Float { get }
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

/// The capture shared by every source: one format (16 kHz mono, what speech models take), the recording file,
/// the clock, and the audio held for the transcriber until it attaches. Thread safe; buffers arrive on audio threads.
final class CaptureStream: @unchecked Sendable {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1,
                                      interleaved: false)!
    private static let log = Logger(subsystem: "studio.shinsa.koe", category: "capture")

    private struct Listener {
        let converter: AVAudioConverter?
        let format: AVAudioFormat
        let deliver: @Sendable (AVAudioPCMBuffer) -> Void
        let finish: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var file: AVAudioFile?
    private var frames: AVAudioFramePosition = 0
    private var lastLevel: Float = 0
    private var paused = false
    private var stopped = false
    private var holding = true
    private var held: [AVAudioPCMBuffer] = []
    private var listener: Listener?

    func open(recording url: URL?) throws {
        guard let url else { return }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        lock.withLock { self.file = file }
    }

    var currentTime: AudioTime { lock.withLock { Double(frames) / Self.format.sampleRate } }
    var level: Float { lock.withLock { paused ? 0 : lastLevel } }
    var isStopped: Bool { lock.withLock { stopped } }

    /// Takes one buffer in `CaptureStream.format`.
    func ingest(_ buffer: AVAudioPCMBuffer) {
        let samples = buffer.floatChannelData.map { UnsafeBufferPointer(start: $0[0], count: Int(buffer.frameLength)) }
        let level = samples.map { AudioLevel.normalized(rms: AudioLevel.rms($0)) } ?? 0
        lock.withLock {
            guard !paused, !stopped else { return }
            do {
                try file?.write(from: buffer)
            } catch {
                Self.log.error("Could not write the recording: \(error.localizedDescription, privacy: .public)")
            }
            frames += AVAudioFramePosition(buffer.frameLength)
            lastLevel = level
            if let listener {
                send(buffer, to: listener)
            } else if holding {
                held.append(buffer)
            }
        }
    }

    func attach(format: AVAudioFormat, deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
                finish: @escaping @Sendable () -> Void) {
        let converter = format == Self.format ? nil : AVAudioConverter(from: Self.format, to: format)
        let listener = Listener(converter: converter, format: format, deliver: deliver, finish: finish)
        let ended = lock.withLock {
            for buffer in held { send(buffer, to: listener) }
            held.removeAll()
            if !stopped { self.listener = listener }
            return stopped
        }
        if ended { finish() }
    }

    func detach() {
        lock.withLock {
            holding = false
            held.removeAll()
            listener = nil
        }
    }

    func pause() { lock.withLock { paused = true } }

    func resume() { lock.withLock { paused = false } }

    /// Closes the recording and ends the transcriber's audio. Runs once.
    func stop() {
        let finish = lock.withLock { () -> (@Sendable () -> Void)? in
            guard !stopped else { return nil }
            stopped = true
            file = nil
            defer { listener = nil }
            return listener?.finish
        }
        finish?()
    }

    private func send(_ buffer: AVAudioPCMBuffer, to listener: Listener) {
        if let converter = listener.converter {
            if let converted = AudioConversion.convert(buffer, with: converter, to: listener.format) {
                listener.deliver(converted)
            }
        } else {
            listener.deliver(buffer)
        }
    }
}

enum AudioConversion {
    /// A converter into Koe's capture format that mixes every channel down rather than keeping only the first.
    static func toCapture(from format: AVAudioFormat) -> AVAudioConverter? {
        let converter = AVAudioConverter(from: format, to: CaptureStream.format)
        converter?.downmix = true
        return converter
    }

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
