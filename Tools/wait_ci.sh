#!/usr/bin/env bash
# Waits for the CI workflow's run on a pushed commit, prints each job's result, and exits 0 only
# when the run succeeded. Usage: Tools/wait_ci.sh [commit]   (defaults to HEAD)
#
# Only the workflow named "CI" counts: the Pages deployment for the same commit finishes first and
# says nothing about the tests (a hand-written wait reported early on it, 2026-10-17). The run is
# matched on the full hash, because a short one matches nothing.
set -euo pipefail
SHA="$(git rev-parse "${1:-HEAD}")"
RUN=""
for _ in $(seq 1 60); do
  RUN="$(gh run list --limit 30 --json headSha,name,databaseId \
    --jq ".[] | select(.headSha == \"$SHA\" and .name == \"CI\") | .databaseId" | head -1)"
  [ -n "$RUN" ] && break
  sleep 10
done
if [ -z "$RUN" ]; then
  echo "No CI run for $SHA after 10 minutes; was it pushed?" >&2
  exit 1
fi
echo "CI run $RUN for ${SHA:0:7}"
gh run watch "$RUN" --interval 30 > /dev/null 2>&1 || true
CONCLUSION="$(gh run view "$RUN" --json conclusion --jq .conclusion)"
gh run view "$RUN" --json jobs --jq '.jobs[] | "  \(.conclusion)  \(.name)"'
echo "CI $CONCLUSION"
[ "$CONCLUSION" = "success" ]
