#!/bin/bash
# usage: scripts/ci-budget.sh <seconds>
# The last step of a CI job: fails it when the job has run longer than its budget. The runner starts one
# Runner.Worker process per job when it takes the job, so its age counts setup and leaves out time in the queue.
# The worker is found among this step's ancestors: macOS's pgrep leaves its own ancestors out.
set -euo pipefail

budget=${1:?usage: scripts/ci-budget.sh <seconds>}
pid=$PPID
elapsed=""
while [[ $pid =~ ^[0-9]+$ ]] && ((pid > 1)); do
  command=$(ps -o comm= -p "$pid" || true)
  if [[ $command == *Runner.Worker ]]; then
    elapsed=$(ps -o etime= -p "$pid" | tr -d ' ')
    break
  fi
  pid=$(ps -o ppid= -p "$pid" | tr -d ' ' || true)
done
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
