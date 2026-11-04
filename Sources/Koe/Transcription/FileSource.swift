@preconcurrency import AVFoundation
import KoeCore

/// Plays an audio file into a session at its own pace, as if it were spoken: `--audio-file` at launch, for trying
/// Koe and capturing it without talking.
final class FileSource: AudioSource, @unchecked Sendable {
    private let url: URL
    private let clock = AudioClock()
    private var playback: Task<Void, Never>?

    init(url: URL) {
        self.url = url
    }

    var currentTime: AudioTime { clock.currentTime }
    var level: Float { clock.level }

    func start(format: AVAudioFormat, deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
               finish: @escaping @Sendable () -> Void) throws {
        guard clock.begin(sampleRate: format.sampleRate, finish: finish) else { return }
        let file = try AVAudioFile(forReading: url)
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else { throw AudioSourceError.unconvertible }
        let clock = clock
        let chunk = AVAudioFrameCount(file.processingFormat.sampleRate / 10)
        playback = Task.detached {
            while !clock.isStopped,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk),
                  (try? file.read(into: buffer, frameCount: chunk)) != nil, buffer.frameLength > 0 {
                if let converted = AudioConversion.convert(buffer, with: converter, to: format) {
                    clock.count(converted)
                    deliver(converted)
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            clock.end()
        }
    }

    func stop() {
        clock.end()
    }
}
