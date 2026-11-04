import AVFoundation
import KoeCore

/// Reads a recorded clip: when each of its frames appears, and any one frame as an image.
enum ClipMovie {
    enum Failure: LocalizedError {
        case noVideo

        var errorDescription: String? { "Koe couldn't read the clip." }
    }

    struct Info: Sendable {
        let frames: ClipFrames
        /// The picture's size in pixels.
        let size: CGSize
    }

    /// Walks the clip's samples without decoding them, so even a long clip reads in a moment.
    static func read(_ url: URL) async throws -> Info {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.noVideo }
        let duration = try await asset.load(.duration).seconds
        let size = try await track.load(.naturalSize)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Failure.noVideo }
        var times: [AudioTime] = []
        while let sample = output.copyNextSampleBuffer() {
            guard CMSampleBufferGetNumSamples(sample) > 0 else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if time.isFinite { times.append(time) }
        }
        if reader.status == .failed { throw reader.error ?? Failure.noVideo }
        guard !times.isEmpty else { throw Failure.noVideo }
        return Info(frames: ClipFrames(times: times, duration: duration.isFinite ? duration : 0), size: size)
    }

    /// Exactly the frame shown at `time`, at full size, or no larger than `maxSide` points for a thumbnail.
    static func image(at time: AudioTime, of url: URL, maxSide: CGFloat? = nil) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        if let maxSide { generator.maximumSize = CGSize(width: maxSide, height: maxSide) }
        return try await generator.image(at: CMTime(seconds: time, preferredTimescale: 6000)).image
    }
}
