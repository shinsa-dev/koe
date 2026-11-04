import KoeCore
import Testing

struct SetupChecklistTests {
    @Test func readyOnceEveryRequiredPermissionIsGranted() {
        let checklist = SetupChecklist(statuses: [.microphone: .granted, .screenRecording: .granted])
        #expect(checklist.isReady)
        #expect(checklist.nextStep == .accessibility)
    }

    @Test func optionalPermissionDoesNotBlockReady() {
        let checklist = SetupChecklist(statuses: [
            .microphone: .granted, .screenRecording: .granted, .accessibility: .denied,
        ])
        #expect(checklist.isReady)
    }

    @Test func notReadyWhileARequiredPermissionIsMissing() {
        let checklist = SetupChecklist(statuses: [.microphone: .granted, .screenRecording: .denied])
        #expect(!checklist.isReady)
        #expect(checklist.nextStep == .screenRecording)
    }

    @Test func requiredStepsComeBeforeOptionalOnes() {
        let checklist = SetupChecklist(statuses: [.microphone: .granted, .accessibility: .notDetermined])
        #expect(checklist.nextStep == .screenRecording)
    }

    @Test func unknownStatusCountsAsNotDetermined() {
        let checklist = SetupChecklist(statuses: [:])
        #expect(checklist.status(of: .microphone) == .notDetermined)
        #expect(checklist.nextStep == .microphone)
        #expect(!checklist.isReady)
    }

    @Test func nothingLeftOnceEverythingIsGranted() {
        let checklist = SetupChecklist(statuses: Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, .granted) }))
        #expect(checklist.nextStep == nil)
        #expect(Permission.allCases.allSatisfy { checklist.action(for: $0) == .none })
    }

    @Test func actionAsksFirstThenSendsToSettings() {
        let checklist = SetupChecklist(statuses: [.microphone: .notDetermined, .screenRecording: .denied])
        #expect(checklist.action(for: .microphone) == .request)
        #expect(checklist.action(for: .screenRecording) == .openSettings)
    }

    @Test func onlyMicrophoneAndScreenRecordingAreRequired() {
        #expect(Permission.allCases.filter(\.isRequired) == [.microphone, .screenRecording])
    }
}
