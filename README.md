# Koe

Koe (声, "voice") is a menubar Mac app, part of Shinsa, for talking to agents. You speak, and while you speak you
take screenshots, write notes, record slow-motion clips and drop in files. When you stop, Koe copies one bundle:
your words with every attachment placed at the moment you added it. Pasting it into Claude, ChatGPT, Slack or a
terminal agent brings everything in, in order, so the agent reads each screenshot where you talked about it.

It transcribes on device, with NVIDIA's Parakeet v3 on the Neural Engine by default. Nothing you say or capture
leaves your Mac; the only download is the speech model itself, from Hugging Face.

## Status

The first version, end to end: the menu bar item, a one-page settings window that asks for the microphone, screen
recording and Accessibility (all three required), on-device transcription with the Fn key and the pill with its
waveform and tools, the comment, screenshot, drop and slow-motion clip tools, and the bundle on the clipboard when
you stop, with recent sessions in the menu.

## Build

Needs macOS 26 and Xcode 26 or later (Swift 6.2).

```sh
./build.sh            # builds ./Koe.app
./build.sh --install  # copies it into /Applications and launches it
swift test            # KoeCore's unit tests
```

There is no Xcode project: SwiftPM builds the binary and `build.sh` assembles and signs the app. It signs with
`KOE_SIGN_IDENTITY` or the first Apple Development certificate in your keychain, so macOS keeps Koe's permissions
across rebuilds; without one it signs ad hoc and the permissions reset on every build. The icon is an Icon Composer
bundle, `Resources/Koe.icon` (two glass layers, the mark and the blue dot, on a light tile with a dark variant);
`build.sh` compiles it with `actool` into `Assets.car`. `scripts/icon.sh` renders `Resources/Koe.svg` into
`Resources/Koe.icns`, the fallback when `actool` fails.

## Design

Koe is a native Mac app that draws its own content in Shinsa's system. Windows and menus are the system's; inside
them Koe draws Shinsa's controls itself (`KoeButtonStyle`, `KoeSwitchStyle`, `SegmentedTabs`, the web's button,
switch and tabs), with SF Symbols for glyphs. The rest is Shinsa's: ABC Areal (`scripts/fonts.py` cuts it at the web's weights into `Resources/Fonts`), Shinsa's colours
(`scripts/tokens.py` writes `Sources/Koe/UI/Tokens.swift` from shinsa's `globals.css`; `Palette` and `Tone` name
them), its settings cards (`SettingsGroup`, `SettingRow`, `Card`) and its blue as the accent.
Everything that floats over other apps (the pill, the attachment list, the clip review)
is a dark HUD, like the notch: Shinsa's dark canvas over a blur of what is behind with one hairline ring
(`floatingSurface`, `Palette.hudRing`), dark whatever the theme. Copy is sentence case, full sentences, no em dashes.

- One window: Settings, one page with no tabs: Koe's icon and name, then Shinsa's cards for Permissions, Dictation,
  While you dictate, When you finish and General. No system toolbar; the page fades out under the window's controls. First launch
  opens it. Every shortcut can be changed: click it and press the new keys (`ShortcutRow`). Starting and
  finishing (Fn alone, watched by `FnKey` as Carbon cannot hold it; it needs Accessibility, and its monitors are added again once Accessibility flips, so no relaunch is needed. Koe only listens, so "Press 🌐 key to" in Keyboard settings should be Do Nothing; the shortcut row says so while it is not) works everywhere, so it needs ⌘, ⌃ or ⌥ (or to be Fn or a function key). The tools are ⌥⇧C to comment, ⌥⇧S for a
  screenshot and ⌥⇧R to record a clip, and `ShortcutCenter` holds them only while a session is open
  (`setDictating`). Every shortcut carries ⌘, ⌃ or ⌥: you type and use your apps as usual while you dictate, so a
  bare key is refused, and so is a ⌘ or ⇧⌘ combo with no ⌥ or ⌃ (`KeyCombo.belongsToApps`): apps use those
  themselves, and ⌘V is how you paste the bundle. No two actions share one (`Shortcuts`); a changed one is saved as
  `shortcut.<action>` = `keyCode:modifiers`. The old shortcuts are unregistered while you press the new one.
  While it is open Koe is a regular app, in the Dock and ⌘Tab, with the standard menu bar (⌘, ⌘W ⌘Q); closing it
  makes Koe a menu bar app again. Clicking Koe in the Dock or Finder opens it.
