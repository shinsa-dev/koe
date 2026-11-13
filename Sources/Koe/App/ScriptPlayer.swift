import Foundation
import KoeCore

extension AppDelegate {
    /// `--script`: plays `ScriptedStep`s into the session at their audio times, for trying the tools hands-free.
    func play(_ script: String) {
        let steps: [ScriptedStep]
        do {
            steps = try ScriptedStep.parse(script)
        } catch {
            FileHandle.standardError.write(Data("Bad --script: \(error)\n".utf8))
            return
        }
        Task { [sessions] in
            for step in steps {
                while sessions.phase.isActive, sessions.currentTime < step.time {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard sessions.phase.isActive else { return }
                await run(step)
            }
        }
    }

    private func run(_ step: ScriptedStep) async {
        switch step.action {
        case .screenshot(let rect, let note, let talk): tools.screenshot(preset: rect, note: note, talk: talk, holds: step.holds)
        case .comment(let spot, let note, let talk): tools.comment(at: spot, note: note, talk: talk, holds: step.holds)
        case .drop(let path): tools.drop([URL(fileURLWithPath: path)])
        case .clip(let rect, let seconds, let picks):
            tools.clip(preset: ClipScript(region: rect, seconds: seconds, picks: picks, holds: step.holds))
        case .pause(let seconds):
            sessions.pause()
            try? await Task.sleep(for: .seconds(seconds))
            sessions.resume()
        case .attachments: pill.toggleAttachments()
        case .finish: sessions.finish()
        case .cancel: sessions.cancel()
        }
    }
}
