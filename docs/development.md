# Developing Koe

How Koe is built, signed, updated and released. What Koe does and how it is drawn is [design.md](design.md); cutting a
release is [release.md](release.md).

## Build

Needs macOS 26 and Xcode 26 or later (Swift 6.2).

```sh
./build.sh            # builds ./Koe.app
./build.sh --install  # copies it into /Applications and launches it
KOE_VERSION=1.2.0 KOE_BUILD=42 ./build.sh  # stamps a release's version and build number
swift test            # KoeCore's unit tests
.build/debug/Koe --bench  # replays your newest recordings and scores how often their endings are complete
.build/debug/Koe --bench --model whisper-large-v3-turbo 3  # the same with another model, newest three recordings
```

`scripts/sandbox.sh` runs a debug Koe for tests without getting in your way: `--background` leaves out the menu bar
item, windows, the pill, shortcuts, ⌘⇧-click, the clipboard, media pausing and updates, and never takes focus. It runs
in its own home (`$TMPDIR/koe-sandbox`, or `KOE_SANDBOX`) with its own settings, so it never touches the installed
Koe's sessions, models or preferences.

```sh
scripts/sandbox.sh --fresh --snapshots /tmp/shots   # no models: watch Koe download Fluid Speech Pro, then Whisper
scripts/sandbox.sh --with-models --audio-file session.caf --start --print-session
```

`--snapshots <folder>` draws the settings page into the folder each time it changes and prints which model runs and
each model's install state when that changes. Koe downloads its models by itself; `--download <model>` brings back
one you deleted.

There is no Xcode project: SwiftPM builds the binary and `build.sh` assembles and signs the app. It signs with
`KOE_SIGN_IDENTITY` or the first Apple Development certificate in your keychain, so macOS keeps Koe's permissions
across rebuilds; without one it signs ad hoc and the permissions reset on every build. The icon is an Icon Composer
bundle, `Resources/Koe.icon` (two glass layers, the mark and the blue dot, on a light tile with a dark variant);
`build.sh` compiles it with `actool` into `Assets.car`. `scripts/icon.sh` renders `Resources/Koe.svg` into
`Resources/Koe.icns`, the fallback when `actool` fails.

Every signed build runs under the hardened runtime with `Resources/Koe.entitlements` (audio input), and a Developer
ID one is timestamped too, so it can be notarized. `build.sh` embeds Sparkle in `Contents/Frameworks` and signs its
helpers inside out with the same identity. Without `KOE_VERSION` and `KOE_BUILD` a build is `0.0.0-dev`, build `0`:
a development build that checks for updates only when you ask, so it never replaces itself.

Signing with a different certificate (a Developer ID build next to your Apple Development one) is a different app to
macOS: running it can drop the microphone grant of the other, so allow it again in Settings afterward.

## Updates