- The pill sits at the bottom centre of the screen you're on, above the Dock. While you talk it shows a waveform
  of your voice (`AudioLevel`, `LevelHistory`) with the tools on its left (comment, screenshot, clip, then the attachment count: each a
  button, so you never need the shortcuts), the clock (audio time, so it stops while paused, digits rolling with
  `.numericText()`), the attachment count, and pause, discard (red) and finish (blue). Pressing a button deflates the
  background behind its glyph by Shinsa's press inset (1 pt across, 0.5 pt down), the same at any size. When a
  session ends the same capsule shows a badge, a title and one line ("Copied to clipboard", "Press ⌘V to paste your
  words and 2 attachments anywhere"; "Recording thrown away"; "We couldn't hear you"), then fades.

## Recording is instant and never lost

- **No waiting states.** The hotkey opens the microphone at once and the pill is recording straight away.
  `CaptureStream` writes every buffer (16 kHz mono) to the session's `audio.caf` as it arrives and holds it until
  the speech model attaches; the model then catches up on what it missed. The model's setup (`SpeechSetup`: locale,
  assets, format) is worked out at launch and kept.
- **Finishing copies at once** (`Delivery`): the words heard so far, the model's latest guess included, go on the
  clipboard the moment you finish. When the last words settle a moment later, the session is saved again and the
  clipboard is replaced, unless you copied something else meanwhile (`SessionLibrary.refined`). Koe waits only for a
  tool you still have open, or when the model has not produced a single word yet.
- **Nothing is lost.** The audio is on disk as it is recorded (CAF stays readable when Koe is killed mid-write) and
  `draft.json` lists the attachments so far. At launch, a folder with audio and no `session.json` is a recording Koe
  never finished: it is transcribed from the file and saved to Recent sessions (`SessionArchive.unfinished`,
  `SessionLibrary.recover`). A model that fails mid-session leaves the recording running and attaches the audio.
  A new input device (AirPods connecting) restarts the tap instead of ending the session. Discard is the one way a
  recording goes: it deletes the session's folder.

## Layout

```
Sources/KoeCore/   Pure logic, unit-tested: the setup checklist, AudioLevel, Session (the timeline), BundleComposer,
                   ClipboardPlan, SessionArchive and HistoryEntry, KoeSettings
Sources/Koe/App/   main, AppDelegate, the status menu, MainMenu, HotKeys (Carbon global shortcuts), SessionLibrary
Sources/Koe/Clipboard/ BundleWriter: the bundle onto NSPasteboard, and ⌘V for you
Sources/Koe/Settings/ The window: settings on one page
Sources/Koe/Transcription/ Transcriber, ActiveTranscriber (picks the model), WindowedTranscriber with Parakeet
                   (FluidAudio) and Whisper (WhisperKit), AppleSpeechTranscriber (SpeechAnalyzer), ModelStore
                   (downloads), AudioSource: microphone and file
Sources/Koe/Session/ SessionController: one session at a time, from the hotkey to the finished Session
Sources/Koe/HUD/   The pill: a non-activating panel at the bottom of the screen, its waveform, the drop target
Sources/Koe/Tools/ ToolCoordinator, ScreenFreezer, RegionPicker (the frozen-screen overlay), NoteCard, ToolPanel;
                   ClipTool, ClipRecorder, RecordingIndicator, ClipMovie, ClipReviewer (the clip tool)
Sources/Koe/Setup/ PermissionCenter (reads and asks for what macOS gates, and reopens Koe)
Sources/Koe/UI/    Tokens (generated), Palette, Typography, Icon (SF Symbols), Components/
Tests/KoeCoreTests Swift Testing
Resources/         Info.plist, Koe.icns, Fonts/ (generated)
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
  HTML flavor is the same text, markers in bold, with no images: the files paste in on their own, and a `file://`
  image in a web editor shows broken.

## The clipboard

When a session ends, `SessionLibrary` saves it as `session.json` in its folder, then `ClipboardPlan` lays out the
clipboard and `BundleWriter` writes it: the first item holds the text (plain and HTML), then one item per file, its
file URL, in marker order. Chat boxes take the text from the first item and every file as an attachment. A file
that no longer exists is left out; with "Copy files with the text" off, only the text goes on.

- Checked with a WebKit view: a paste gets both files with their types and the HTML. WebKit hides the plain text
  when files come with it, so in Safari-based editors the HTML is the text, which is why it carries everything the
  plain text does.
