#!/bin/bash
# usage: scripts/ci-budget.sh <seconds>
# The last step of a CI job: fails it when the job has run longer than its budget. The runner starts one
# Runner.Worker process per job when it takes the job, so its age counts setup and leaves out time in the queue.
set -euo pipefail

budget=${1:?usage: scripts/ci-budget.sh <seconds>}
worker=$(pgrep -f Runner.Worker | head -n 1 || true)
elapsed=$([[ -n $worker ]] && ps -o etime= -p "$worker" | tr -d ' ' || true)
if [[ ! $elapsed =~ ^(([0-9]+)-)?(([0-9]+):)?([0-9]+):([0-9]+)$ ]]; then
  echo "::error title=Budget::Could not find this job's Runner.Worker process, so its budget cannot be checked."
  exit 1
fi
took=$(((10#${BASH_REMATCH[2]:-0} * 24 + 10#${BASH_REMATCH[4]:-0}) * 3600 + 10#${BASH_REMATCH[5]} * 60 + 10#${BASH_REMATCH[6]}))

if ((took > budget)); then
  echo "::error title=Budget::This job took ${took} s, over its budget of ${budget} s."
  exit 1
fi
echo "This job took ${took} s, within its budget of ${budget} s." | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
