@preconcurrency import AVFoundation
import KoeCore
import os

/// The default input device, through AVAudioEngine's input tap. When the device changes mid-session (AirPods
/// connect, a mic is unplugged) the engine stops; the source picks up the new device and records on.
final class MicrophoneSource: AudioSource, @unchecked Sendable {
    // The engine is touched only on the main thread: start, pause, resume and stop come from the session controller,
    // and the configuration-change observer runs on the main queue.
    private let engine = AVAudioEngine()
    private let stream = CaptureStream()
    private var observer: NSObjectProtocol?
    private static let log = Logger(subsystem: "studio.shinsa.koe", category: "microphone")

    var currentTime: AudioTime { stream.currentTime }
    var level: Float { stream.level }

    func start(recordingTo recording: URL?) throws {
        try installTap()
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw error
        }
        try? stream.open(recording: recording)
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.deviceChanged() }
    }

    private func installTap() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw AudioSourceError.noMicrophone }
        guard let converter = AudioConversion.toCapture(from: inputFormat) else { throw AudioSourceError.unconvertible }
        let stream = stream
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let converted = AudioConversion.convert(buffer, with: converter, to: CaptureStream.format) else { return }
            stream.ingest(converted)
        }
    }

    private func deviceChanged() {
        guard !stream.isStopped else { return }
        Self.log.info("Input device changed; restarting the microphone")
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        do {
            try installTap()
            engine.prepare()
            try engine.start()
        } catch {
            Self.log.error("Could not restart the microphone: \(error.localizedDescription, privacy: .public)")
        }
    }

    func attach(format: AVAudioFormat, deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
                finish: @escaping @Sendable () -> Void) {
        stream.attach(format: format, deliver: deliver, finish: finish)
    }

    func detach() { stream.detach() }

    func pause() {
        stream.pause()
        engine.pause()
    }

    func resume() {
        stream.resume()
        do {
            try engine.start()
        } catch {
            Self.log.error("Could not resume the microphone: \(error.localizedDescription, privacy: .public)")
            deviceChanged()
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        stream.stop()
    }
}
