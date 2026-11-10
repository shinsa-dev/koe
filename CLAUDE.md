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
  `~/Developer/Projects/shinsa` (`--check` on tokens fails on drift). `scripts/icon.sh` renders
  `Resources/Koe.svg` (Shinsa's tile and curved cut, with a blue dot) into `Resources/Koe.icns`. `bun scripts/icons.ts`
  renders every `"Icon…"` named in Swift with shinsa's own icon pipeline into `Resources/Icons` (`--check` on drift);
  run it after naming a new icon.

## Rules

- **Koe's own look, Shinsa's system.** Native windows and menus, but Koe draws its own content: the settings window
  is one page of cards in a full-size content view (no tabs, no sidebar, no system toolbar), and controls are Shinsa's, drawn by Koe:
  `KoeButtonStyle` (the web's `Button`), `KoeSwitchStyle` (the web's `Switch`), `SegmentedTabs` (the web's tabs),
  `SettingsGroup`/`SettingRow` cards, `Badge` (the web's `Badge`), `Kbd`, `TextInput` (the web's `Input`) and
  `.hint(_:shortcut:)` (the web's `Hint` tooltip; never `.help`). Each matches its React file in
  `packages/ui/src/components` size for size and variant for variant; change both together. Shortcuts live in
  hints, never inside a button. A button that sits in a row (close, remove) is a ghost: `.secondary`, or
  `.destructiveGhost` for remove, never a filled one. A list never shows a scroll bar: it is a `FadingScroll`. No focus rings anywhere (`focusEffectDisabled`). Never system push buttons, switches
  or segmented controls. ABC Areal through
  `Typography`, colours through `Palette`/`Tone` (`Tokens.swift` is generated: change the web token and rerun
  `scripts/tokens.py`), glyphs through `Icon`: the web's Central Icons, an SF Symbol only where Central has none.
  Never raw RGB or system colours in views. Text draws without stem darkening (`AppleFontSmoothing` 0 in `main.swift`),
  as the web's `antialiased` does.
- **Nothing is typed.** A note on a comment, screenshot or frame is what you say while the pill listens (`VoiceSpan`);
  the composer moves those words onto the attachment. Never add a text field to a tool. While a tool is open the
  pill says what to do (`ToolStatus`/`ToolPrompt`); nothing is drawn on the frozen screen but your drag and pin.
- Everything that floats over other apps (pill, cards, overlays, the clip review) is a dark HUD, like Droppy and the
  notch: `floatingSurface` on a `ToolPanel` or `PillPanel`, which pin the dark appearance whatever the theme. It
  gives every one the same hairline ring; never draw a different border on a floating surface.
- An attachment opens in the viewer (`AttachmentViewer`, a lightbox over the dimmed screen); a list row never
  grows in place. Lists show the newest first.
- In the pill, actions keep one order everywhere: discard on the left, pause in the middle, confirm on the right.
  Finishing a session never waits on an open tool: it attaches what is there (`sessionStopping`).
- Koe is a menu bar app (`LSUIElement`); while its window is open it switches to a regular app (Dock, ⌘Tab, menu
  bar) and back when it closes. Keep that when adding windows.
- Copy: sentence case (buttons and titles too), full sentences, no em dashes, American spelling.
- Logic that can live without AppKit goes in `KoeCore` and gets Swift Testing tests. `Koe` holds AppKit, SwiftUI
  and system frameworks.
- Swift 6 language mode: UI types are `@MainActor`; anything crossing to audio or capture threads is `Sendable`.
- Windows and panels are AppKit; their content is SwiftUI in an `NSHostingController`/`NSHostingView`.
- `build.sh` runs under macOS `/bin/bash` 3.2: no empty-array `"${A[@]}"` under `set -u`.
- Comments are rare: only a why that the code can't say.
