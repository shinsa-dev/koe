#!/usr/bin/env python3
# usage: scripts/dmg.py: draws the disk image's background into Resources/DMG, one per channel at 1x and 2x.
# A port of shinsa's apps/desktop/scripts/dmg-background.ts, so both installers look alike. Needs fontTools and
# rsvg-convert (brew install librsvg). release.sh dmg joins each pair into one TIFF.
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources/DMG")
FONTS = os.path.join(ROOT, "Resources/Fonts")
MARK = os.path.join(ROOT, "Resources/KoeMark.svg")

WIDTH = 660
HEIGHT = 432
TITLE_BAR = 32
# Icon centres in window points: dmg_settings.py places Koe.app and Applications here.
ICON = {"y": 196, "app_x": 180, "applications_x": 480, "app_half": 45, "applications_half": 52, "clearance": 14}
GUIDE_START = ICON["app_x"] + ICON["app_half"] + ICON["clearance"] + 6
GUIDE_END = ICON["applications_x"] - ICON["applications_half"] - ICON["clearance"] - 6
DOT_PITCH = 24
DOT_RADIUS = 1.1
INK = {
    "page": "#ffffff",
    "dot": "#d9d9de",
    "trace": "#d4d4d8",
    "strong": "#18181b",
    "muted": "#71717a",
    "accent": "#0a7aff",
}
FAMILY = "ShinsaAreal"
# The web's medium is 450 (scripts/fonts.py); Shinsa's background asks its variable font for 500.
WORDMARK = {"size": 20, "weight": 450, "mark": 20, "gap": 9, "y": 58, "text": "Koe"}
PILL = {"size": 11, "weight": 450, "pad_x": 7, "height": 19, "gap": 9}
PILLS = {"canary": {"label": "Canary", "tile": "#fdf0d2", "ink": "#9a5b00"}}
HINT = {"size": 13, "y": 330, "text": "Drag Koe into Applications to install"}
CHANNELS = ["stable", "canary"]
MARK_BOX = 365


def text_width(text, size, weight):
    from fontTools.ttLib import TTFont

    font = TTFont(os.path.join(FONTS, f"{FAMILY}-W{weight}.ttf"))
    cmap = font.getBestCmap()
    metrics = font["hmtx"].metrics
    units = sum(metrics[cmap[ord(char)]][0] for char in text)
    return units * size / font["head"].unitsPerEm


def mark_shapes(svg):
    shapes = re.findall(r"<(?:path|circle)\b[^>]*/>", svg)
    if not shapes:
        sys.exit(f"No shapes in {MARK}.")
    return [re.sub(r'\s*fill="[^"]*"', "", shape) for shape in shapes]


def dots():
    circles = []
    y = DOT_PITCH / 2
    while y < HEIGHT - TITLE_BAR:
        x = DOT_PITCH / 2
        while x < WIDTH:
            circles.append(f'<circle cx="{x:g}" cy="{y:g}" r="{DOT_RADIUS}"/>')
            x += DOT_PITCH
        y += DOT_PITCH
    return f'<g fill="{INK["dot"]}" mask="url(#fade)">{"".join(circles)}</g>'


def edge_traces():
    y = ICON["y"]
    app_edge = ICON["app_x"] - ICON["app_half"] - ICON["clearance"]
    applications_edge = ICON["applications_x"] + ICON["applications_half"] + ICON["clearance"]
    paths = [
        f"M 0 {y - 74} H 44 L 56 {y - 62} V {y - 18} L 68 {y - 6} H {app_edge}",
        f"M 0 {y - 58} H 28 L 40 {y - 46} V {y - 2} L 52 {y + 10} H {app_edge}",
        f"M {WIDTH} {y + 82} H {WIDTH - 44} L {WIDTH - 56} {y + 70} V {y + 18} L {WIDTH - 68} {y + 6} H {applications_edge}",
        f"M {WIDTH} {y + 66} H {WIDTH - 28} L {WIDTH - 40} {y + 54} V {y + 2} L {WIDTH - 52} {y - 10} H {applications_edge}",
    ]
    traces = "".join(f'<path d="{d}" fill="none" stroke="{INK["trace"]}" stroke-width="1.25"/>' for d in paths)
    pins = "".join(
        f'<rect x="{px}" y="{py - 1.5}" width="6" height="3" rx="1" fill="{INK["trace"]}"/>'
        for px, py in [(app_edge - 6, y - 6), (app_edge - 6, y + 10), (applications_edge, y + 6), (applications_edge, y - 10)]
    )
    vias = "".join(
        f'<circle cx="{vx}" cy="{vy}" r="3" fill="{INK["page"]}" stroke="{INK["trace"]}" stroke-width="1.25"/>'
        for vx, vy in [(40, 360), (612, 64), (628, 352)]
    )
    return traces + pins + vias


