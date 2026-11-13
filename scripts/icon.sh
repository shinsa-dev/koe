#!/bin/bash
# usage: scripts/icon.sh: renders Resources/Koe.svg (Shinsa's tile and mark language, with Koe's blue dot) into
# Resources/Koe.icns. Needs rsvg-convert (brew install librsvg).
set -euo pipefail
cd "$(dirname "$0")/.."
SET=$(mktemp -d)/Koe.iconset
mkdir -p "$SET"
for base in 16 32 128 256 512; do
  rsvg-convert -w "$base" Resources/Koe.svg -o "$SET/icon_${base}x${base}.png"
  rsvg-convert -w $((base * 2)) Resources/Koe.svg -o "$SET/icon_${base}x${base}@2x.png"
done
iconutil -c icns "$SET" -o Resources/Koe.icns
echo "→ Resources/Koe.icns"