- **One ⌘V for everything** ("Paste everything with one ⌘V", on by default, needs Accessibility). A chat box given
  text and files in one paste keeps one and drops the other. So `BundlePaster` leaves only the words on the
  clipboard and watches every ⌘V; when the text being pasted is a bundle Koe copied (`PasteIndex`, the last 200,
  reloaded from the saved sessions at launch), once ⌘ is let go and 180 ms more, Koe puts that bundle's files on, presses ⌘V itself and
  puts back whatever the clipboard held (`PastePlan.split`). It goes by the words, not by who wrote the clipboard
  last, so it still works after you copied other things, or when you paste the words out of a clipboard history;
  any other paste is left alone. The files upload like any pasted file, so this works for a remote agent too. In a
  terminal or a code editor such as VS Code, Cursor, Zed or a JetBrains IDE (`PastePlan.takesFiles`) only the words
  go in: they already end with every path. With "Copy attachments with the text" off no files follow, for old
  sessions too (`filesAllowed`). Without Accessibility, or with the setting off, everything goes on the clipboard at
  once as above.
- Finishing before the model has any words says "Copying your words" and only says "Copied" once they are on the
  clipboard. A model that never settles is given 10 s (`settleLimit`); then the session is copied with what it has.
- "Paste for you" presses ⌘V after 250 ms, with Accessibility allowed. Koe's panels never take focus, so it lands
  in the app you were in; when Koe itself is in front it does nothing and the pill says "Copied to clipboard".
- The pill stays up 2.5 s after you stop to say what it copied ("Copied the transcript and 2 files. Paste it
  anywhere."), or that it heard nothing.
- The menu lists the latest sessions (3, 5 or 10, in settings) under "Recent sessions", with when and how many
  attachments; clicking one copies its bundle again from `session.json`, with the settings as they are now.

## Transcription

- **Models.** Settings' Transcription card has one Model dropdown (`TranscriptionModel.catalog`, `ModelPicker`), a
  system menu with each model's state under its name: Parakeet v3 (recommended and the default, 25 European
  languages, about 480 MB), Parakeet v2 (English, about 460 MB), Whisper large-v3 turbo (99 languages, about 650 MB)
  and Apple's on-device model (built in). Choosing a model that isn't downloaded starts its download; the row shows
  its progress with Cancel, or Try again after a failure. "Delete a download" at the foot of the menu frees a
  model's disk space. The line under the card says which model runs and why when it isn't the chosen one.
