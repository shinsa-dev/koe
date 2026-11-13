@preconcurrency import AVFoundation
import KoeCore

/// Plays an audio file into a session at its own pace, as if it were spoken: `--audio-file` at launch, for trying
/// Koe and capturing it without talking. The session ends when the file does.
final class FileSource: AudioSource, @unchecked Sendable {
    private let url: URL
    private let stream = CaptureStream()
    private var playback: Task<Void, Never>?

    init(url: URL) {
        self.url = url
    }

    var currentTime: AudioTime { stream.currentTime }
    var level: Float { stream.level }

    func start(recordingTo recording: URL?) throws {
        let file = try AVAudioFile(forReading: url)
        guard let converter = AudioConversion.toCapture(from: file.processingFormat) else {
            throw AudioSourceError.unconvertible
        }
        try? stream.open(recording: recording)
        let stream = stream
        let chunk = AVAudioFrameCount(file.processingFormat.sampleRate / 10)
        playback = Task.detached {
            while !stream.isStopped,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk),
                  (try? file.read(into: buffer, frameCount: chunk)) != nil, buffer.frameLength > 0 {
                if let converted = AudioConversion.convert(buffer, with: converter, to: CaptureStream.format) {
                    stream.ingest(converted)
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            stream.stop()
        }
    }

    func attach(format: AVAudioFormat, deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
                finish: @escaping @Sendable () -> Void) {
        stream.attach(format: format, deliver: deliver, finish: finish)
    }

    func detach() { stream.detach() }
    func pause() { stream.pause() }
    func resume() { stream.resume() }
    func stop() { stream.stop() }
}
