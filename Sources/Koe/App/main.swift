import AppKit

// Text as the web draws it (`-webkit-font-smoothing: antialiased`): no stem darkening, which made ABC Areal read a
// weight heavier than in Shinsa. It is read from Koe's own defaults, so it never touches other apps.
UserDefaults.standard.set(0, forKey: "AppleFontSmoothing")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
