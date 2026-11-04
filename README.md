# Koe

Koe (声, "voice") is a menubar Mac app, part of Shinsa, for talking to agents. You speak, and while you speak you
take screenshots, write notes, record slow-motion clips and drop in files. When you stop, Koe copies one bundle:
your words with every attachment placed at the moment you added it. Pasting it into Claude, ChatGPT, Slack or a
terminal agent brings everything in, in order, so the agent reads each screenshot where you talked about it.

It transcribes on device. Nothing you say or capture leaves your Mac.

## Status

Phases 1 to 5 of the first version: the app, its menu bar item, the setup window that asks for the microphone,
screen recording and (optionally) Accessibility, the session timeline and bundle composer in `KoeCore`, live
on-device transcription with the ⌥Space hotkey and the pill, the screenshot, note and drop tools, and the slow-motion
clip tool. The clipboard follows.

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
`KoeButtonStyle`, `SegmentedTabs`) are the web's `SettingsCard`, `RemoteHero`, `Button` and default `Tabs`. Copy follows Shinsa's voice: sentence
case, full sentences, no em dashes.

## Layout

```
Sources/KoeCore/   Pure logic, unit-tested: the setup checklist, Session (the timeline), BundleComposer
Sources/Koe/App/   main, AppDelegate, the status menu, HotKeys (Carbon global shortcuts)
Sources/Koe/Transcription/ Transcriber, AppleSpeechTranscriber (SpeechAnalyzer), AudioSource: microphone and file
Sources/Koe/Session/ SessionController: one session at a time, from the hotkey to the finished Session
Sources/Koe/HUD/   The pill: a non-activating panel at the top of the screen, and the drop target
Sources/Koe/Tools/ ToolCoordinator, ScreenFreezer, RegionPicker (the frozen-screen overlay), NoteCard, ToolPanel;
                   ClipTool, ClipRecorder, RecordingIndicator, ClipMovie, ClipReviewer (the clip tool)
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
[3] Video of Figma: …/clip-1.mov
[4] Frame 0.42 s into [3], of Figma: …/clip-1-frame-25.png
```

- Each annotation goes to the word boundary nearest its time. Inside a gap the distance is zero; inside a word it
  goes to the nearer side, and the exact middle goes after the word.
- A sentence end within 0.6 s wins over a nearer gap mid-sentence, so a screenshot doesn't split "the button | here".
- A pause of 2.5 s after a sentence starts a paragraph. An annotation in the later half of that pause opens the next
  paragraph, since you were already on to the next thing.
- Files, screenshots and clips are numbered `[n]` in reading order, not in the order you added them, so the nth
  image pasted is the nth marker. A note on an attachment rides in its marker; a note on its own reads `[Note: …]`.
- A frame picked out of a clip is a screenshot that says which clip it came from and when in it.
- The footer lists every file with its path, for terminal agents that read files rather than pasted images. The
  HTML flavor is the same text with images inline.

## Transcription

- Apple's `SpeechAnalyzer` with `SpeechTranscriber` (macOS 26), on device. It asks for volatile results, so the pill
  shows a guess at once and replaces it when the result is final, and for audio time ranges, which time the words.
- `LiveTranscript` (`KoeCore`) keeps settled words and the current guess. A final result times each run; a volatile
  one usually doesn't, so its words share the result's range. A run without a leading space ("'t" after "don")
  continues the word before it.
- The session's clock is the audio the source has delivered (`AudioSource.currentTime`), not the wall clock, so an
  annotation's time lines up with the words' times even when the model lags.
- Stopping closes the source; the session ends once the model settles the last words. A press of the hotkey while
  it finishes is ignored. A failure shows in the pill for six seconds.
- The hotkey is Carbon's `RegisterEventHotKey`, which needs no Accessibility permission. When another app holds
  ⌥Space, the menu says so and starting from the menu still works.

## Tools

Every tool takes a ticket from `SessionController.openTicket()`, stamped with the session's audio time the moment
you start it, so a screenshot lands at the word you were saying when you pressed the key, not when you finished
dragging. A tool used while no session runs starts one. `AnnotationLedger` (`KoeCore`) holds the tickets: a session
you stop while a tool is open ends once the tool hands back its annotation or you cancel it.

