import KoeCore
import Testing

struct AudioLevelTests {
    @Test func rmsOfSilenceAndOfAFullSquareWave() {
        #expect(AudioLevel.rms([Float]()) == 0)
        #expect(AudioLevel.rms([0, 0, 0] as [Float]) == 0)
        #expect(AudioLevel.rms([1, -1, 1, -1] as [Float]) == 1)
        #expect(abs(AudioLevel.rms([0.5, -0.5] as [Float]) - 0.5) < 0.0001)
    }

    @Test func levelsMapOntoADecibelScale() {
        #expect(AudioLevel.normalized(rms: 0) == 0)
        #expect(AudioLevel.normalized(rms: 1) == 1)
        #expect(AudioLevel.normalized(rms: 2) == 1)
        // -50 dB is the floor; -25 dB is half way.
        #expect(AudioLevel.normalized(rms: 0.003) == 0)
        #expect(abs(AudioLevel.normalized(rms: 0.0562) - 0.5) < 0.01)
    }

    @Test func historyKeepsTheNewestLevelsInOrder() {
        var history = LevelHistory(count: 3)
        #expect(history.bars == [0, 0, 0])
        history.push(0.2)
        history.push(0.4)
        history.push(0.6)
        history.push(1.5)
        #expect(history.bars == [0.4, 0.6, 1])
        history.push(-1)
        #expect(history.bars == [0.6, 1, 0])
    }

    @Test func historyHasAtLeastOneBar() {
        var history = LevelHistory(count: 0)
        history.push(0.5)
        #expect(history.bars == [0.5])
    }
}
