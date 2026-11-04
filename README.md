# Koe

Koe (声, "voice") is a menubar Mac app, part of Shinsa, for talking to agents. You speak, and while you speak you
take screenshots, write notes, record slow-motion clips and drop in files. When you stop, Koe copies one bundle:
your words with every attachment placed at the moment you added it. Pasting it into Claude, ChatGPT, Slack or a
terminal agent brings everything in, in order, so the agent reads each screenshot where you talked about it.

It transcribes on device. Nothing you say or capture leaves your Mac.

## Status

Phases 1 and 2 of the first version: the app, its menu bar item, the setup window that asks for the microphone,
screen recording and (optionally) Accessibility, and the session timeline and bundle composer in `KoeCore`.
Transcription, the tools and the clipboard follow.

## Build

Needs macOS 26 and Xcode 26 or later (Swift 6.2).

```sh
./build.sh            # builds ./Koe.app
./build.sh --install  # copies it into /Applications and launches it
swift test            # KoeCore's unit tests
```

There is no Xcode project: SwiftPM builds the binary and `build.sh` assembles and ad-hoc signs the app.

## Design

Koe looks and reads like Shinsa. Its design system is Shinsa's, generated rather than copied by hand:

- `scripts/tokens.py` writes `Sources/Koe/UI/Tokens.swift` from shinsa's `packages/ui/src/styles/globals.css`
  (every colour, light and dark). `Palette` and `Tone` name them.
- `scripts/fonts.py` cuts ABC Areal, the web's typeface, at the web's weights into `Resources/Fonts`, with the web's
  -0.02em tracking baked in.
- `bun scripts/icons.ts` renders every `"Icon…"` the Swift names into `Resources/Icons` with shinsa's own icon
  pipeline. Koe never uses SF Symbols.

They read `~/Developer/Projects/shinsa` (`SHINSA_REPO`, `SHINSA_SOURCE`). The components (`Card`, `Hero`,
`KoeButtonStyle`) are the web's `SettingsCard`, `RemoteHero` and `Button`. Copy follows Shinsa's voice: sentence
case, full sentences, no em dashes.

## Layout

```
Sources/KoeCore/   Pure logic, unit-tested: the setup checklist, Session (the timeline), BundleComposer
Sources/Koe/App/   main, AppDelegate, the status menu
Sources/Koe/Setup/ PermissionCenter (reads and asks for what macOS gates), the setup window
Sources/Koe/UI/    Tokens (generated), Palette, Typography, Icon, Components/
Tests/KoeCoreTests Swift Testing
Resources/         Info.plist, Fonts/, Icons/ (generated)
```

## The bundle

A `Session` holds the words you said (`TimedWord`, each with its start and end in the session's audio) and what you
added (`Annotation`: a screenshot, clip, file or note, stamped with the audio time at the moment you started it).
`BundleComposer` turns it into what Koe copies:

```
Look at the sidebar. [1: padding is 8, should be 12] The button here [2] looks off.

[3] Now the menu opens too slowly. [Note: compare with Finder]

Attachments:
[1] Image of Safari, "Settings": ~/Library/Application Support/Koe/Sessions/…/1.png
[2] Image of Safari, "Settings": …/2.png
[3] Video of Figma: …/3.mov
```

- Each annotation goes to the word boundary nearest its time. Inside a gap the distance is zero; inside a word it
  goes to the nearer side, and the exact middle goes after the word.
- A sentence end within 0.6 s wins over a nearer gap mid-sentence, so a screenshot doesn't split "the button | here".
- A pause of 2.5 s after a sentence starts a paragraph. An annotation in the later half of that pause opens the next
  paragraph, since you were already on to the next thing.
- Files, screenshots and clips are numbered `[n]` in reading order, not in the order you added them, so the nth
  image pasted is the nth marker. A note on an attachment rides in its marker; a note on its own reads `[Note: …]`.
- The footer lists every file with its path, for terminal agents that read files rather than pasted images. The
  HTML flavor is the same text with images inline.

## Notes

- Screen recording and Accessibility only report granted or not. Koe remembers whether it has asked
  (`asked.<permission>` in its defaults): before, a row offers the system prompt; after, it opens System Settings.
  macOS only applies a new screen recording grant once the app is reopened, so the row says so.
- `defaults write studio.shinsa.koe appearance light|dark` pins a theme. `--setup` opens the setup window at launch
  and `--open-menu` opens the menu, for screenshots.
