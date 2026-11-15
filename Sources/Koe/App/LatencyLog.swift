import Foundation
import KoeCore
import OSLog

/// Stamps the stages of the session that runs now. Stages come from the main thread, the audio thread and the
/// transcriber, so it is thread safe. A trace begins at the shortcut that starts a session and ends once it is copied.
final class LatencyLog: @unchecked Sendable {
    static let shared = LatencyLog()
    private static let log = Logger(subsystem: "studio.shinsa.koe", category: "latency")

    private let lock = NSLock()
    private var current: LatencyTrace?
    private var done: [LatencyTrace] = []
    /// The session copied last, which its last pass may still refine.
    private var last: LatencyTrace?

    func mark(_ stage: LatencyTrace.Stage) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.withLock {
            if stage == .startPressed { current = LatencyTrace() }
            // The last pass and its refinement can come after the copy: they belong to the session copied last.
            if current == nil {
                last?.mark(stage, at: now)
                return
            }
            current?.mark(stage, at: now)
            if stage == .copied, let trace = current {
                if let breach = trace.breach { Self.log.error("\(breach, privacy: .public)") }
                done.append(trace)
                last = trace
                current = nil
            }
        }
    }

    /// The session copied last, with its refinement if one came.
    var lastCopied: LatencyTrace? { lock.withLock { last } }

    /// The traces of sessions copied since the last call.
    func takeFinished() -> [LatencyTrace] {
        lock.withLock {
            defer { done.removeAll() }
            return done
        }
    }
}
