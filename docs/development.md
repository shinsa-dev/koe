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
release is a GitHub release with `Koe.dmg`, copied to shinsa.dev under `koe/` with an appcast for its channel. Lint
(SwiftLint, actionlint, shellcheck) and Test (`swift test --filter KoeCoreTests`, the release script tests) run on
every pull request. [release.md](release.md) has the versions, the steps, the files on shinsa.dev and the secrets.

