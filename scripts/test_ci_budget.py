import os
import stat
import subprocess
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ci-budget.sh")


class CiBudgetTests(unittest.TestCase):
    """Runs the script under a fake `ps` whose process table puts a Runner.Worker of the given age two levels above
    the step's shell, as the runner does, with another Runner.Worker elsewhere that is not an ancestor."""

    def run_budget(self, budget, elapsed, worker_name="Runner.Worker"):
        with tempfile.TemporaryDirectory() as folder:
            body = f"""pid=$4
field=$2
case "$pid:$field" in
  "$STEP_SHELL:comm=") echo /bin/bash ;;
  "$STEP_SHELL:ppid=") echo 700 ;;
  700:comm=) echo /Users/runner/actions-runner/bin/{worker_name} ;;
  700:ppid=) echo 600 ;;
  700:etime=) echo "   {elapsed}" ;;
  600:comm=) echo launchd ;;
  600:ppid=) echo 1 ;;
  800:comm=) echo Runner.Worker ;;
  800:etime=) echo "   99:99" ;;
  *) exit 1 ;;
esac"""
            path = os.path.join(folder, "ps")
            with open(path, "w") as file:
                file.write(f"#!/bin/sh\n{body}\n")
            os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)
            # The test runner stands in for the step's shell: it is the script's parent.
            env = dict(os.environ, PATH=f"{folder}:{os.environ['PATH']}", STEP_SHELL=str(os.getpid()))
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
        result = self.run_budget(35, "00:20", worker_name="Runner.Listener")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Could not find this job's Runner.Worker process", result.stdout)


if __name__ == "__main__":
    unittest.main()
