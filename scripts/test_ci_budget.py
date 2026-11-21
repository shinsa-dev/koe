import os
import stat
import subprocess
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ci-budget.sh")


class CiBudgetTests(unittest.TestCase):
    """Runs the script against a fake `pgrep` and `ps` that report a Runner.Worker of the given age."""

    def run_budget(self, budget, elapsed, worker="4242"):
        with tempfile.TemporaryDirectory() as folder:
            tools = {
                "pgrep": f'[ "$2" = Runner.Worker ] && [ -n "{worker}" ] && echo {worker} || exit 1',
                "ps": f'[ "$4" = "{worker}" ] && echo "   {elapsed}"',
            }
            for name, body in tools.items():
                path = os.path.join(folder, name)
                with open(path, "w") as file:
                    file.write(f"#!/bin/sh\n{body}\n")
                os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)
            env = dict(os.environ, PATH=f"{folder}:{os.environ['PATH']}")
            env.pop("GITHUB_STEP_SUMMARY", None)
            return subprocess.run([SCRIPT, str(budget)], env=env, capture_output=True, text=True)

    def test_a_job_within_its_budget_passes(self):
        result = self.run_budget(35, "00:20")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("This job took 20 s, within its budget of 35 s.", result.stdout)

    def test_a_job_over_its_budget_fails_with_its_time(self):
        result = self.run_budget(35, "01:09")
        self.assertEqual(result.returncode, 1)
        self.assertIn("::error title=Budget::This job took 69 s, over its budget of 35 s.", result.stdout)

    def test_hours_and_days_count(self):
        result = self.run_budget(35, "1-02:03:04")
        self.assertIn("This job took 93784 s", result.stdout)

    def test_a_job_on_its_budget_passes(self):
        self.assertEqual(self.run_budget(35, "00:35").returncode, 0)

    def test_a_runner_without_a_worker_fails(self):
        result = self.run_budget(35, "00:20", worker="")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Could not find this job's Runner.Worker process", result.stdout)


if __name__ == "__main__":
    unittest.main()