- **Where they come from.** Parakeet is FluidAudio's Core ML port of NVIDIA's Parakeet TDT 0.6B, Whisper is
  WhisperKit's Neural Engine build; both download from Hugging Face into `~/Library/Application Support/Koe/Models/
  <model>` (`ModelStore`). A `.koe-installed` file is written last, once the model has loaded, so a download cut
  short never counts. FluidAudio reports no progress, so the card measures the folder against the expected size.
  Nothing else goes online: audio and text never leave the Mac.
- **First launch** starts downloading Parakeet v3 (`startedFirstDownload`, retried each launch until it lands) and
  transcribes with Apple's model meanwhile. `ActiveTranscriber` switches as soon as a download lands or the choice
  changes, without a relaunch; a session already running keeps its model. A chosen model that isn't downloaded,
  fails to load, or needs Apple silicon on an Intel Mac falls back to Apple's (`TranscriberRoute`).
- **Streaming with models that don't stream.** Parakeet and Whisper read whole stretches of audio, so
  `WindowedTranscriber` decodes again every 0.9 s from the first unsettled word to the newest audio, with 1.5 s of
  settled audio ahead as context. Words that end 2 s or more before the newest audio settle as a final update; the
  rest is a volatile guess the next pass replaces (`RollingWindow`). A window never grows past 14 s. Their sub-word
  tokens join into timed words (`TokenRuns`), so attachments still land at word boundaries. A recording Koe never
  finished is read in one pass with the active model.
- Apple's `SpeechAnalyzer` with `SpeechTranscriber` (macOS 26) streams on its own. It asks for volatile results and
  for audio time ranges, which time the words.
- `LiveTranscript` (`KoeCore`) keeps settled words and the current guess. A final result times each run; a volatile
  one usually doesn't, so its words share the result's range. A run without a leading space ("'t" after "don")
  continues the word before it.
- The session's clock is the audio the source has delivered (`AudioSource.currentTime`), not the wall clock, so an
  annotation's time lines up with the words' times even when the model lags.
- Stopping closes the source; the session ends once the model settles the last words. A press of the hotkey while
  it finishes is ignored. A failure shows in the pill for six seconds.
- A combo hotkey is Carbon's `RegisterEventHotKey`, which needs no Accessibility permission, but Fn (the default),
  ⇧⌘-click and the one-⌘V paste do, so setup asks for Accessibility as a required step. When another app holds
  its shortcut, the menu says so and starting from the menu still works.

## Tools

Every tool takes a ticket from `SessionController.openTicket()`, stamped with the session's audio time the moment
you start it, so a screenshot lands at the word you were saying when you pressed the key, not when you finished
dragging. A tool used while no session runs starts one. `AnnotationLedger` (`KoeCore`) holds the tickets: a session
you finish while a tool is open never waits for another click (`ToolCoordinator.sessionStopping`): what is picked
attaches with what you said, a clip still recording stops and attaches, and a clip in review attaches with the
frames picked so far.

- **Screenshot, ⌥⇧S while you dictate.** `ScreenFreezer` captures every screen with ScreenCaptureKit, leaving Koe's own windows out,
  and lists the windows on them front to back (CGWindowList). The overlay shows the frozen screens dimmed from the moment it opens,
  and clear where you drag or picked: drag a region, or click to take the window under the pointer. With "Freeze
  the screen while you pick" off (`KoeSettings.freezeScreen`) the overlay is clear glass over the live screen and
  the picture is taken when you attach. Nothing is drawn around windows: the pill names what the
  pointer is over. Once picked, the pill listens at once, as it does for a comment, and Return or a click anywhere attaches it (dragging picks again): what you say until you attach it
  (a `VoiceSpan`) becomes the screenshot's note. Return attaches, Esc cancels. The crop is saved at full resolution as `screenshot-<n>.png`; its source is
  the window you clicked, or the frontmost window under the region's centre.
- **Comment, ⌥⇧C while you dictate.** Agentation for the whole Mac: the screen freezes, you click anything, and the pill listens:
  what you say until you click its check is the comment. Clicking something else finishes that comment and starts
  the next one there (`RegionPicker.onCommit`), each on its own ticket. The pill's buttons keep the session's
  order: discard, pause, confirm; pause is the session's own pause, so the comment greys like the waveform does. The screenshot is the window you clicked (or 640 × 400
  around the spot when there is none) with a blue pin in a wide halo where you clicked, carrying the comment's number in the session (`PinMark`,
  `KoeCore`), and the bundle says it in words too ("at the blue pin numbered 2, 58% across and 60% down",
  `PinPlace`), so an agent that misses the dot still knows the spot. Each comment keeps its own picture: the screen
  as it was when you made it.
- **Comment on anything, ⌘⇧-click, dictating or not.** `ClickTrigger` watches for the click all the time: with no
  session it starts one, straight on the comment's page. `ToolCoordinator.quickComment` pictures the screen at that
  moment and draws what the comment tool draws (the dimmed screen, the window you clicked, the pins) on a window
  that lets every click and key through (`RegionPickerView` with `passive`), so you can move through pages and
  comment as you go. Return (held system-wide meanwhile), the pill's check or your next click anywhere adds it.
  Another ⌘⇧-click keeps the pins before it (`quickTrail`), and the new pin comes out from behind the last one, as
  in the comment tool. A plain click on the app under it fades everything away (`clickedElsewhere`) and forgets
  them, since the page they pointed at may have changed. With Accessibility allowed a click Koe takes is kept from the app under it (an event tap);
  without, the app gets it too. One Koe can't take (another tool is open, screen recording isn't allowed) goes on to
  the app. Browsers open a link in a new tab with ⌘⇧-click, so Settings has "Comment with ⇧⌘-click" to turn it off.
- A clip's recording page has no pause: the clip and its clock keep running, so pausing the audio would stamp the
  frames after it later than the words said as they showed.
- **Nothing is typed.** `BundleComposer.splitVoiceNotes` takes the words said inside each attachment's voice span out
  of the transcript and makes them its note, so `Look at this. [1: the padding is too tight] Next thing.`. A pause
  you spent talking about an attachment never breaks a paragraph.
- **The list.** The paperclip count beside the tools opens what the session holds (`AttachmentList`), to check each
  one, open a picture or clip larger with a click (a clip plays with its own controls: pause, a bar to drag, the speeds), and take any out (`SessionController.remove`). The viewer's card
  is as wide as its picture; pinch or double-click zooms and a drag pans. Previews are made as things are attached
  (`ThumbnailCache`), so the list never opens on a placeholder. A comment is a
  screenshot of what you clicked with a pin on the spot (`Annotation.comment`), named "Comment" there and in the
  bundle.
- **Clip, ⌥⇧R while you dictate.** macOS has no public way to slow other apps down, so Koe records instead and you slow the recording
  down. Pick a region as for a screenshot (the pick starts recording). `ClipRecorder` takes
  ScreenCaptureKit's frames at the screen's refresh rate and encodes them itself (`ClipQuality`: 0.08 bits a pixel
  a frame, 6 to 32 Mbit/s, H.264 or HEVC past 4096 × 2304), since `SCRecordingOutput` has no bit rate to set and
  its pictures were too soft to step through. With the pointer and without Koe's windows, to `clip-<n>.mov`. A dashed red outline shows around the region, and the pill becomes the recording's own page: its clock, discard (this clip only, the session carries on), pause and stop. R again,
  or stopping the session stops it; a clip has no length limit. Then the clip opens at 1× (`PlaybackSpeed`): play
  it at 1×, 0.5×, 0.25× or 0.1×, step with ← and → (⇧ for ten), scrub. Stepping stays in the review's own card, which has no buttons of its own for the clip. While it is open
  the pill names the frame on screen beside the live waveform, with discard, pick this frame (`ToolPrompt.extra`) and attach; it has no pause there. Picking a
  frame starts listening for its note at once: the pill shows the frame's time, its check (Return) keeps the note
  and its discard removes that frame. Return also stops a recording: Koe holds Return and Enter system-wide while a
  clip records (`ClipTool.stopKeys`), since none of its windows has the keys then. The row shows your words as they
  are heard (`SessionController.spoken(in:)`), with say it again and remove beside them. Return attaches, Esc
  discards. The scrubber runs from the first frame to the last (`ClipFrames.fraction`), so the right end is always
  the end, however long the clip holds its last frame.
- A screen recording only stores a frame when something changed, so `ClipMovie` reads the clip's real frame times
  (`ClipFrames`) and stepping goes from one change to the next. Seeks aim at the middle of a frame and frames are
  pulled with zero tolerance, so the image you pick is the one you saw.
- The clip is stamped when recording began, and each picked frame at that time plus its time in the clip, so a frame
  lands at the words you said while it was on screen. All of them close the ticket taken when you pressed R.
  Frames are saved full size as `clip-<n>-frame-<m>.png`.
- **Drop on the pill.** Each file is stamped when it lands and copied (an APFS clone) into the session's folder, so
  the bundle keeps it if the original moves. The pill shows how many attachments the session holds.
- Tool panels are non-activating: they take typing without bringing Koe to the front, so the app you were in keeps
  focus. Esc is caught with a local key monitor, because a text field turns it into completion before the window
  sees it.
- Each session is one folder, `~/Library/Application Support/Koe/Sessions/<date-time-id>/` (`SessionFolder`,
  `SessionArchive`), and holds everything about it:

  ```
  2026-11-10-143200-1A2B/
  ├── session.json     every word with its time, every attachment and note
  ├── transcript.md    the text exactly as it was copied
  ├── audio.caf        what you said
  └── attachments/     screenshot-1.png, clip-1.mov, clip-1-frame-25.png, spec.pdf
  ```

  Attachment names carry no spaces so a pasted path stays one word. Sessions saved before `attachments/` keep
  their files beside `session.json`; their paths are absolute, so they still open and paste.

## Notes

- Screen recording and Accessibility only report granted or not. Koe remembers whether it has asked
  (`asked.<permission>` in its defaults): before, a row offers the system prompt; after, it opens System Settings.
  macOS only applies a new screen recording grant once the app is reopened, so that row offers "Reopen Koe".
  The window checks again every second while it is open, since System Settings sends no notice.
- `defaults write studio.shinsa.koe appearance light|dark` pins a theme. `--setup` and `--settings` open the settings
  window at launch, and `--open-menu` the menu, for
  screenshots. `--audio-file <path>` plays a recording into each session
  instead of the microphone, `--start` starts one at launch, and `--print-session` prints the finished bundle text
  to stdout: `say -o /tmp/s.aiff "Look at this." && ./Koe.app/Contents/MacOS/Koe --audio-file /tmp/s.aiff --start
  --print-session`.
- `--script "<steps>"` plays tools into the session at audio times (`ScriptedStep`): `1.5 shot 120,80,640,360 A
  note; 3 pin 400,300 talk 2; 4 drop /tmp/spec.pdf; 6 clip 120,80,640,360 2 0.4,1.1` (records 2 s and picks
  the frames 0.4 s and 1.1 s in); `shot!`, `pin!` and `clip!` leave the tool open. `--backdrop <png>` shows that
  image instead of capturing your screen, so captures of Koe never show what's on your screen, and `--clip-file
  <mov>` stands in for every recorded clip (a scripted one still shows the recording outline for its length). A
  script needs a session, so pair it with `--start`.
- `-transcriptionModel parakeet-v3|parakeet-v2|whisper-large-v3-turbo|apple` at launch picks the model for that run.
  `--download <model>` starts that model's download, and `--snapshot <png>` draws the whole settings page into a
  PNG three seconds in, which works while the screen is locked.
