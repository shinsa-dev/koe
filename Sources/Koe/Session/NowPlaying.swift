import AudioToolbox
import CoreAudio
import Foundation
import KoeCore
import os

/// Pauses what plays while you dictate and plays it again when you finish, as `MediaPause` decides.
@MainActor
final class NowPlaying {
    private var pause = MediaPause()
    nonisolated private static let log = Logger(subsystem: "studio.shinsa.koe", category: "media")

    /// The probe, set up ahead of time while pausing is on and allowed. Setting one up takes from a tenth of a second
    /// to seconds, so it happens off the main thread; starting a ready one hears the output within milliseconds, so
    /// the pause lands as the session opens.
    private var probe: Task<OutputProbe?, Never>?

    /// Sets the probe up or takes it down, to match the setting and the permission. Its audio only runs in a session.
    func prepare(enabled: Bool) {
        let wanted = enabled && SystemAudioAccess.status == .granted
        guard wanted != (probe != nil) else { return }
        if wanted {
            probe = Task.detached {
                do {
                    return try OutputProbe()
                } catch {
                    Self.log.error("Could not set up the output probe: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        } else if let probe {
            self.probe = nil
            Task { await probe.value?.destroy() }
        }
    }

    /// Whether a session's listen owns the probe, so a warm-up never stops it underneath.
    private var listening = false
    private var warming: Task<Void, Never>?

    /// Fn went down, and its release may open a session: the probe starts hearing now, so by the release Koe already
    /// knows whether something plays and pauses it at once. Unless a session takes the probe over, it stops again.
    func warm(enabled: Bool) {
        guard enabled, warming == nil, let probe, SystemAudioAccess.status == .granted,
              OutputProcesses.othersRunning() else { return }
        warming = Task {
            defer { warming = nil }
            guard let output = await probe.value, output.start() else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !listening { output.stop() }
        }
    }

    func sessionOpened(enabled: Bool) {
        let listen = pause.sessionOpened(enabled: enabled, allowed: SystemAudioAccess.status == .granted,
                                         streamsOpen: enabled && OutputProcesses.othersRunning())
        if listen { Task { await self.listen() } }
    }

    func sessionClosed() {
        if pause.sessionClosed() == .play { send(.play) }
    }

    private func listen() async {
        prepare(enabled: true)
        listening = true
        defer { listening = false }
        guard let probe = await probe?.value, probe.start() else {
            Self.log.error("Could not listen to the Mac's output")
            _ = pause.heard(peak: 0)
            return
        }
        defer { probe.stop() }
        guard pause.heard(peak: await probe.firstSound(within: .milliseconds(250))) == .pause else { return }
        send(.pause)
        // A player takes a moment to fade out; the peak is read once it has.
        try? await Task.sleep(for: .milliseconds(500))
        if pause.settled(peak: await probe.peak(over: .milliseconds(300))) == .play { send(.play) }
    }

    private func send(_ command: MediaPause.Command) {
        Self.log.info("Media \(command == .pause ? "pause" : "play", privacy: .public)")
        MediaRemote.send(command)
    }
}

/// The player in charge of the Mac's media keys, reached through MediaRemote. macOS no longer lets an app read what
/// it plays, but it still takes commands. Explicit pause and play, never a toggle, so a wrong guess can't start it.
private enum MediaRemote {
    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool
    private static let sendCommand: SendCommand? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
              let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(symbol, to: SendCommand.self)
    }()

    static func send(_ command: MediaPause.Command) {
        _ = sendCommand?(command == .play ? 0 : 1, nil)
    }
}

/// Which apps have an audio output stream open. Cheap and needs no permission, but a stream stays open while silent,
/// so this only says whether listening is worth it.
private enum OutputProcesses {
    static func othersRunning() -> Bool {
        let own = getpid()
        return processObjects().contains { object in
            read(kAudioProcessPropertyIsRunningOutput, of: object, as: UInt32.self) ?? 0 != 0
                && read(kAudioProcessPropertyPID, of: object, as: pid_t.self) != own
        }
    }

    static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    static func read<Value>(_ selector: AudioObjectPropertySelector, of object: AudioObjectID,
                            as _: Value.Type) -> Value? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<Value>.size)
        let value = UnsafeMutablePointer<Value>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }
}

