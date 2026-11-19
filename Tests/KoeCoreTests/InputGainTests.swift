import Foundation
import KoeCore
import Testing

struct InputGainTests {
    private static let rate = 16000

    /// Bursts of a 220 Hz tone at `speech` dBFS RMS (0.4 s on, 0.15 s off) over room noise at `noise` dBFS.
    private static func talk(seconds: Double, speech: Float, noise: Float = -65) -> [Float] {
        let tone = pow(10, speech / 20) * Float(2).squareRoot()
        let hiss = pow(10, noise / 20) * Float(3).squareRoot()
        var seed: UInt32 = 7
        return (0..<Int(seconds * Double(rate))).map { index in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let random = Float(seed) / Float(UInt32.max) * 2 - 1
            let time = Double(index) / Double(rate)
            let voiced = time.truncatingRemainder(dividingBy: 0.55) < 0.4
            return random * hiss + (voiced ? tone * Float(sin(2 * .pi * 220 * time)) : 0)
        }
    }

    private static func noise(seconds: Double, at level: Float) -> [Float] {
        talk(seconds: seconds, speech: -200, noise: level)
    }

    private static func decibels(_ samples: ArraySlice<Float>) -> Float {
        20 * log10(AudioLevel.rms(samples))
    }

    /// The level of the voiced stretches in `from...to` seconds of a `talk` signal.
    private static func speechLevel(_ samples: [Float], from start: Double, to end: Double) -> Float {
        var voiced: [Float] = []
        for index in Int(start * Double(rate))..<Int(end * Double(rate)) {
            let time = Double(index) / Double(rate)
            let offset = time.truncatingRemainder(dividingBy: 0.55)
            if offset > 0.05, offset < 0.35 { voiced.append(samples[index]) }
        }
        return decibels(voiced[...])
    }

    @Test func quietSpeechReachesTheTarget() {
        var gain = InputGain()
        let output = gain.apply(Self.talk(seconds: 6, speech: -28))
        #expect(abs(Self.speechLevel(output, from: 4, to: 6) - -18) < 1.5)
        #expect(abs(gain.gainDecibels - 10) < 1.5)
    }

    @Test func theFirstWordsAreRaisedRightAway() {
        var gain = InputGain()
        let output = gain.apply(Self.talk(seconds: 0.55, speech: -30))
        #expect(Self.speechLevel(output, from: 0, to: 0.55) > -21)
    }

    @Test func gainStopsAtItsCap() {
        var gain = InputGain()
        let output = gain.apply(Self.talk(seconds: 4, speech: -45, noise: -80))
        #expect(abs(Self.speechLevel(output, from: 2, to: 4) - -27) < 1.5)
    }

    @Test func loudSpeechIsLeftAlone() {
        var gain = InputGain()
        let input = Self.talk(seconds: 3, speech: -12)
        let output = gain.apply(input)
        #expect(abs(Self.speechLevel(output, from: 1, to: 3) - Self.speechLevel(input, from: 1, to: 3)) < 0.5)
    }

    @Test func aQuietRoomIsNotRaised() {
        var gain = InputGain()
        let input = Self.noise(seconds: 3, at: -60)
        let output = gain.apply(input)
        #expect(abs(Self.decibels(output[...]) - Self.decibels(input[...])) < 0.1)
        #expect(gain.gainDecibels == 0)
    }

    @Test func aPauseAfterSpeechFallsBackToTheRoom() {
        var gain = InputGain()
        let input = Self.talk(seconds: 3, speech: -30) + Self.noise(seconds: 2, at: -65)
        let output = gain.apply(input)
        let pause = (3 + 1) * Self.rate..<(3 + 2) * Self.rate
        #expect(abs(Self.decibels(output[pause]) - Self.decibels(input[pause])) < 0.5)
        #expect(abs(gain.gainDecibels) < 0.1)
    }

    @Test func aSuddenShoutNeverClips() {
        var gain = InputGain()
        let input = Self.talk(seconds: 3, speech: -40) + Self.talk(seconds: 1, speech: -1)
        let output = gain.apply(input)
        #expect(output.allSatisfy { abs($0) <= 0.98 })
        #expect(output.map(abs).max()! > 0.9)
    }

    @Test func theOutputDoesNotDependOnHowTheInputIsSplit() {
        let input = Self.talk(seconds: 2, speech: -30)
        var whole = InputGain()
        let expected = whole.apply(input)
        var split = InputGain()
        var output: [Float] = []
        let sizes = [1, 159, 160, 161, 1024, 3, 4096]
        var start = 0
        var turn = 0
        while start < input.count {
            let end = min(input.count, start + sizes[turn % sizes.count])
            output += split.apply(Array(input[start..<end]))
            start = end
            turn += 1
        }
        #expect(output == expected)
    }
}
