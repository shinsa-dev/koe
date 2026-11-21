import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ci_source_times  # noqa: E402


def git(folder, *args):
    return subprocess.run(["git", *args], cwd=folder, capture_output=True, check=True).stdout


class CiSourceTimesTests(unittest.TestCase):
    """Stamps files in a throwaway repository, the way the CI jobs do before they build."""

    def stamped(self, files):
        with tempfile.TemporaryDirectory() as folder:
            git(folder, "init", "-q")
            for name, text in files.items():
                with open(os.path.join(folder, name), "w") as file:
                    file.write(text)
            git(folder, "add", "-A")
            cwd = os.getcwd()
            os.chdir(folder)
            try:
                count = ci_source_times.stamp(git(folder, "ls-files", "-s", "-z"))
            finally:
                os.chdir(cwd)
            return count, {name: os.lstat(os.path.join(folder, name)).st_mtime_ns for name in files}

    def test_the_same_content_gets_the_same_time_in_another_checkout(self):
        _, first = self.stamped({"a.swift": "let a = 1\n"})
        _, second = self.stamped({"a.swift": "let a = 1\n"})
        self.assertEqual(first["a.swift"], second["a.swift"])

    def test_changed_content_gets_another_time(self):
        _, before = self.stamped({"a.swift": "let a = 1\n"})
        _, after = self.stamped({"a.swift": "let a = 2\n"})
        self.assertNotEqual(before["a.swift"], after["a.swift"])

    def test_every_tracked_file_is_stamped_with_a_time_in_its_range(self):
        count, times = self.stamped({"a.swift": "a\n", "b.swift": "b\n"})
        self.assertEqual(count, 2)
        for moment in times.values():
            self.assertGreaterEqual(moment, ci_source_times.BASE * 1_000_000_000)
            self.assertLess(moment, (ci_source_times.BASE + 16**7 + 1) * 1_000_000_000)

    def test_a_file_missing_from_the_checkout_is_left_out(self):
        listing = b"100644 " + b"a" * 40 + b" 0\tgone.swift\0"
        with tempfile.TemporaryDirectory() as folder:
            cwd = os.getcwd()
            os.chdir(folder)
            try:
                self.assertEqual(ci_source_times.stamp(listing), 0)
            finally:
                os.chdir(cwd)


if __name__ == "__main__":
    unittest.main()
