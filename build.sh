#!/bin/bash
# Builds Koe.app. Pass --install to also copy it into /Applications and launch it.
# KOE_VERSION (such as 1.2.0 or 1.2.1-canary.3) and KOE_BUILD (a number that grows with every release, which Sparkle
# compares) stamp a release; without them the build is 0.0.0-dev, build 0, and only checks for updates when asked.
set -euo pipefail
cd "$(dirname "$0")"

APP="Koe.app"
VERSION="${KOE_VERSION:-0.0.0-dev}"
BUILD="${KOE_BUILD:-0}"
if ! [[ "$BUILD" =~ ^[0-9]+$ ]]; then
  echo "KOE_BUILD must be a whole number, not '$BUILD'." >&2
  exit 1
fi

echo "→ Compiling Koe $VERSION ($BUILD)…"
swift build -c release
PRODUCTS="$(swift build -c release --show-bin-path)"
BIN="$PRODUCTS/Koe"

echo "→ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Koe"
cp Resources/Info.plist "$APP/Contents/Info.plist"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$PLIST"
if [[ "$BUILD" == 0 ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$PLIST"
fi
mkdir -p "$APP/Contents/Frameworks"
ditto "$PRODUCTS/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp Resources/Koe.icns "$APP/Contents/Resources/Koe.icns"
# The icon is an Icon Composer bundle. actool compiles it into an Assets.car, which macOS 26 draws as layered
# glass; the committed Koe.icns stays as the fallback.
ICONTMP=$(mktemp -d)
if xcrun actool --compile "$ICONTMP" --app-icon Koe --platform macosx --minimum-deployment-target 26.0 \
  --output-partial-info-plist "$ICONTMP/partial.plist" "$PWD/Resources/Koe.icon" >/dev/null 2>&1 \
  && [ -f "$ICONTMP/Assets.car" ]; then
  cp "$ICONTMP/Assets.car" "$APP/Contents/Resources/Assets.car"
else
  echo "  (actool failed; using the committed Koe.icns)"
fi
rm -rf "$ICONTMP"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
cp -R Resources/Icons "$APP/Contents/Resources/Icons"
cp Resources/KoeMark.svg "$APP/Contents/Resources/KoeMark.svg"

# macOS ties the microphone, screen recording and Accessibility grants to the signature. An ad-hoc signature
# changes with every build, so System Settings would keep showing Koe as allowed while the new build is not.
# A real certificate keeps the grants across rebuilds: KOE_SIGN_IDENTITY, else the first Apple Development one.
# Every signed build runs under the hardened runtime, as notarization requires; a Developer ID one is also
# timestamped, so it can be notarized.
IDENTITY="${KOE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk '/Apple Development/ { print $2; exit }')}"
IDENTITY_NAME=""
if [[ -n "$IDENTITY" ]]; then
  IDENTITY_NAME="$(security find-identity -v -p codesigning | awk -v id="$IDENTITY" '$2 == id || index($0, id) { $1=""; $2=""; print; exit }' | sed 's/^ *//; s/"//g')"
fi
TIMESTAMP="--timestamp=none"
if [[ "$IDENTITY_NAME" == "Developer ID Application"* ]]; then TIMESTAMP="--timestamp"; fi

# Sparkle's helpers are signed inside out, each with Koe's identity, as Sparkle's own guide does.
sign_app() {
  local sign=(codesign --force --sign "$1" --options runtime "$2")
  local sparkle="$APP/Contents/Frameworks/Sparkle.framework"
  "${sign[@]}" "$sparkle/Versions/B/XPCServices/Installer.xpc" &&
    "${sign[@]}" --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc" &&
    "${sign[@]}" "$sparkle/Versions/B/Autoupdate" &&
    "${sign[@]}" "$sparkle/Versions/B/Updater.app" &&
    "${sign[@]}" "$sparkle" &&
    "${sign[@]}" --entitlements Resources/Koe.entitlements "$APP"
}

if [[ -n "$IDENTITY" ]] && sign_app "$IDENTITY" "$TIMESTAMP" >/dev/null 2>&1; then
  echo "→ Signed with $IDENTITY_NAME"
elif [[ "$IDENTITY_NAME" == "Developer ID Application"* || -n "${KOE_SIGN_IDENTITY:-}" ]]; then
  echo "Could not sign with ${IDENTITY_NAME:-$IDENTITY}." >&2
  sign_app "$IDENTITY" "$TIMESTAMP"
  exit 1
else
  sign_app - --timestamp=none >/dev/null 2>&1 || true
  echo "  (no signing certificate found, so ad-hoc signed: permissions reset on each rebuild)"
fi

if [[ "${1:-}" == "--install" ]]; then
  echo "→ Installing to /Applications…"
  osascript -e 'quit app "Koe"' >/dev/null 2>&1 || true
  sleep 1
  # A grant made for an ad-hoc build stays pinned to that build's hash: System Settings shows Koe as allowed, but no
  # later build matches it, and toggling it keeps the old hash. Coming from such a build, clear Koe's grants once.
  if [[ -d "/Applications/$APP" ]] && ! codesign -d -r- "/Applications/$APP" 2>&1 | grep -q "certificate leaf"; then
    echo "→ Clearing permissions left by an ad-hoc build…"
    for SERVICE in ScreenCapture Accessibility Microphone; do tccutil reset "$SERVICE" studio.shinsa.koe >/dev/null 2>&1 || true; done
    defaults delete studio.shinsa.koe asked.screenRecording >/dev/null 2>&1 || true
    defaults delete studio.shinsa.koe asked.accessibility >/dev/null 2>&1 || true
  fi
  rm -rf "/Applications/$APP"
  cp -R "$APP" "/Applications/$APP"
  open "/Applications/$APP"
  echo "✓ Koe is running in the menu bar."
else
  echo "✓ Built ./$APP. Run ./build.sh --install to put it in /Applications."
fi
