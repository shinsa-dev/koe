import datetime
import json
import os
import stat
import subprocess
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ci-budget.sh")
RUNNER = "GitHub Actions 7"


def started(seconds_ago):
    moment = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=seconds_ago)
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


class CiBudgetTests(unittest.TestCase):
    """Runs the script against a fake `gh` that answers with the given jobs, filtered by its own `--jq`."""

    def run_budget(self, budget, jobs):
        with tempfile.TemporaryDirectory() as folder:
            gh = os.path.join(folder, "gh")
            with open(gh, "w") as file:
                file.write("#!/bin/sh\n")
                file.write(f'echo "$2" > "{folder}/url"\n')
                # The script's own filter, applied by jq the way gh's --jq applies it.
                file.write(f"jq -r \"$4\" <<'JSON'\n{json.dumps({'jobs': jobs})}\nJSON\n")
            os.chmod(gh, os.stat(gh).st_mode | stat.S_IEXEC)
            env = dict(
                os.environ,
                PATH=f"{folder}:{os.environ['PATH']}",
                GITHUB_REPOSITORY="shinsa-dev/koe",
                GITHUB_RUN_ID="42",
                GITHUB_RUN_ATTEMPT="2",
                RUNNER_NAME=RUNNER,
            )
            env.pop("GITHUB_STEP_SUMMARY", None)
            result = subprocess.run([SCRIPT, str(budget)], env=env, capture_output=True, text=True)
            with open(os.path.join(folder, "url")) as file:
                url = file.read().strip()
        return result, url

    def job(self, seconds_ago, runner=RUNNER, status="in_progress"):
        return {"runner_name": runner, "status": status, "started_at": started(seconds_ago)}

    def test_a_job_within_its_budget_passes(self):
        result, url = self.run_budget(35, [self.job(20)])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("within its budget of 35 s", result.stdout)
        self.assertEqual(url, "repos/shinsa-dev/koe/actions/runs/42/attempts/2/jobs?per_page=100")

    def test_a_job_over_its_budget_fails_with_its_time(self):
        result, _ = self.run_budget(35, [self.job(50)])
        self.assertEqual(result.returncode, 1)
        self.assertRegex(result.stdout, r"::error title=Budget::This job took 5\d s, over its budget of 35 s\.")

    def test_only_this_runners_job_counts(self):
        jobs = [self.job(300, runner="GitHub Actions 8"), self.job(10), self.job(400, status="completed")]
        result, _ = self.run_budget(35, jobs)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_a_job_it_cannot_find_fails(self):
        result, _ = self.run_budget(35, [self.job(10, runner="GitHub Actions 8")])
        self.assertEqual(result.returncode, 1)
        self.assertIn("Could not find when this job started", result.stdout)


if __name__ == "__main__":
    unittest.main()
