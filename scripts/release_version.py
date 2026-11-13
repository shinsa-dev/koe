#!/usr/bin/env python3
"""Koe's release rules, as Shinsa's: the next version from the tags, whether main needs a canary, which channels a
release reaches and the appcast Sparkle reads for each. The Release workflow calls it; docs/release.md explains it.

    release_version.py plan <stable|canary> <patch|minor|major>   prints version, tag, prerelease, notes_start_tag
    release_version.py canary                                           prints build and reason, from git
    release_version.py channels <version> <pointers.json>                prints the channels the release moves
    release_version.py pointer <version> <size> <sha256>                 prints a channel's download pointer
    release_version.py appcast <update.json>                             prints the appcast for that update
"""

from __future__ import annotations

import fnmatch
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from xml.sax.saxutils import escape, quoteattr

CHANNELS = ("stable", "canary")
BUMPS = ("patch", "minor", "major")
SITE = "https://shinsa.dev/koe"
DMG_NAME = "Koe.dmg"
MINIMUM_SYSTEM = "26.0"

STABLE_TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
CANARY_TAG = re.compile(r"^v\d+\.\d+\.\d+-canary\.\d+$")
VERSION = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-(canary)\.(\d+))?$")

# Koe ships no beta: a release moves only its own channel.
REACHED = {"stable": ("stable",), "canary": ("canary",)}

# A merge that touches only these never makes a canary: it would ship the same app again. fnmatch's * crosses
# folders, so *.md takes every CLAUDE.md too.
CANARY_IGNORED = ("docs/*", "*.md", ".claude/*", ".github/assets/*")


def version_key(version: str) -> tuple[int, int, int, int, int]:
    """Orders versions as semver does for Koe's tags: a canary sorts before its release."""
    match = VERSION.match(version)
    if not match:
        raise ValueError(f"{version!r} is not a Koe version such as 1.2.0 or 1.2.0-canary.4.")
    major, minor, patch, identifier, number = match.groups()
    rank = {"canary": 0, None: 1}[identifier]
    return int(major), int(minor), int(patch), rank, int(number or 0)


def channel_of(version: str) -> str:
    version_key(version)
    return "canary" if "-canary." in version else "stable"


def newest(tags: list[str], pattern: re.Pattern[str]) -> str | None:
    versions = [tag[1:] for tag in tags if pattern.match(tag)]
    return max(versions, key=version_key, default=None)


def bump(version: str, part: str) -> str:
    major, minor, patch = (int(n) for n in version.split("-")[0].split("."))
    if part == "major":
        return f"{major + 1}.0.0"
    if part == "minor":
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def count(tags: list[str], base: str, identifier: str) -> int:
    pattern = re.compile(rf"^v{re.escape(base)}-{identifier}\.(\d+)$")
    return max((int(m.group(1)) for tag in tags if (m := pattern.match(tag))), default=0)


def plan(tags: list[str], channel: str, part: str) -> dict[str, str]:
    if channel not in CHANNELS:
        raise ValueError(f"The channel must be stable or canary, not {channel!r}.")
    if part not in BUMPS:
        raise ValueError(f"The bump must be patch, minor or major, not {part!r}.")
    last_stable = newest(tags, STABLE_TAG)
    if channel == "canary":
        base = bump(last_stable or "0.0.0", "patch")
        version = f"{base}-canary.{count(tags, base, 'canary') + 1}"
        last_canary = newest(tags, CANARY_TAG)
        start = f"v{last_canary}" if last_canary else ""
    else:
        base = bump(last_stable or "0.0.0", part)
        version = base
        start = f"v{last_stable}" if last_stable else ""
    return {
        "version": version,
        "tag": f"v{version}",
        "prerelease": "false" if channel == "stable" else "true",
        "notes_start_tag": start,
    }


def is_app_change(path: str) -> bool:
    return not any(fnmatch.fnmatch(path, pattern) for pattern in CANARY_IGNORED)


