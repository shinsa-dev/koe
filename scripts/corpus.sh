#!/bin/bash
# Makes a reference corpus for `Koe --bench --refine`: each passage below is spoken by one of the Mac's voices, set to a
# speech level the way a microphone hears it (quiet -40, normal -28, loud -18 dBFS RMS of the voiced stretches), laid
# over the same faint room noise, and saved as `<level>-<nn>/audio.caf` beside a `reference.txt` with its words.
# Nothing leaves the Mac: `say` speaks offline, and the corpus lives outside the repository.
#
#   scripts/corpus.sh [folder]        (default ~/Library/Caches/Koe/Corpus)
#   .build/debug/Koe --bench --refine [--gain off] ~/Library/Caches/Koe/Corpus/*/audio.caf
set -euo pipefail

OUT="${1:-$HOME/Library/Caches/Koe/Corpus}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

VOICES=("Samantha" "Daniel" "Reed (English (US))" "Flo (English (US))" "Shelley (English (UK))" "Eddy (English (US))")
PASSAGES=(
  "Okay so the settings window should open on the models card first. If nothing is downloaded yet, start the download right away and show the progress bar."
  "Can you look at why the pill flickers when I switch spaces? I think the panel loses its level when the window server reorders everything."
  "Let's rename the function to refresh tokens and move it into the session controller. Then write a test that covers the expired case."
  "The deploy failed again on the staging server. Check the logs from this morning and tell me which migration timed out."
  "I want the button on the right to be a ghost button, not a filled one. Keep the same height as the switch next to it."
  "Remember to pick up milk and bread on the way home, and call the dentist before five to move the appointment to next week."
  "This paragraph reads a little stiff. Make it shorter, keep the first sentence, and drop the part about the history of the project."
  "When the user drags a file onto the window, copy it into the attachments folder and add a row at the top of the list."
  "Please review the pull request for the payment flow. I'm mostly worried about the retry logic and what happens when the webhook arrives twice."
  "The waveform barely moves when I talk normally. Turn the input up so quiet speech fills the bars, but make sure loud speech never clips."
)
LEVELS=("quiet:-40" "normal:-28" "loud:-18")

mkdir -p "$OUT"
for index in "${!PASSAGES[@]}"; do
  text="${PASSAGES[$index]}"
  voice="${VOICES[$((index % ${#VOICES[@]}))]}"
  number="$(printf '%02d' $((index + 1)))"
  say -v "$voice" --file-format=WAVE --data-format=LEI16@16000 -o "$WORK/voice.wav" "$text"
  for level in "${LEVELS[@]}"; do
    name="${level%%:*}"
    folder="$OUT/$name-$number"
    mkdir -p "$folder"
    python3 -I - "$WORK/voice.wav" "$WORK/clip.wav" "${level##*:}" "$index" <<'EOF'
import array, math, random, sys, wave

source, target, level, seed = sys.argv[1], sys.argv[2], float(sys.argv[3]), int(sys.argv[4])
with wave.open(source) as file:
    rate = file.getframerate()
    voice = [s / 32768 for s in array.array("h", file.readframes(file.getnframes()))]

# The level of the voiced stretches: 10 ms blocks within 30 dB of the loudest one.
block = rate // 100
energies = [sum(s * s for s in voice[i:i + block]) / block for i in range(0, len(voice) - block, block)]
loudest = max(energies)
voiced = [e for e in energies if e > loudest / 1000]
scale = 10 ** (level / 20) / math.sqrt(sum(voiced) / len(voiced))

# Room noise at -62 dBFS, softened a little as a microphone's self noise is, and the same for every clip of a passage.
noise = random.Random(seed)
lead, tail = int(0.6 * rate), int(0.8 * rate)
signal = [0.0] * lead + [s * scale for s in voice] + [0.0] * tail
floor = 10 ** (-62 / 20) * math.sqrt(3)
smooth = 0.0
out = array.array("h")
for sample in signal:
    smooth = 0.6 * smooth + 0.4 * noise.uniform(-1, 1)
    value = sample + floor * smooth * 1.6
    out.append(max(-32767, min(32767, round(value * 32767))))
with wave.open(target, "wb") as file:
    file.setnchannels(1)
    file.setsampwidth(2)
    file.setframerate(rate)
    file.writeframes(out.tobytes())
EOF
    afconvert -f caff -d LEF32@16000 -c 1 "$WORK/clip.wav" "$folder/audio.caf"
    printf '%s\n' "$text" > "$folder/reference.txt"
  done
done
echo "Wrote $(( ${#PASSAGES[@]} * ${#LEVELS[@]} )) clips to $OUT"
