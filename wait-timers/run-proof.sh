#!/usr/bin/env bash
# run-proof.sh: the wait-identity proof for done-done. Runs the wait-timers hook journey and the full timer journey
# against a read-only fork checkout (default ~/firstmate) and keeps one combined plain transcript as evidence.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
evidence=${DONE_DONE_EVIDENCE_ROOT:?}
mkdir -p "$evidence"
export FM_TEST_FORK=${FM_TEST_FORK:-$HOME/firstmate}
d=$(mktemp -d)
trap 'rm -rf -- "$d"' EXIT
mkdir -p "$d/fork" "$d/user" "$d/tmp" "$d/addons"
cp -a "$FM_TEST_FORK/bin" "$FM_TEST_FORK/tests" "$d/fork/"
cp -a "$repo/." "$d/addons/"
cp "$repo/wait-timers/tests/fm-wait-timers.test.sh" "$d/fork/tests/"
{
  echo "== hook journey"
  bash "$repo/wait-timers/tests/wait-timers-hook-e2e.sh"
  echo "== full timer journey"
  (cd "$d/fork" && env -u FM_TASK_ID FM_HOME="$d/fork" FM_ADDONS_DIR="$d/addons" HOME="$d/user" TMPDIR="$d/tmp" bash tests/fm-wait-timers.test.sh)
} 2>&1 | tee "$evidence/wait-timers-identity.txt"
test "${PIPESTATUS[0]}" -eq 0
