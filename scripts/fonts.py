#!/usr/bin/env python3
# usage: scripts/fonts.py: writes Resources/Fonts from the ABC Areal variable fonts in shinsa's packages/ui
# Needs fontTools and brotli (pip install fonttools brotli).
import io
import os
import subprocess

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.environ.get("SHINSA_REPO", os.path.expanduser("~/Developer/Projects/shinsa"))
REF = os.environ.get("SHINSA_REF", "origin/main")
OUT = os.path.join(ROOT, "Resources/Fonts")
# The web's weights: normal 400, medium 450, semibold 550, bold 600 (globals.css → --font-weight-*).
FONTS = {
    "ABCArealVariable": ("ShinsaAreal", [400, 450, 550, 600]),
    "ABCArealMonoVariable": ("ShinsaArealMono", [400, 500]),
}


def source(name):
    path = f"packages/ui/src/styles/fonts/{name}.woff2"
    return io.BytesIO(subprocess.check_output(["git", "-C", REPO, "show", f"{REF}:{path}"]))


def rename(font, family, weight):
    style = f"W{weight}"
    names = font["name"]
    for record in list(names.names):
        if record.nameID in (1, 2, 3, 4, 6, 16, 17, 25):
            names.removeNames(nameID=record.nameID)
    names.setName(family, 1, 3, 1, 0x409)
    names.setName(style, 2, 3, 1, 0x409)
    names.setName(f"{family}-{style}", 3, 3, 1, 0x409)
    names.setName(f"{family} {style}", 4, 3, 1, 0x409)
    names.setName(f"{family}-{style}", 6, 3, 1, 0x409)
    font["OS/2"].usWeightClass = weight


# The web sets every line at letter-spacing -0.02em (globals.css → body), code included; baked into the advances here so every
# label, button and text view in the app is tracked like the web without an attribute at each call site.
TRACKING = -0.02


def track(font):
    shift = round(TRACKING * font["head"].unitsPerEm)
    metrics = font["hmtx"].metrics
    for glyph, (advance, lsb) in metrics.items():
        if advance > 0:
            metrics[glyph] = (max(0, advance + shift), lsb)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (family, weights) in FONTS.items():
        for weight in weights:
            font = TTFont(source(name))
            instance = instantiateVariableFont(font, {"wght": weight, "slnt": 0, "DRKM": 0}, updateFontNames=False)
            instance.flavor = None
            rename(instance, family, weight)
            track(instance)
            path = os.path.join(OUT, f"{family}-W{weight}.ttf")
            instance.save(path)
            print(f"Wrote {os.path.relpath(path, ROOT)}")


main()
