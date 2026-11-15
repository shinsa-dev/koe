import Foundation
import KoeCore

/// Stamps the stages of the session that runs now. Stages come from the main thread, the audio thread and the
/// transcriber, so it is thread safe. A trace begins at the shortcut that starts a session and ends once it is copied.
final class LatencyLog: @unchecked Sendable {
    static let shared = LatencyLog()

    private let lock = NSLock()
    private var current: LatencyTrace?
    private var done: [LatencyTrace] = []

    func mark(_ stage: LatencyTrace.Stage) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.withLock {
            if stage == .startPressed { current = LatencyTrace() }
            current?.mark(stage, at: now)
            if stage == .copied, let trace = current {
                done.append(trace)
                current = nil
            }
        }
    }

    /// The traces of sessions copied since the last call.
    func takeFinished() -> [LatencyTrace] {
        lock.withLock {
            defer { done.removeAll() }
            return done
        }
    }
}
