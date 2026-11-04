@preconcurrency import AVFoundation
import KoeCore

/// The default input device, through AVAudioEngine's input tap.
final class MicrophoneSource: AudioSource, @unchecked Sendable {
    // The engine is touched only by start and stop, which the session controller calls on the main actor.
    private let engine = AVAudioEngine()
    private let clock = AudioClock()

    var currentTime: AudioTime { clock.currentTime }
    var level: Float { clock.level }

    func start(format: AVAudioFormat, deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
               finish: @escaping @Sendable () -> Void) throws {
        guard clock.begin(sampleRate: format.sampleRate, finish: finish) else { return }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw AudioSourceError.noMicrophone }
        guard let converter = AVAudioConverter(from: inputFormat, to: format) else { throw AudioSourceError.unconvertible }
        let clock = clock
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard !clock.isStopped, let converted = AudioConversion.convert(buffer, with: converter, to: format) else { return }
            clock.count(converted)
            deliver(converted)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        clock.end()
    }
}
