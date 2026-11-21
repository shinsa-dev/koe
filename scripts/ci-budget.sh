#!/bin/bash
# usage: scripts/ci-budget.sh <seconds>
# The last step of a CI job: fails it when the job has run longer than its budget, counted from when a runner took it,
# so setup counts and time in the queue does not.
set -euo pipefail

budget=${1:?usage: scripts/ci-budget.sh <seconds>}
jobs="repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/attempts/${GITHUB_RUN_ATTEMPT:-1}/jobs?per_page=100"
started=$(gh api "$jobs" --jq ".jobs[] | select(.runner_name == \"$RUNNER_NAME\" and .status == \"in_progress\") | .started_at")
if [[ -z $started || $started == *$'\n'* ]]; then
  echo "::error title=Budget::Could not find when this job started on $RUNNER_NAME, so its budget cannot be checked."
  exit 1
fi

took=$(python3 -c 'import datetime, sys
start = datetime.datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
print(int((datetime.datetime.now(datetime.timezone.utc) - start).total_seconds()))' "$started")

if ((took > budget)); then
  echo "::error title=Budget::This job took ${took} s, over its budget of ${budget} s."
  exit 1
fi
echo "This job took ${took} s, within its budget of ${budget} s." | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