def guide():
    upper, lower = ICON["y"] - 6, ICON["y"] + 6
    lanes = "".join(
        f'<path d="M {GUIDE_START} {lane} H {GUIDE_END}" fill="none" stroke="{INK["trace"]}" stroke-width="1.25"/>'
        for lane in (upper, lower)
    )
    pins = "".join(
        f'<rect x="{px}" y="{lane - 1.5}" width="6" height="3" rx="1"/>'
        for px in (GUIDE_START - 6, GUIDE_END)
        for lane in (upper, lower)
    )
    signal = (
        f'<path d="M {GUIDE_START + 24} {upper} H {GUIDE_END - 2}" fill="none" stroke="url(#signal)" '
        'stroke-width="1.5" stroke-linecap="round"/>'
    )
    tip = (
        f'<path d="M {GUIDE_END - 9} {upper - 5} L {GUIDE_END - 3} {upper} L {GUIDE_END - 9} {upper + 5}" '
        f'fill="none" stroke="{INK["accent"]}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>'
    )
    return f'{lanes}<g fill="{INK["trace"]}">{pins}</g>{signal}{tip}'


def wordmark(channel, shapes, measure):
    pill = PILLS.get(channel)
    word = measure(WORDMARK["text"], WORDMARK["size"], WORDMARK["weight"])
    label = measure(pill["label"], PILL["size"], PILL["weight"]) if pill else 0
    pill_width = label + PILL["pad_x"] * 2
    total = WORDMARK["mark"] + WORDMARK["gap"] + word + (PILL["gap"] + pill_width if pill else 0)
    left = (WIDTH - total) / 2
    scale = WORDMARK["mark"] / MARK_BOX
    mark_y = WORDMARK["y"] - WORDMARK["mark"] / 2
    text_x = left + WORDMARK["mark"] + WORDMARK["gap"]
    # 0.358 of the size drops Areal's x-height centre onto the line, as Shinsa's does.
    baseline = WORDMARK["y"] + WORDMARK["size"] * 0.358
    parts = [
        f'<g transform="translate({left:.2f} {mark_y:g}) scale({scale:.6f})" fill="{INK["strong"]}">{"".join(shapes)}</g>',
        f'<text x="{text_x:.2f}" y="{baseline:.2f}" font-size="{WORDMARK["size"]}" font-weight="{WORDMARK["weight"]}" '
        f'fill="{INK["strong"]}">{WORDMARK["text"]}</text>',
    ]
    if pill:
        pill_x = text_x + word + PILL["gap"]
        parts.append(
            f'<rect x="{pill_x:.2f}" y="{WORDMARK["y"] - PILL["height"] / 2:g}" width="{pill_width:.2f}" '
            f'height="{PILL["height"]}" rx="{PILL["height"] / 2:g}" fill="{pill["tile"]}"/>'
        )
        parts.append(
            f'<text x="{pill_x + pill_width / 2:.2f}" y="{WORDMARK["y"] + PILL["size"] * 0.358:.2f}" '
            f'font-size="{PILL["size"]}" font-weight="{PILL["weight"]}" fill="{pill["ink"]}" '
            f'text-anchor="middle">{pill["label"]}</text>'
        )
    return "".join(parts)


def hint():
    return (
        f'<text x="{WIDTH / 2:g}" y="{HINT["y"]}" font-size="{HINT["size"]}" font-weight="400" fill="{INK["muted"]}" '
        f'text-anchor="middle">{HINT["text"]}</text>'
    )


def background(channel, shapes, measure=text_width):
    center_y = ICON["y"] + 20
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}" font-family="{FAMILY}">
  <defs>
    <radialGradient id="fade-gradient" cx="{WIDTH / 2:g}" cy="{center_y}" r="{WIDTH * 0.5:g}" gradientTransform="translate(0 {center_y}) scale(1 0.62) translate(0 {-center_y})" gradientUnits="userSpaceOnUse">
      <stop offset="0.5" stop-color="#000"/>
      <stop offset="1" stop-color="#fff"/>
    </radialGradient>
    <mask id="fade"><rect width="{WIDTH}" height="{HEIGHT}" fill="url(#fade-gradient)"/></mask>
    <linearGradient id="signal" x1="{GUIDE_START + 24}" y1="0" x2="{GUIDE_END}" y2="0" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{INK["accent"]}" stop-opacity="0"/>
      <stop offset="1" stop-color="{INK["accent"]}"/>
    </linearGradient>
  </defs>
  <rect width="{WIDTH}" height="{HEIGHT}" fill="{INK["page"]}"/>
  {dots()}
  {edge_traces()}
  {guide()}
  {wordmark(channel, shapes, measure)}
  {hint()}
</svg>
"""


def main():
    with open(MARK) as file:
        shapes = mark_shapes(file.read())
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="koe-dmg-") as scratch:
        config = os.path.join(scratch, "fonts.conf")
        with open(config, "w") as file:
            file.write(
                '<?xml version="1.0"?>\n<!DOCTYPE fontconfig SYSTEM "fonts.dtd">\n'
                f"<fontconfig><dir>{FONTS}</dir><cachedir>{scratch}/cache</cachedir></fontconfig>\n"
            )
        env = {**os.environ, "FONTCONFIG_FILE": config}
        for channel in CHANNELS:
            svg = os.path.join(scratch, f"{channel}.svg")
            with open(svg, "w") as file:
                file.write(background(channel, shapes))
            for scale, suffix in ((1, ""), (2, "@2x")):
                output = os.path.join(OUT, f"background-{channel}{suffix}.png")
                subprocess.run(["rsvg-convert", "--zoom", str(scale), svg, "--output", output], env=env, check=True)
                print(f"Wrote {os.path.relpath(output, ROOT)}")


if __name__ == "__main__":
    main()
