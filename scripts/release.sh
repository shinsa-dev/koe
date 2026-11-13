#!/bin/bash
# The steps of a Koe release, one per command, as the Release workflow runs them (docs/release.md):
#   release.sh keychain                    imports CSC_LINK into a keychain of its own, prints the identity
#   release.sh notarize <Koe.app>          notarizes and staples the app
#   release.sh dmg <Koe.app> <version>     packs Koe.dmg beside an Applications link, signs it, staples when signed
#   release.sh verify <Koe.app> <version>  checks the version, bundle id and signature
#   release.sh update <dmg> <version> <build>  signs the DMG for Sparkle, writes update.json
#   release.sh upload <dir> <version>      copies the DMG, pointers and appcasts to R2 under koe/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="studio.shinsa.koe"
BUCKET="shinsa-releases"
R2_ACCOUNT_ID="e8563b02f2bf2b6a136f2781445a486f"
R2_ENDPOINT="https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com"

fail() {
  echo "::error title=Release::$1" >&2
  exit 1
}

need() {
  for name in "$@"; do
    [[ -n "${!name:-}" ]] || fail "Set $name (docs/release.md → Secrets)."
  done
}

# Apple's services drop connections now and then; a step that talks to them gets five tries.
retry() {
  local attempt=1 delay=15
  until "$@"; do
    ((attempt >= 5)) && return 1
    echo "::warning::Try $attempt of $* failed; again in ${delay}s." >&2
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}

keychain() {
  need CSC_LINK CSC_KEY_PASSWORD
  local keychain="$RUNNER_TEMP/koe-signing.keychain-db" password certificate
  password="$(uuidgen)"
  certificate="$RUNNER_TEMP/koe-signing.p12"
  printf '%s' "$CSC_LINK" | base64 --decode >"$certificate"
  security create-keychain -p "$password" "$keychain"
  security set-keychain-settings -lut 21600 "$keychain"
  security unlock-keychain -p "$password" "$keychain"
  security import "$certificate" -k "$keychain" -P "$CSC_KEY_PASSWORD" -T /usr/bin/codesign
  security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
  # shellcheck disable=SC2046
  security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')
  rm -f "$certificate"
  security find-identity -v -p codesigning "$keychain" | awk '/Developer ID Application/ { print $2; exit }'
}

submit() {
  xcrun notarytool submit "$1" --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" --wait --output-format json
}

notarize() {
  need APPLE_ID APPLE_APP_SPECIFIC_PASSWORD APPLE_TEAM_ID
  local target="$1" archive="$1" result status id
  if [[ "$target" == *.app ]]; then
    archive="$RUNNER_TEMP/$(basename "$target" .app).zip"
    ditto -c -k --sequesterRsrc --keepParent "$target" "$archive"
  fi
  result="$(retry submit "$archive")"
  status="$(plutil -extract status raw -o - - <<<"$result")"
  id="$(plutil -extract id raw -o - - <<<"$result")"
  if [[ "$status" != Accepted ]]; then
    xcrun notarytool log "$id" --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" || true
    fail "Apple did not notarize $(basename "$target") ($status, submission $id); its log is above."
  fi
  retry xcrun stapler staple "$target"
  echo "Notarized and stapled $target (submission $id)."
}

