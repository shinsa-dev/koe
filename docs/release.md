# Releasing Koe

Koe ships the way Shinsa does (`shinsa/docs/release.md`): a release is a GitHub release of `shinsa-dev/koe` built by
the Release workflow (`.github/workflows/release.yml`), and nothing is bumped in the code, since the version lives in
the tag. There are two channels: **Stable**, cut by hand on GitHub, and **Canary**, built from every merge to `main` that passes the
tests. There is no beta. Both are the same app (`studio.shinsa.koe`), so Settings → Updates switches between them
and Koe updates itself in place with Sparkle, keeping its settings, sessions and model.

## Cutting a release

Create the release on GitHub, in the web or with the CLI:

```sh
gh release create v1.3.0 -R shinsa-dev/koe --generate-notes
```

Publishing a release that is not a pre-release starts the Release workflow at its tag's commit. It builds, signs and
notarizes that commit, attaches `Koe.dmg` and `update.json` to your release (its title and notes stay yours), then
copies it to shinsa.dev and moves the stable appcast. The tag must be `vX.Y.Z` and above every stable release that
already has `Koe.dmg`; anything else fails the run before it builds. While the run takes its fifteen minutes, GitHub
shows the release without files; the appcast moves only once the build succeeds.

To build an existing release again, after a failed run or for a release made before this trigger existed:

```sh
gh workflow run release.yml -R shinsa-dev/koe -f tag=v1.3.0
```

A canary needs no run: every merge to `main` whose Test workflow passes makes one, unless it only changed docs
(`*.md`, `docs/`, `.claude/`). `gh workflow run release.yml -f channel=canary` makes one of the current `main` by
hand. `gh workflow run release.yml -f channel=stable -f bump=minor` still makes a stable release with a bumped
version and its own release, without a tag of yours.

| Input | Values | Default |
|---|---|---|
| `channel` | `stable`: a GitHub release marked latest. `canary`: a pre-release of `main` | `stable` |
| `bump` | `patch`, `minor` or `major`: which part of the **last stable** version goes up; a canary ignores it | `patch` |
| `tag` | An existing stable tag such as `v1.3.0`, built onto its release instead of bumping; needs `channel=stable` | empty |

## Versions

`scripts/release_version.py` holds the rules, tested in `scripts/test_release_version.py`:

- A release made on GitHub is its tag: `v1.3.0` is `1.3.0` (`release_version.py tagged`). Only releases with
  `Koe.dmg` count as shipped, so one made by hand and never built is not the version to beat, and a tag can be built
  again to retry.
- Stable by `bump` is the last stable version bumped: `1.2.0` → `1.2.1`, `1.3.0` or `2.0.0`.
- Canary is the next patch after the newest stable, with `-canary.N`.
- The build number (`CFBundleVersion`, which Sparkle compares) is the workflow's run number, so every release on any
  channel is above every one before it. The version string is what Koe shows.

## What a run does

1. `trigger` (Ubuntu) decides whether to build and which commit. A published release, or a run with `tag`, builds
   that tag's commit as stable, with its version from `release_version.py tagged` (pre-releases and releases the
   workflow made itself start nothing). Any other run by hand always builds; after a merge,
   `release_version.py canary` builds only when something but docs changed since the last canary.
