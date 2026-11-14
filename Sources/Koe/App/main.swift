import AppKit

// Text as the web draws it (`-webkit-font-smoothing: antialiased`): no stem darkening, which made ABC Areal read a
// weight heavier than in Shinsa. It is read from Koe's own defaults, so it never touches other apps.
UserDefaults.standard.set(0, forKey: "AppleFontSmoothing")

if let flag = CommandLine.arguments.firstIndex(of: "--bench") {
    let arguments = Array(CommandLine.arguments.dropFirst(flag + 1))
    Task { @MainActor in exit(await TailBench.run(arguments)) }
    dispatchMain()
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
