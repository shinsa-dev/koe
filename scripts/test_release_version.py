import json
import os
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ElementTree
from contextlib import redirect_stdout
from datetime import datetime, timezone
from io import StringIO

sys.path.insert(0, os.path.dirname(__file__))

import release_version as release  # noqa: E402

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


class PlanTests(unittest.TestCase):
    def test_first_releases_start_from_zero(self):
        self.assertEqual(release.plan([], "stable", "major")["version"], "1.0.0")
        self.assertEqual(release.plan([], "canary", "patch")["version"], "0.0.1-canary.1")

    def test_stable_bumps_the_last_stable_and_starts_notes_there(self):
        tags = ["v1.2.0", "v1.1.9", "v1.2.1-canary.3"]
        self.assertEqual(release.plan(tags, "stable", "patch"),
                         {"version": "1.2.1", "tag": "v1.2.1", "prerelease": "false", "notes_start_tag": "v1.2.0"})
        self.assertEqual(release.plan(tags, "stable", "minor")["version"], "1.3.0")

    def test_canary_is_the_next_patch_after_the_last_stable(self):
        result = release.plan(["v1.2.0"], "canary", "major")
        self.assertEqual(result["version"], "1.2.1-canary.1")
        self.assertEqual(result["prerelease"], "true")
        tags = ["v1.2.0", "v1.2.1-canary.1", "v1.2.1-canary.2"]
        result = release.plan(tags, "canary", "patch")
        self.assertEqual(result["version"], "1.2.1-canary.3")
        self.assertEqual(result["notes_start_tag"], "v1.2.1-canary.2")

    def test_ignores_tags_that_are_not_releases(self):
        tags = ["v2", "nightly", "v1.0.0-rc.1", "v1.0.0-beta.1"]
        self.assertEqual(release.plan(tags, "stable", "patch")["version"], "0.0.1")

    def test_refuses_an_unknown_channel_or_bump(self):
        with self.assertRaises(ValueError):
            release.plan([], "nightly", "patch")
        with self.assertRaises(ValueError):
            release.plan([], "beta", "patch")
        with self.assertRaises(ValueError):
            release.plan([], "stable", "huge")


class TaggedTests(unittest.TestCase):
    def test_a_tag_above_every_built_stable_is_its_own_version(self):
        built = ["v1.0.0", "v1.1.1-canary.3"]
        self.assertEqual(release.tagged("v1.2.0", built), {"version": "1.2.0", "tag": "v1.2.0", "prerelease": "false"})
        self.assertEqual(release.tagged("v1.0.0", [])["version"], "1.0.0")

    def test_empty_releases_made_by_hand_do_not_count(self):
        # v1.0.1 and v1.1.0 have no Koe.dmg, so they are not in built and do not block v1.0.5.
        self.assertEqual(release.tagged("v1.0.5", ["v1.0.0"])["version"], "1.0.5")

    def test_a_canary_above_the_tag_does_not_block_it(self):
        self.assertEqual(release.tagged("v1.1.0", ["v1.0.0", "v1.1.1-canary.3"])["version"], "1.1.0")

    def test_the_tag_itself_can_be_built_again(self):
        self.assertEqual(release.tagged("v1.2.0", ["v1.0.0", "v1.2.0"])["version"], "1.2.0")

    def test_refuses_a_tag_at_or_below_a_built_stable(self):
        for tag in ("v1.0.0", "v0.9.9", "v1.1.9"):
            with self.subTest(tag=tag), self.assertRaisesRegex(ValueError, "v1.2.0"):
                release.tagged(tag, ["v1.2.0", "v1.0.0"])

    def test_refuses_a_tag_that_is_not_a_stable_release(self):
        for tag in ("1.2.0", "v1.2", "v1.2.0-canary.1", "v1.2.0-beta.1", "release-1.2.0", ""):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.tagged(tag, [])


class OrderTests(unittest.TestCase):
    def test_a_prerelease_sorts_before_its_release(self):
        ordered = ["1.2.0-canary.1", "1.2.0-canary.10", "1.2.0", "1.10.0"]
        self.assertEqual(sorted(reversed(ordered), key=release.version_key), ordered)

    def test_channel_of_a_version(self):
        self.assertEqual(release.channel_of("1.0.0"), "stable")
        self.assertEqual(release.channel_of("1.0.0-canary.2"), "canary")
        with self.assertRaises(ValueError):
            release.channel_of("0.0.0-dev")
        with self.assertRaises(ValueError):
            release.channel_of("1.0.0-beta.2")


