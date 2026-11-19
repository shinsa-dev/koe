@preconcurrency import AVFoundation
import Foundation
import KoeCore

/// `InputGain` for every reader of audio: the live capture, and anything that reads a recording again (the refine,
/// recovery, the benches). A recording stays as the microphone gave it, so each reader gains it the same way the
/// session did; `InputGain` gives the same samples whatever the buffer sizes, so a refine hears what the session heard.
enum RecordingGain {
    static let isOn = InputGain.isOn(arguments: CommandLine.arguments)

    /// A whole recording's samples (16 kHz mono) as the models hear them.
    static func apply(_ samples: [Float]) -> [Float] {
        guard isOn else { return samples }
        var gain = InputGain(rate: WindowedTranscriber.rate)
        return gain.apply(samples)
    }

    /// For a model that reads files itself (Apple's): a gained copy of `file` in the temporary folder, which the caller
    /// removes, or `file` itself with the gain off.
    static func copy(of file: URL) throws -> URL {
        guard isOn else { return file }
        let samples = apply(try SampleBuffer.read(file))
        let format = CaptureStream.format
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count))),
              let channel = buffer.floatChannelData?[0] else { throw AudioSourceError.unconvertible }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        let copy = FileManager.default.temporaryDirectory.appending(path: "koe-gained-\(UUID().uuidString).caf")
        let output = try AVAudioFile(forWriting: copy, settings: format.settings,
                                     commonFormat: .pcmFormatFloat32, interleaved: false)
        try output.write(from: buffer)
        return copy
    }
}
