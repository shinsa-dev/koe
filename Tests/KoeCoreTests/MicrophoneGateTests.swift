import KoeCore
import Testing

struct MicrophoneGateTests {
    @Test func aGrantedMicrophoneStartsAtOnceAndIsCheckedBehind() {
        #expect(MicrophoneGate.onStart(lastKnown: .granted) == .startThenRecheck)
    }

    @Test func anythingElseAsksMacOSBeforeStarting() {
        #expect(MicrophoneGate.onStart(lastKnown: .notDetermined) == .askFirst)
        #expect(MicrophoneGate.onStart(lastKnown: .denied) == .askFirst)
    }

    @Test func onlyAnAnswerOtherThanGrantedCountsAsRevoked() {
        #expect(!MicrophoneGate.isRevoked(recheck: .granted))
        #expect(MicrophoneGate.isRevoked(recheck: .denied))
        #expect(MicrophoneGate.isRevoked(recheck: .notDetermined))
    }
}
