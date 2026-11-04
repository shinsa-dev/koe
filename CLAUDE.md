# Koe: development notes

Koe is a menubar-only macOS app (SwiftPM + `build.sh`, no Xcode project) that transcribes your voice on device and
copies one bundle of transcript and attachments. The README is the design record; read it before changing
behaviour it describes.

## Commands

- `swift build` builds; `./build.sh` assembles `Koe.app`; `./build.sh --install` puts it in `/Applications`.
- `swift test --filter KoeCoreTests` runs the unit tests. `swiftlint lint --quiet Sources Tests` lints.
- `python3 scripts/tokens.py`, `python3 scripts/fonts.py` and `bun scripts/icons.ts` regenerate the design system
  from `~/Developer/Projects/shinsa`. `--check` on tokens and icons fails on drift. Run `icons.ts` after naming a
  new `"Icon…"` in Swift.

## Rules

- **Shinsa's UI system, everywhere.** Every colour through `Palette` or `Tone` (never system colours or raw RGB in
  views), every font through `Typography`, every glyph through `Icon` (the web's icons, never SF Symbols), buttons
  through `KoeButtonStyle`. `Tokens.swift` is generated: change the web token and rerun the script. When a screen
  needs a component, port the web's (`packages/ui/src/components`, `apps/web/src`) or shinsa-ios's (`Shinsa/UI`)
  rather than inventing one.
- Copy is Shinsa's voice: sentence case (buttons and titles too), full sentences, no em dashes, American spelling.
- Logic that can live without AppKit goes in `KoeCore` and gets Swift Testing tests. `Koe` holds AppKit, SwiftUI
  and system frameworks.
- Swift 6 language mode: UI types are `@MainActor`; anything crossing to audio or capture threads is `Sendable`.
- Windows and panels are AppKit; their content is SwiftUI in an `NSHostingController`/`NSHostingView`.
- `build.sh` runs under macOS `/bin/bash` 3.2: no empty-array `"${A[@]}"` under `set -u`.
- Comments are rare: only a why that the code can't say.