/// Listens to everything the Mac plays but Koe, through a private process tap, and keeps the loudest sample.
/// Nothing is recorded or kept: the samples are only measured.
private final class OutputProbe: Sendable {
    struct Failure: LocalizedError {
        let step: String
        let status: OSStatus
        var errorDescription: String? { "\(step) failed (\(status))" }
    }

    private let tap: AudioObjectID
    private let device: AudioObjectID
    private let ioProc: AudioDeviceIOProcID
    private let loudest: OSAllocatedUnfairLock<Float>
    private let running = OSAllocatedUnfairLock(initialState: false)

    init() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: Self.ownProcessObject.map { [$0] } ?? [])
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        try Self.check(AudioHardwareCreateProcessTap(description, &tap), "Creating the tap")

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Koe output probe",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        let created = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard created == noErr else {
            AudioHardwareDestroyProcessTap(tap)
            throw Failure(step: "Creating the device", status: created)
        }

        let loudest = OSAllocatedUnfairLock<Float>(initialState: 0)
        var ioProc: AudioDeviceIOProcID?
        let started = AudioDeviceCreateIOProcIDWithBlock(&ioProc, device, nil) { _, input, _, _, _ in
            var peak: Float = 0
            for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
                guard let data = buffer.mData else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                for index in 0..<Int(buffer.mDataByteSize) / MemoryLayout<Float>.size {
                    peak = max(peak, abs(samples[index]))
                }
            }
            let heard = peak
            loudest.withLock { $0 = max($0, heard) }
        }
        guard started == noErr, let ioProc else {
            if let ioProc { AudioDeviceDestroyIOProcID(device, ioProc) }
            AudioHardwareDestroyAggregateDevice(device)
            AudioHardwareDestroyProcessTap(tap)
            throw Failure(step: "Reading the device", status: started)
        }
        self.tap = tap
        self.device = device
        self.ioProc = ioProc
        self.loudest = loudest
    }

    /// Starts hearing the output, unless it already does: what a warm-up heard counts. The device is set up already,
    /// so the first samples arrive within milliseconds.
    func start() -> Bool {
        running.withLock { running in
            guard !running else { return true }
            loudest.withLock { $0 = 0 }
            running = AudioDeviceStart(device, ioProc) == noErr
            return running
        }
    }

    /// The loudest sample, as soon as one is louder than silence, or after `limit` of silence.
    func firstSound(within limit: Duration) async -> Float {
        let clock = ContinuousClock()
        let deadline = clock.now + limit
        while clock.now < deadline {
            let heard = loudest.withLock { $0 }
            if heard >= MediaPause.silence { return heard }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return loudest.withLock { $0 }
    }

    /// The loudest sample heard over the next `duration`.
    func peak(over duration: Duration) async -> Float {
        loudest.withLock { $0 = 0 }
        try? await Task.sleep(for: duration)
        return loudest.withLock { $0 }
    }

    func stop() {
        running.withLock { running in
            AudioDeviceStop(device, ioProc)
            running = false
        }
    }

    func destroy() {
        AudioDeviceStop(device, ioProc)
        AudioDeviceDestroyIOProcID(device, ioProc)
        AudioHardwareDestroyAggregateDevice(device)
        AudioHardwareDestroyProcessTap(tap)
    }

    private static var ownProcessObject: AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    private static func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw Failure(step: step, status: status) }
    }
}

/// System audio recording, which the tap needs. macOS has no public call to read it without asking, so Koe asks TCC
/// directly.
enum SystemAudioAccess {
    private static var service: CFString { "kTCCServiceAudioCapture" as CFString }
    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @Sendable (Bool) -> Void) -> Void
    nonisolated(unsafe) private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    static var status: PermissionStatus {
        guard let symbol = dlsym(tcc, "TCCAccessPreflight") else { return .notDetermined }
        return switch unsafeBitCast(symbol, to: Preflight.self)(service, nil) {
        case 0: .granted
        case 1: .denied
        default: .notDetermined
        }
    }

    static func request(_ done: @escaping @Sendable (Bool) -> Void) {
        guard let symbol = dlsym(tcc, "TCCAccessRequest") else { return done(false) }
        unsafeBitCast(symbol, to: Request.self)(service, nil, done)
    }
}
