#!/bin/bash
# Runs a debug Koe for tests, out of your way: `--background` shows nothing, takes no shortcut, focus or clipboard,
# and its own home keeps its settings, sessions, models and Neural Engine cache apart from the installed Koe's.
#
#   scripts/sandbox.sh [--fresh] [--with-models] [Koe flags…]
#   scripts/sandbox.sh --with-models --snapshots /tmp/koe-shots --download whisper-large-v3-turbo
#   scripts/sandbox.sh --with-models --audio-file a.caf --start --print-session
#
# --fresh empties the sandbox and its settings first. --with-models clones your downloaded models into it (APFS
# clones: instant, no extra space), so a test doesn't download them again. Set KOE_SANDBOX to use another folder.
set -euo pipefail
cd "$(dirname "$0")/.."

SANDBOX="${KOE_SANDBOX:-${TMPDIR:-/tmp}/koe-sandbox}"
WITH_MODELS=0
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fresh) rm -rf "$SANDBOX"; defaults delete studio.overclock.koe.sandbox >/dev/null 2>&1 || true; shift ;;
    --with-models) WITH_MODELS=1; shift ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

SUPPORT="Library/Application Support/Koe"
mkdir -p "$SANDBOX/$SUPPORT"
if [[ $WITH_MODELS == 1 && -d "$HOME/$SUPPORT/Models" && ! -d "$SANDBOX/$SUPPORT/Models" ]]; then
  cp -cR "$HOME/$SUPPORT/Models" "$SANDBOX/$SUPPORT/Models"
  # The Neural Engine's compile of them too, when a debug Koe made one, so Whisper loads in seconds, not minutes.
  CACHE="Library/Caches/Koe"
  if [[ -d "$HOME/$CACHE" && ! -d "$SANDBOX/$CACHE" ]]; then mkdir -p "$SANDBOX/Library/Caches"; cp -cR "$HOME/$CACHE" "$SANDBOX/$CACHE"; fi
fi

swift build --product Koe >&2
echo "→ Koe in the background, home $SANDBOX" >&2
CFFIXED_USER_HOME="$SANDBOX" exec .build/debug/Koe --background ${ARGS[@]+"${ARGS[@]}"}