Koe updates itself with Sparkle 2 (`Updater`). Each channel, Stable and Canary, has its own appcast at
`https://shinsa.dev/koe/appcast/<channel>.xml` (`UpdateChannel`), and Sparkle installs an update only when it is
signed with the EdDSA key whose public half is `SUPublicEDKey` in `Info.plist`. The private half lives in the login
keychain under the account `studio.shinsa.koe` (Sparkle's `generate_keys --account studio.shinsa.koe`), Koe's id
before it became `studio.overclock.koe`: the account is only the key's label, so it keeps that name. For the Release
workflow it also lives in a repository secret. Settings → Updates picks the channel; until you pick one, Koe follows the
channel of the build you installed (`1.2.1-canary.3` is a canary). Sparkle never goes back a version, so moving from
Canary to Stable waits for the next stable release. A release build checks once a day, and Check now checks at once.

## Releases

The Release workflow builds, signs, notarizes and publishes Koe, as Shinsa's does: every tested merge to `main` is a
canary, and stable releases run from Actions → Release (`gh workflow run release.yml -f channel=stable`). Koe has
no beta channel. Each
release is a GitHub release with `Koe.dmg`, copied to shinsa.dev under `koe/` with an appcast for its channel. [CI](#ci) gates
every merge, and [release.md](release.md) has the versions, the steps, the files on shinsa.dev and the secrets.

## CI

Every pull request, every push to `main` and every merge queue run starts four jobs side by side, on GitHub's own
runners; none waits on another, and none is skipped for the paths a change touches, so a required check never hangs:

| Workflow | Job | Runner | What it runs | Budget |
|---|---|---|---|---|
| Lint | `lint` | `ubuntu-24.04` | SwiftLint 0.65.1 `--strict`, actionlint, shellcheck on `build.sh` and `scripts/*.sh` | 25 s |
| Test | `core` | `macos-26` | `KOE_CORE_ONLY=1 swift test`: KoeCore and its tests alone, from the newest build tree `main` saved | 35 s |
| Test | `app` | `macos-26` | `swift build` of the whole app, from the newest build tree `main` saved | 35 s |
| Test | `scripts` | `ubuntu-latest` | `python3 -m unittest discover -s scripts -p 'test_*.py'` | 15 s |

- **Budgets.** Each job's last step, `scripts/ci-budget.sh <seconds>`, reads the age of the job's `Runner.Worker`
  process, which the runner starts when it takes the job, and fails the job when it ran longer than its budget, naming
  both times. Time in the queue does not count; setup does. A slow job is a bug to find, never a budget to raise.
- **Build trees.** Every push to `main` saves each macOS job's build tree under a key of the job, the Xcode and the
  commit (`app` adds `Package.resolved`), and a pull request restores the newest one. A checkout stamps every file
  with the time it wrote it, and Swift rebuilds any file whose time differs from the one it built, so before building
  `scripts/ci_source_times.py` gives each tracked file a time made from its content (its git blob id): an unchanged
  file gets the time `main`'s build saw and is skipped, and a changed one gets another time and compiles again, with
  what depends on it. Until `main` has saved a tree, the job builds from scratch.
- **`core`.** With `KOE_CORE_ONLY` set, `Package.swift` declares only `KoeCore` and `KoeCoreTests`, with no packages
  to fetch or build. CI runs it without `--disable-automatic-resolution`, since with that flag SwiftPM fetches every
  package pinned in `Package.resolved`; without it, SwiftPM drops the file from the throwaway checkout. Locally, keep
  the file with `KOE_CORE_ONLY=1 swift test --disable-automatic-resolution --scratch-path .build/core`, and the
  scratch path keeps your app build apart.
- **`app`.** Its tree leaves out the packages' git mirrors (`.build/repositories`, about half of it): FluidAudio,
  WhisperKit and Sparkle come checked out and built. Both macOS jobs build with Xcode 26.3,
  the compiler releases use, until Koe moves to FluidAudio 0.13 (FluidInference/FluidAudio#415).
- **Lint.** SwiftLint and actionlint are downloaded from their releases and checked against the SHA-256 sums in
  `lint.yml`. SwiftLint is the dynamic Linux build on the runner's Swift: the static build cannot load SourceKit and
  quietly skips the rules that need it, so the step fails when SwiftLint reports a skipped rule. That build links
  `libxml2.so.2`, which Ubuntu 26.04 dropped, so `lint` stays on `ubuntu-24.04`. Each linter runs even when another
  fails, so one run lists every failure.
- **No retries.** A test that fails sometimes has a bug: the dictionary's speed test counts the comparisons
  `CustomDictionary.apply` makes (`comparisons(_:)`) instead of timing it, as a wall clock on a shared runner is noise.

Before this layout, from the last 100 runs (14 to 21 November 2026), at p50/p95: Test took 80/108 s per pull request,
its single macOS job 76/101 s (a 714 MB cache restore of 18/24 s that never refreshed, and a rebuild of the whole app
for 0.4 s of tests); Lint took 20/24 s, half of it starting the SwiftLint container. It failed 2 of 40 runs: once the
5 ms timing test, once a real compile error.

`main` is protected by the ruleset in `.github/rulesets/main.json`: no deletion or force push, changes through a pull
request, and the four jobs required on a branch that is up to date with `main`, so the full suite has run on exactly
what merges. The workflows also run on `merge_group`, so a merge queue can replace the up-to-date rule later. Apply the
ruleset once, or update it after changing the file:

```sh
gh api -X POST repos/shinsa-dev/koe/rulesets --input .github/rulesets/main.json
gh api -X PUT repos/shinsa-dev/koe/rulesets/<id> --input .github/rulesets/main.json  # <id> from gh api repos/shinsa-dev/koe/rulesets
```

A new job joins the table above, `.github/rulesets/main.json` and its budget step together.
