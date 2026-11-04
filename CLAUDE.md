# Koe: development notes

Koe is a menubar-only macOS app (SwiftPM + `build.sh`, no Xcode project) that transcribes your voice on device and
copies one bundle of transcript and attachments. The README is the design record; read it before changing
behaviour it describes.

## Commands

- `swift build` builds; `./build.sh` assembles `Koe.app`; `./build.sh --install` puts it in `/Applications`.
- **After every change to the app, run `./build.sh --install`** before you hand over, so the human can always test
  the latest build from `/Applications`. Never leave `/Applications/Koe.app` behind the branch.
- `swift test --filter KoeCoreTests` runs the unit tests. `swiftlint lint --quiet Sources Tests` lints.
- `python3 scripts/tokens.py` and `python3 scripts/fonts.py` regenerate Shinsa's colours and ABC Areal from
  `~/Developer/Projects/shinsa` (`--check` on tokens fails on drift). `swift scripts/icon.swift` redraws the
  placeholder `Resources/Koe.icns`.

## Rules

- **Native structure, Shinsa character.** Windows, menus and controls are the system's own (standard windows and
  toolbars, SwiftUI switches, pickers and push buttons through `KoeButtonStyle`, SF Symbols through `Icon`). The
  character is Shinsa's: ABC Areal through `Typography`, Shinsa's colours through `Palette`/`Tone` (`Tokens.swift`
  is generated: change the web token and rerun `scripts/tokens.py`), its settings cards (`SettingsGroup`,
  `SettingRow`) and its blue as the tint. Never raw RGB or system colours in views.
- Everything that floats over other apps (pill, cards, overlays, the clip review) is a dark HUD, like Droppy and the
  notch: `floatingSurface` on a `ToolPanel` or `PillPanel`, which pin the dark appearance whatever the theme.
- Koe is a menu bar app (`LSUIElement`); while its window is open it switches to a regular app (Dock, ⌘Tab, menu
  bar) and back when it closes. Keep that when adding windows.
- Copy: sentence case (buttons and titles too), full sentences, no em dashes, American spelling.
- Logic that can live without AppKit goes in `KoeCore` and gets Swift Testing tests. `Koe` holds AppKit, SwiftUI
  and system frameworks.
- Swift 6 language mode: UI types are `@MainActor`; anything crossing to audio or capture threads is `Sendable`.
- Windows and panels are AppKit; their content is SwiftUI in an `NSHostingController`/`NSHostingView`.
- `build.sh` runs under macOS `/bin/bash` 3.2: no empty-array `"${A[@]}"` under `set -u`.
- Comments are rare: only a why that the code can't say.
