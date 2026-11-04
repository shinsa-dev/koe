#!/bin/bash
# Builds Koe.app. Pass --install to also copy it into /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

APP="Koe.app"

echo "→ Compiling…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Koe"

echo "→ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Koe"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Koe.icns "$APP/Contents/Resources/Koe.icns"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"

# macOS ties the microphone, screen recording and Accessibility grants to the signature. An ad-hoc signature
# changes with every build, so System Settings would keep showing Koe as allowed while the new build is not.
# A real certificate keeps the grants across rebuilds: KOE_SIGN_IDENTITY, else the first Apple Development one.
IDENTITY="${KOE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk '/Apple Development/ { print $2; exit }')}"
if [[ -n "$IDENTITY" ]] && codesign --force --sign "$IDENTITY" --timestamp=none "$APP" >/dev/null 2>&1; then
  echo "→ Signed with $(security find-identity -v -p codesigning | awk -v id="$IDENTITY" '$2 == id { $1=""; $2=""; print; exit }' | sed 's/^ *//')"
else
  codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true
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