class CanaryTests(unittest.TestCase):
    def test_the_first_canary_always_builds(self):
        self.assertEqual(release.canary_decision(None, [])["build"], "true")

    def test_docs_alone_make_no_canary(self):
        decision = release.canary_decision("v1.0.1-canary.1", ["README.md", "docs/release.md", "Sources/CLAUDE.md"])
        self.assertEqual(decision["build"], "false")

    def test_an_app_change_makes_one_and_names_it(self):
        changed = ["README.md", "Sources/Koe/App/Updater.swift", "a", "b", "c", "d", "e"]
        decision = release.canary_decision("v1.0.1-canary.1", changed)
        self.assertEqual(decision["build"], "true")
        self.assertIn("`Sources/Koe/App/Updater.swift`", decision["reason"])
        self.assertIn("and 1 more", decision["reason"])


class ChannelTests(unittest.TestCase):
    def test_stable_moves_only_stable(self):
        current = {"stable": "1.0.0", "canary": "1.0.1-canary.4"}
        self.assertEqual(release.reached_channels("1.1.0", current), ["stable"])
        self.assertEqual(release.reached_channels("1.1.0", {"stable": "1.2.0"}), [])

    def test_a_canary_moves_its_own_channel_when_newer(self):
        self.assertEqual(release.reached_channels("1.1.0-canary.2", {"canary": None}), ["canary"])
        self.assertEqual(release.reached_channels("1.1.0-canary.2", {"canary": "1.1.0-canary.3"}), [])


class FileTests(unittest.TestCase):
    def test_pointer_names_the_dmg_under_koe(self):
        when = datetime(2026, 11, 13, 9, 30, tzinfo=timezone.utc)
        self.assertEqual(release.pointer("1.0.0", 42, "a" * 64, when), {
            "version": "1.0.0", "key": "koe/releases/1.0.0/Koe.dmg", "size": 42, "sha256": "a" * 64,
            "publishedAt": "2026-11-13T09:30:00Z",
        })
        with self.assertRaises(ValueError):
            release.pointer("1.0.0", 42, "nope")

    def test_appcast_is_one_signed_item(self):
        text = release.appcast({"version": "1.2.1-canary.3", "build": 57, "length": 1234,
                                "edSignature": "c2ln+/=", "publishedAt": "Fri, 13 Nov 2026 09:30:00 +0000"})
        channel = ElementTree.fromstring(text).find("channel")
        self.assertEqual(channel.findtext("title"), "Koe Canary")
        item = channel.find("item")
        self.assertEqual(item.findtext(f"{SPARKLE}version"), "57")
        self.assertEqual(item.findtext(f"{SPARKLE}shortVersionString"), "1.2.1-canary.3")
        self.assertEqual(item.findtext(f"{SPARKLE}minimumSystemVersion"), "26.0")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"), "https://shinsa.dev/koe/releases/1.2.1-canary.3/Koe.dmg")
        self.assertEqual(enclosure.get("length"), "1234")
        self.assertEqual(enclosure.get(f"{SPARKLE}edSignature"), "c2ln+/=")

    def test_appcast_refuses_a_build_that_is_not_a_number(self):
        with self.assertRaises(ValueError):
            release.appcast({"version": "1.0.0", "build": "1a", "length": 1, "edSignature": "x", "publishedAt": ""})


class CommandTests(unittest.TestCase):
    def run_main(self, *argv):
        output = StringIO()
        with redirect_stdout(output):
            code = release.main(list(argv))
        return code, output.getvalue()

    def test_channels_and_appcast_read_their_files(self):
        with tempfile.TemporaryDirectory() as directory:
            pointers = os.path.join(directory, "pointers.json")
            with open(pointers, "w", encoding="utf-8") as file:
                json.dump({"stable": "1.0.0", "canary": None}, file)
            self.assertEqual(self.run_main("channels", "1.0.1", pointers), (0, "stable\n"))
            update = os.path.join(directory, "update.json")
            with open(update, "w", encoding="utf-8") as file:
                json.dump({"version": "1.0.1", "build": 3, "length": 9, "edSignature": "s", "publishedAt": "now"},
                          file)
            code, text = self.run_main("appcast", update)
            self.assertEqual(code, 0)
            self.assertIn("<sparkle:version>3</sparkle:version>", text)

    def test_tagged_reads_the_built_tags(self):
        with tempfile.TemporaryDirectory() as directory:
            built = os.path.join(directory, "built.json")
            with open(built, "w", encoding="utf-8") as file:
                json.dump(["v1.0.0", "v1.1.1-canary.3"], file)
            self.assertEqual(self.run_main("tagged", "v1.2.0", built),
                             (0, "version=1.2.0\ntag=v1.2.0\nprerelease=false\n"))
            with self.assertRaises(ValueError):
                self.run_main("tagged", "v0.9.0", built)
            self.assertEqual(self.run_main("tagged", "v1.2.0")[0], 2)

    def test_pointer_prints_json(self):
        code, text = self.run_main("pointer", "1.0.0", "5", "b" * 64)
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(text)["key"], "koe/releases/1.0.0/Koe.dmg")

    def test_unknown_command_prints_usage(self):
        self.assertEqual(self.run_main("nope")[0], 2)


if __name__ == "__main__":
    unittest.main()