- **Screenshot, ⌥⇧S.** `ScreenFreezer` captures every screen with ScreenCaptureKit, leaving Koe's own windows out,
  and lists the windows on them front to back (CGWindowList). The overlay shows the frozen screens dimmed: drag a
  region, or click to take the window under the pointer. A note card opens under the region (above it when there is
  no room). Return attaches, Esc cancels. The crop is saved at full resolution as `screenshot-<n>.png`; its source is
  the window you clicked, or the frontmost window under the region's centre.
- **Note, ⌥⇧N.** A note card under the pill. A blank note adds nothing.
- **Clip, ⌥⇧C.** macOS has no public way to slow other apps down, so Koe records instead and you slow the recording
  down. Pick a region as for a screenshot (the pick starts recording; there is no note card). `ClipRecorder` records
  it with ScreenCaptureKit's `SCRecordingOutput` at up to 60 fps, with the pointer and without Koe's windows, to
  `clip-<n>.mov`. A dashed red outline and a card with the clock show while it records; ⌥⇧C again, the card's Stop,
  stopping the session or 30 s (`ClipFrames.longest`) stops it. Then the clip opens at 0.25× (`PlaybackSpeed`): play
  it at 1×, 0.5×, 0.25× or 0.1×, step with ← and → (⇧ for ten), scrub, and press P to pick a frame, each with an
  optional note. Return attaches, Esc discards (in a note, Esc only leaves the note).
- A screen recording only stores a frame when something changed, so `ClipMovie` reads the clip's real frame times
  (`ClipFrames`) and stepping goes from one change to the next. Seeks aim at the middle of a frame and frames are
  pulled with zero tolerance, so the image you pick is the one you saw.
- The clip is stamped when recording began, and each picked frame at that time plus its time in the clip, so a frame
  lands at the words you said while it was on screen. All of them close the ticket taken when you pressed ⌥⇧C.
  Frames are saved full size as `clip-<n>-frame-<m>.png`.
- **Drop on the pill.** Each file is stamped when it lands and copied (an APFS clone) into the session's folder, so
  the bundle keeps it if the original moves. The pill shows how many attachments the session holds.
- Tool panels are non-activating: they take typing without bringing Koe to the front, so the app you were in keeps
  focus. Esc is caught with a local key monitor, because a text field turns it into completion before the window
  sees it.
- A session's files live in `~/Library/Application Support/Koe/Sessions/<date-time-id>/` (`SessionFolder`), with
  names that carry no spaces so a pasted path stays one word.

## Notes

- Screen recording and Accessibility only report granted or not. Koe remembers whether it has asked
  (`asked.<permission>` in its defaults): before, a row offers the system prompt; after, it opens System Settings.
  macOS only applies a new screen recording grant once the app is reopened, so the row says so.
- `defaults write studio.shinsa.koe appearance light|dark` pins a theme. `--setup` opens the setup window at launch
  and `--open-menu` opens the menu, for screenshots. `--audio-file <path>` plays a recording into each session
  instead of the microphone, `--start` starts one at launch, and `--print-session` prints the finished bundle text
  to stdout: `say -o /tmp/s.aiff "Look at this." && ./Koe.app/Contents/MacOS/Koe --audio-file /tmp/s.aiff --start
  --print-session`.
- `--script "<steps>"` plays tools into the session at audio times (`ScriptedStep`): `1.5 shot 120,80,640,360 A
  note; 3 note Compare with Finder; 4 drop /tmp/spec.pdf; 6 clip 120,80,640,360 2 0.4,1.1` (records 2 s and picks
  the frames 0.4 s and 1.1 s in); `shot!`, `note!` and `clip!` leave the tool open. `--backdrop <png>` shows that
  image instead of capturing your screen, so captures of Koe never show what's on your screen, and `--clip-file
  <mov>` stands in for every recorded clip (a scripted one still shows the recording outline for its length). A
  script needs a session, so pair it with `--start`.
