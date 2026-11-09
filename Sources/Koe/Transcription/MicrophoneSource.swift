@preconcurrency import AVFoundation
import KoeCore
import os

/// The default input device, through AVAudioEngine's input tap. When the device changes mid-session (AirPods
/// connect, a mic is unplugged) the engine stops; the source picks up the new device and records on.
final class MicrophoneSource: AudioSource, @unchecked Sendable {
    // Starting the engine takes about half a second, so the engine lives on its own queue: the session and the pill
    // start the moment you ask, and the audio follows. Every engine call goes through `queue`, in order.
    private let queue = DispatchQueue(label: "studio.shinsa.koe.microphone", qos: .userInteractive)
    private let engine = AVAudioEngine()
    private let stream = CaptureStream()
    private var observer: NSObjectProtocol?
    private var running = false
    private static let log = Logger(subsystem: "studio.shinsa.koe", category: "microphone")

    var currentTime: AudioTime { stream.currentTime }
    var level: Float { stream.level }

    func start(recordingTo recording: URL?) throws {
        try stream.open(recording: recording)
        queue.async { [self] in
            guard !stream.isStopped else { return }
            do {
                try startEngine()
            } catch {
                Self.log.error("Could not open the microphone: \(error.localizedDescription, privacy: .public)")
                stream.stop()
                return
            }
            observer = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                queue.async { self.deviceChanged() }
            }
        }
    }

    private func startEngine() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw AudioSourceError.noMicrophone }
        guard let converter = AudioConversion.toCapture(from: inputFormat) else { throw AudioSourceError.unconvertible }
        let stream = stream
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let converted = AudioConversion.convert(buffer, with: converter, to: CaptureStream.format) else { return }
            stream.ingest(converted)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        running = true
    }

    private func stopEngine() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }

    private func deviceChanged() {
        guard !stream.isStopped else { return }
        Self.log.info("Input device changed; restarting the microphone")
        stopEngine()
        do {
            try startEngine()
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
        queue.async { [self] in if running { engine.pause() } }
    }

    func resume() {
        stream.resume()
        queue.async { [self] in
            guard running else { return }
            do {
                try engine.start()
            } catch {
                Self.log.error("Could not resume the microphone: \(error.localizedDescription, privacy: .public)")
                deviceChanged()
            }
        }
    }

    /// Ends the recording at once; the engine winds down on its queue.
    func stop() {
        stream.stop()
        queue.async { [self] in
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            stopEngine()
        }
    }
}
