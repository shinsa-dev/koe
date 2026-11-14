import Foundation

/// How loud a session was over time: the peak level (0...1, as `AudioLevel.normalized` maps it) of each 50 ms
/// stretch. The cleanup reads it to tell words said aloud from words a model heard in silence.
public struct LevelTrack: Sendable, Equatable {
    public static let step: AudioTime = 0.05

    public private(set) var peaks: [Float] = []

    public init(peaks: [Float] = []) {
        self.peaks = peaks
    }

    /// Adds a level heard at `time`, in session seconds.
    public mutating func record(_ level: Float, at time: AudioTime) {
        guard time >= 0 else { return }
        let index = Int(time / Self.step)
        if index >= peaks.count {
            peaks.append(contentsOf: repeatElement(0, count: index - peaks.count + 1))
        }
        peaks[index] = max(peaks[index], min(1, max(0, level)))
    }

    /// Adds samples that start at `time`, a 50 ms stretch at a time.
    public mutating func record(samples: [Float], rate: Double, at time: AudioTime) {
        let chunk = max(1, Int(rate * Self.step))
        var offset = 0
        while offset < samples.count {
            let slice = samples[offset..<min(samples.count, offset + chunk)]
            record(AudioLevel.normalized(rms: AudioLevel.rms(slice)), at: time + Double(offset) / rate)
            offset += chunk
        }
    }

    public var duration: AudioTime { Double(peaks.count) * Self.step }

    /// The session's background: the level most of its quiet stretches stay under.
    public var noiseFloor: Float {
        guard !peaks.isEmpty else { return 0 }
        let sorted = peaks.sorted()
        return sorted[Int(Double(sorted.count - 1) * Self.floorPercentile)]
    }

    /// The loudest stretch between `start` and `end`, or nil when the track doesn't reach that far.
    public func peak(from start: AudioTime, to end: AudioTime) -> Float? {
        let first = max(0, Int(start / Self.step))
        let last = max(first, Int(end / Self.step))
        guard first < peaks.count, last < peaks.count else { return nil }
        return peaks[first...last].max()
    }

    private static let floorPercentile = 0.1
}