2. `mac` (macOS 26 with Xcode 26.3, as FluidAudio 0.9 fails to compile on 26.4 and later) marks the commit's
   `Release` status pending, works out the version, and runs the signing preflight: all six secrets set is a
   **signed** release, none set an **unsigned** one, and some but not all fails the run naming the missing ones.
   Then, through `scripts/release.sh`:
   - `keychain` imports `CSC_LINK` into a keychain of its own and finds the Developer ID Application identity.
   - `./build.sh` with `KOE_VERSION`, `KOE_BUILD` and `KOE_SIGN_IDENTITY` builds, embeds Sparkle and signs everything
     under the hardened runtime, timestamped.
   - `notarize Koe.app` submits it to Apple and staples the ticket, five tries each.
   - `verify` checks the version, the bundle id, that Sparkle is inside and the signature (`spctl` and the stapled
     ticket when signed).
   - `dmg` packs `Koe.dmg` with `dmgbuild` (see [The disk image](#the-disk-image)), signs and notarizes it.
   - `update` signs the DMG with Sparkle's EdDSA key and writes `update.json`: version, build, length, signature.
   - It attaches `Koe.dmg` and `update.json` to the tag's release when there is one. Otherwise it publishes the
     release: a one-line channel note, then GitHub's generated list of pull requests (since the last stable for a
     stable, the last canary for a canary).
3. `downloads` (Ubuntu, signed releases only) copies the release to the `shinsa-releases` R2 bucket that serves
   shinsa.dev (`release.sh upload`). It is its own job, so Re-run failed jobs retries only the copy.
4. `status` reports the outcome on the commit as the `Release` status, so a failed release turns it red.

## The disk image

`Koe.dmg` opens like Shinsa's installer: a 660×432 window with no toolbar or sidebar, Koe at (180, 196) and an
Applications link at (480, 196), both at 112 pt, over a drawn background. `scripts/dmg_settings.py` holds that
layout for `dmgbuild` (pinned in the workflow; locally `pip install dmgbuild`, or point `DMGBUILD` at it), and
`release.sh dmg` picks the channel's background, so a canary shows a Canary pill beside the name. `dmgbuild` joins
the 1x and 2x PNGs into one HiDPI TIFF, so it stays sharp on Retina screens.

The backgrounds are committed in `Resources/DMG`. `scripts/dmg.py` draws them, a port of Shinsa's
`apps/desktop/scripts/dmg-background.ts` with Koe's mark and ABC Areal: run it after changing the mark, the copy or the
icon positions (keep `ICON` in it and `icon_locations` in the settings together). It needs `rsvg-convert`
(`brew install librsvg`) and fontTools. To see a disk image without a release:

```sh
./build.sh && scripts/release.sh dmg Koe.app 0.0.0-dev canary /tmp/Koe.dmg && open /tmp/Koe.dmg
```

## On shinsa.dev

Everything lives under `koe/` in the bucket, beside Shinsa's own files, and nothing is ever deleted:

| Key | What |
|---|---|
| `koe/releases/<version>/Koe.dmg` | Every release's disk image |
| `koe/channels/<channel>.json` | The channel's download: `version`, `key`, `size`, `sha256`, `publishedAt`, as Shinsa's |
| `koe/appcast/<channel>.xml` | The channel's Sparkle appcast: one item, the release |

A release moves only its own channel, and no channel ever goes back to an older version (`release_version.py channels`). The site serves these at `https://shinsa.dev/koe`:
`/koe/download` redirects to the stable DMG (the newest canary while there is no stable) and `/koe/download/canary`
to the canary one, `/koe/appcast/<channel>.xml` is what Koe's
`Updater` reads, and `/koe/releases/<version>/Koe.dmg` is the appcast's enclosure. Those routes are the shinsa
repository's (`apps/marketing`).

An unsigned release reaches GitHub only: Sparkle installs only updates signed with Koe's key, and Gatekeeper would
stop a download from the site, so no channel offers it.

## Secrets

Set on `shinsa-dev/koe` (Settings → Secrets and variables → Actions). The first five are the ones Shinsa's release
uses, under the same names.

| Secret | What |
|---|---|
| `CSC_LINK` | The Developer ID Application certificate and key, a `.p12` in base64 |
| `CSC_KEY_PASSWORD` | Its password |
| `APPLE_ID` | The Apple ID that notarizes |
| `APPLE_APP_SPECIFIC_PASSWORD` | An app-specific password for it |
| `APPLE_TEAM_ID` | The team of the certificate |
| `SPARKLE_PRIVATE_KEY` | Sparkle's EdDSA private key, whose public half is `SUPublicEDKey` in `Resources/Info.plist` |
| `CLOUDFLARE_API_TOKEN` | A token with R2 write access to `shinsa-releases` |

The Sparkle key lives in the login keychain under the account `studio.shinsa.koe`. Export it once into the secret:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account studio.shinsa.koe -x sparkle-key.txt
gh secret set SPARKLE_PRIVATE_KEY -R shinsa-dev/koe < sparkle-key.txt && rm sparkle-key.txt
```

Losing it means no installed Koe can update again, so keep it in the password manager too. Never generate a new one
for an existing release line.

## Cost

`shinsa-dev/koe` is public, so its Actions minutes, macOS ones included, are free. A
release run takes about fifteen minutes, mostly notarization; the Test workflow about five.
