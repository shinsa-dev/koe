import AppKit

// Text as the web draws it (`-webkit-font-smoothing: antialiased`): no stem darkening, which made ABC Areal read a
// weight heavier than in Shinsa. It is read from Koe's own defaults, so it never touches other apps.
UserDefaults.standard.set(0, forKey: "AppleFontSmoothing")

if let flag = CommandLine.arguments.firstIndex(of: "--bench") {
    let arguments = Array(CommandLine.arguments.dropFirst(flag + 1))
    Task { @MainActor in exit(await TailBench.run(arguments)) }
    dispatchMain()
}

if let flag = CommandLine.arguments.firstIndex(of: "--names") {
    exit(MainActor.assumeIsolated { NamesCommand.run(Array(CommandLine.arguments.dropFirst(flag + 1))) })
}

let app = NSApplication.shared
// A background run never joins the Dock, ⌘Tab or the menu bar, and never takes focus.
app.setActivationPolicy(Launch.isBackground ? .prohibited : .accessory)
let delegate = AppDelegate()
app.delegate = delegate
if LatencyRun.isOn { LatencyRun.start(delegate) }
app.run()
