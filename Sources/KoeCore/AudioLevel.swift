import Foundation

/// How loud the microphone is, for the pill's waveform.
public enum AudioLevel {
    /// The quietest level the waveform shows; anything under it draws as silence.
    public static let floor: Float = -50

    /// The root mean square of samples in -1...1.
    public static func rms(_ samples: some Collection<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// An RMS amplitude mapped to 0...1 on a decibel scale from `floor` to 0 dB, which tracks loudness as heard.
    public static func normalized(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels - floor) / -floor))
    }
}

/// The last few levels, oldest first, as the waveform draws them from left to right.
public struct LevelHistory: Sendable, Equatable {
    public private(set) var bars: [Float]

    public init(count: Int) {
        bars = Array(repeating: 0, count: max(1, count))
    }

    public mutating func push(_ level: Float) {
        bars.removeFirst()
        bars.append(min(1, max(0, level)))
    }
}
