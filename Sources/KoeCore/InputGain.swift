import Foundation

/// Raises quiet speech toward a steady level before the waveform and the speech models see it.
///
/// It measures the input in 10 ms blocks. A block counts as speech when it stands well above the room's noise floor;
/// only speech moves the gain, so a pause never winds it up. The gain only ever boosts (never past `maxGain`), and
/// after a short hangover in a pause it eases back to none, so the room between words stays as quiet as it was. Each
/// block's gain is decided from the blocks before it and ramped across the block, so the output is the same however
/// the input is split into buffers. A soft limiter keeps every sample under 0.98 of full scale.
public struct InputGain: Sendable {
    /// The speech level the gain aims for, in dBFS (RMS of a 10 ms block).
    public var target: Float
    /// The most the gain ever adds, in dB.
    public var maxGain: Float
    /// How far above the noise floor a block must be to count as speech, in dB.
    public var speechMargin: Float

    /// The gain applied to the last sample, in dB.
    public var gainDecibels: Float { 20 * log10(gain) }

    private let blockSize: Int
    private let blockSeconds: Float
    private var blockSum: Float = 0
    private var blockCount = 0
    private var gain: Float = 1
    private var step: Float = 0
    private var heading: Float = 1
    private var floor: Float?
    private var speech: Float?
    private var sinceSpeech: Float = .infinity

    // Speech under this is never taken for speech, whatever the floor.
    private static let quietest: Float = -55
    // A first block louder than this is taken as speech over a quiet room rather than as the room itself.
    private static let loudestFloor: Float = -45
    private static let floorRise: Float = 6 // dB per second
    private static let louderSeconds: Float = 0.2
    private static let softerSeconds: Float = 2
    private static let hangoverSeconds: Float = 0.3
    private static let releaseSeconds: Float = 0.15
    private static let knee: Float = 0.5
    private static let ceiling: Float = 0.98

    public init(rate: Double = 16000, target: Float = -18, maxGain: Float = 18, speechMargin: Float = 10) {
        self.target = target
        self.maxGain = maxGain
        self.speechMargin = speechMargin
        blockSize = max(1, Int(rate / 100))
        blockSeconds = Float(blockSize) / Float(rate)
    }

    /// Gains `samples` in place.
    public mutating func apply(_ samples: UnsafeMutableBufferPointer<Float>) {
        for index in samples.indices {
            let sample = samples[index]
            blockSum += sample * sample
            blockCount += 1
            samples[index] = Self.limit(sample * gain)
            gain += step
            if blockCount == blockSize { endBlock() }
        }
    }

    /// Gains `samples` and returns them.
    public mutating func apply(_ samples: [Float]) -> [Float] {
        var output = samples
        output.withUnsafeMutableBufferPointer { apply($0) }
        return output
    }

    private mutating func endBlock() {
        let rms = (blockSum / Float(blockCount)).squareRoot()
        let level = rms > 0 ? 20 * log10(rms) : -120
        blockSum = 0
        blockCount = 0
        gain = heading

        let noise = floor.map { level < $0 ? level : $0 + Self.floorRise * blockSeconds } ?? min(level, Self.loudestFloor)
        floor = noise
        let isSpeech = level >= Self.quietest && level >= noise + speechMargin
        if isSpeech {
            let seconds = level > (speech ?? level) ? Self.louderSeconds : Self.softerSeconds
            speech = speech.map { $0 + (level - $0) * min(1, blockSeconds / seconds) } ?? level
            sinceSpeech = 0
        } else {
            sinceSpeech += blockSeconds
        }

        var wanted: Float = 1
        if let speech, sinceSpeech < Self.hangoverSeconds {
            wanted = pow(10, min(maxGain, max(0, target - speech)) / 20)
        } else if gain > 1 {
            wanted = gain + (1 - gain) * min(1, blockSeconds / Self.releaseSeconds)
        }
        heading = wanted
        step = (wanted - gain) / Float(blockSize)
    }

    // Leaves anything under the knee alone and bends the rest smoothly toward a ceiling just under full scale (in
    // Float, tanh of a loud sample rounds to exactly 1), so nothing ever clips.
    private static func limit(_ sample: Float) -> Float {
        let magnitude = abs(sample)
        guard magnitude > knee else { return sample }
        let bent = knee + (ceiling - knee) * tanh((magnitude - knee) / (ceiling - knee))
        return sample < 0 ? -bent : bent
    }
}
