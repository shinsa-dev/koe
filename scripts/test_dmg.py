import importlib.util
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))

import dmg  # noqa: E402


def measure(text, size, weight):
    return len(text) * size / 2


class DmgTests(unittest.TestCase):
    def setUp(self):
        with open(dmg.MARK) as file:
            self.shapes = dmg.mark_shapes(file.read())

    def test_mark_shapes_take_the_wordmark_ink(self):
        self.assertEqual(len(self.shapes), 2)
        for shape in self.shapes:
            self.assertNotIn("fill=", shape)

    def test_stable_has_no_pill(self):
        svg = dmg.background("stable", self.shapes, measure)
        self.assertNotIn("Canary", svg)
        self.assertIn(">Koe</text>", svg)
        self.assertIn("Drag Koe into Applications to install", svg)

    def test_canary_has_a_pill(self):
        svg = dmg.background("canary", self.shapes, measure)
        self.assertIn(">Canary</text>", dmg.wordmark("canary", self.shapes, measure))
        self.assertIn(dmg.PILLS["canary"]["tile"], svg)

    def test_wordmark_is_centred(self):
        for channel in dmg.CHANNELS:
            row = dmg.wordmark(channel, self.shapes, measure)
            left = float(re.search(r"translate\(([\d.]+) ", row).group(1))
            if channel in dmg.PILLS:
                rect = re.search(r'<rect x="([\d.]+)"[^>]*width="([\d.]+)"', row)
                right = float(rect.group(1)) + float(rect.group(2))
            else:
                text_x = float(re.search(r'<text x="([\d.]+)"', row).group(1))
                right = text_x + measure("Koe", dmg.WORDMARK["size"], 0)
            self.assertAlmostEqual(left, dmg.WIDTH - right, delta=0.02)

    def test_guide_sits_between_the_icons(self):
        self.assertGreater(dmg.GUIDE_START, dmg.ICON["app_x"] + dmg.ICON["app_half"])
        self.assertLess(dmg.GUIDE_END, dmg.ICON["applications_x"] - dmg.ICON["applications_half"])

    @unittest.skipUnless(importlib.util.find_spec("fontTools"), "needs fontTools")
    def test_text_width_reads_the_bundled_font(self):
        width = dmg.text_width("Koe", 20, 450)
        self.assertGreater(width, 25)
        self.assertLess(width, 50)


if __name__ == "__main__":
    unittest.main()