def canary_decision(base: str | None, changed: list[str]) -> dict[str, str]:
    files = [path for path in changed if is_app_change(path)]
    if base is None:
        return {"build": "true", "reason": "Building a canary: there is no canary before it."}
    if not files:
        return {"build": "false", "reason": f"No canary: nothing since {base} changes the app, only docs."}
    shown = ", ".join(f"`{path}`" for path in files[:5])
    more = f" and {len(files) - 5} more" if len(files) > 5 else ""
    return {"build": "true", "reason": f"Building a canary: since {base}, {shown}{more} changed."}


def reached_channels(version: str, current: dict[str, str | None]) -> list[str]:
    """The channels whose pointer and appcast move to this release: never one that already has a newer version."""
    return [
        channel
        for channel in REACHED[channel_of(version)]
        if not current.get(channel) or version_key(version) >= version_key(current[channel] or "")
    ]


def pointer(version: str, size: int, sha256: str, published: datetime | None = None) -> dict[str, object]:
    if not re.fullmatch(r"[0-9a-f]{64}", sha256):
        raise ValueError(f"{sha256!r} is not a SHA-256 digest.")
    when = (published or datetime.now(timezone.utc)).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {"version": version, "key": f"koe/releases/{version}/{DMG_NAME}", "size": size, "sha256": sha256,
            "publishedAt": when}


def appcast(update: dict[str, object]) -> str:
    """One item, the release itself: Sparkle offers it when its build is above the installed one."""
    version = str(update["version"])
    build = str(update["build"])
    if not build.isdigit():
        raise ValueError(f"The build must be a whole number, not {build!r}.")
    channel = channel_of(version)
    url = f"{SITE}/releases/{version}/{DMG_NAME}"
    attributes = " ".join([
        f"url={quoteattr(url)}",
        f"length={quoteattr(str(int(str(update['length']))))}",
        'type="application/x-apple-diskimage"',
        f"sparkle:edSignature={quoteattr(str(update['edSignature']))}",
    ])
    return "\n".join([
        '<?xml version="1.0" encoding="utf-8"?>',
        '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">',
        "  <channel>",
        f"    <title>Koe {escape(channel.capitalize())}</title>",
        f"    <link>{SITE}</link>",
        "    <item>",
        f"      <title>Koe {escape(version)}</title>",
        f"      <pubDate>{escape(str(update['publishedAt']))}</pubDate>",
        f"      <sparkle:version>{escape(build)}</sparkle:version>",
        f"      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>",
        f"      <sparkle:minimumSystemVersion>{MINIMUM_SYSTEM}</sparkle:minimumSystemVersion>",
        f"      <enclosure {attributes} />",
        "    </item>",
        "  </channel>",
        "</rss>",
        "",
    ])


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def emit(values: dict[str, str]) -> None:
    for key, value in values.items():
        print(f"{key}={value}")


def main(argv: list[str]) -> int:
    command, *rest = argv or [""]
    if command == "plan" and len(rest) == 2:
        emit(plan(git("tag", "--list", "v*").split(), rest[0], rest[1]))
    elif command == "canary" and not rest:
        base = newest(git("tag", "--list", "v*").split(), CANARY_TAG)
        changed = git("diff", "--name-only", f"v{base}", "HEAD").split() if base else []
        emit(canary_decision(f"v{base}" if base else None, changed))
    elif command == "channels" and len(rest) == 2:
        with open(rest[1], encoding="utf-8") as file:
            print(" ".join(reached_channels(rest[0], json.load(file))))
    elif command == "pointer" and len(rest) == 3:
        print(json.dumps(pointer(rest[0], int(rest[1]), rest[2]), indent=2))
    elif command == "appcast" and len(rest) == 1:
        with open(rest[0], encoding="utf-8") as file:
            sys.stdout.write(appcast(json.load(file)))
    else:
        sys.stderr.write(__doc__ or "")
        return 2
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except ValueError as error:
        sys.stderr.write(f"{error}\n")
        sys.exit(1)
