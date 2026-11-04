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
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
cp -R Resources/Icons "$APP/Contents/Resources/Icons"

# Ad-hoc signed: macOS ties the microphone and screen recording grants to the signature, so an unsigned
# build would ask again on every rebuild.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
  echo "  (ad-hoc signing failed; the app will still run)"

if [[ "${1:-}" == "--install" ]]; then
  echo "→ Installing to /Applications…"
  osascript -e 'quit app "Koe"' >/dev/null 2>&1 || true
  sleep 1
  rm -rf "/Applications/$APP"
  cp -R "$APP" "/Applications/$APP"
  open "/Applications/$APP"
  echo "✓ Koe is running in the menu bar."
else
  echo "✓ Built ./$APP. Run ./build.sh --install to put it in /Applications."
fi