dmg() {
  local app="$1" version="$2" output="${3:-Koe.dmg}" stage
  stage="$(mktemp -d)"
  ditto "$app" "$stage/Koe.app"
  ln -s /Applications "$stage/Applications"
  rm -f "$output"
  hdiutil create -volname "Koe $version" -srcfolder "$stage" -fs APFS -format ULFO -ov "$output" >/dev/null
  rm -rf "$stage"
  if [[ -n "${KOE_SIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$KOE_SIGN_IDENTITY" --timestamp "$output"
    notarize "$output"
  fi
  echo "Packed $output."
}

verify() {
  local app="$1" version="$2" plist="$1/Contents/Info.plist" bundled identifier
  bundled="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
  identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
  [[ "$bundled" == "$version" ]] || fail "Koe.app says $bundled, but the release is $version."
  [[ "$identifier" == "$BUNDLE_ID" ]] || fail "Koe.app is $identifier, not $BUNDLE_ID: it would not update in place."
  [[ -d "$app/Contents/Frameworks/Sparkle.framework" ]] || fail "Koe.app has no Sparkle.framework, so it could never update."
  codesign --verify --deep --strict "$app"
  if [[ -n "${KOE_SIGN_IDENTITY:-}" ]]; then
    retry spctl --assess --type execute "$app"
    retry xcrun stapler validate "$app"
  fi
  echo "Koe.app is $version ($identifier), signed and intact."
}

update() {
  need SPARKLE_PRIVATE_KEY
  local file="$1" version="$2" build="$3" signature length
  local signer="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"
  [[ -x "$signer" ]] || fail "No $signer: build Koe first, which fetches Sparkle and its tools."
  signature="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$signer" --ed-key-file - -p "$file")"
  length="$(stat -f %z "$file")"
  cat >"$(dirname "$file")/update.json" <<EOF
{"version": "$version", "build": $build, "length": $length, "edSignature": "$signature", "publishedAt": "$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"}
EOF
  echo "Signed $file for Sparkle: $length bytes."
}

r2() {
  aws s3 "$@" --endpoint-url "$R2_ENDPOINT" --region auto --only-show-errors
}

upload() {
  need CLOUDFLARE_API_TOKEN
  local directory="$1" version="$2" answer channel channels sha size
  # R2's S3 keys come from the API token: its id is the access key and its SHA-256 the secret, as in Shinsa.
  answer="$(curl --fail --silent --show-error --retry 4 -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    "https://api.cloudflare.com/client/v4/accounts/$R2_ACCOUNT_ID/tokens/verify")" \
    || fail "Could not verify CLOUDFLARE_API_TOKEN."
  AWS_ACCESS_KEY_ID="$(jq -er '.result.id' <<<"$answer")" || fail "CLOUDFLARE_API_TOKEN is not an active token of the account."
  AWS_SECRET_ACCESS_KEY="$(printf '%s' "$CLOUDFLARE_API_TOKEN" | shasum -a 256 | cut -d' ' -f1)"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

  echo '{}' >"$directory/pointers.json"
  for channel in stable beta canary; do
    if r2 cp "s3://$BUCKET/koe/channels/$channel.json" "$directory/current-$channel.json" 2>/dev/null; then
      jq --arg channel "$channel" --slurpfile pointer "$directory/current-$channel.json" \
        '.[$channel] = $pointer[0].version' "$directory/pointers.json" >"$directory/pointers.next"
      mv "$directory/pointers.next" "$directory/pointers.json"
    fi
  done
  channels="$(python3 "$ROOT/scripts/release_version.py" channels "$version" "$directory/pointers.json")"

  sha="$(shasum -a 256 "$directory/Koe.dmg" | cut -d' ' -f1)"
  size="$(wc -c <"$directory/Koe.dmg" | tr -d ' ')"
  r2 cp "$directory/Koe.dmg" "s3://$BUCKET/koe/releases/$version/Koe.dmg" --content-type application/x-apple-diskimage
  python3 "$ROOT/scripts/release_version.py" pointer "$version" "$size" "$sha" >"$directory/pointer.json"
  python3 "$ROOT/scripts/release_version.py" appcast "$directory/update.json" >"$directory/appcast.xml"
  for channel in $channels; do
    r2 cp "$directory/pointer.json" "s3://$BUCKET/koe/channels/$channel.json" --content-type application/json
    r2 cp "$directory/appcast.xml" "s3://$BUCKET/koe/appcast/$channel.xml" --content-type application/xml
  done
  echo "Uploaded Koe $version; it now leads: ${channels:-no channel, as each has a newer release}."
}

command="${1:-}"
shift || true
case "$command" in
  keychain) keychain ;;
  notarize) notarize "$@" ;;
  dmg) dmg "$@" ;;
  verify) verify "$@" ;;
  update) update "$@" ;;
  upload) upload "$@" ;;
  *) sed -n '2,8p' "$0" >&2; exit 2 ;;
esac
