#!/usr/bin/env bash
# run-proof.sh: the fleet-contract-check proof for done-done. Runs the real script against the installed fork
# (FM_MAIN_HOME, default ~/firstmate, read-only) in a throwaway home, then the broken-caller journey, and keeps the transcript.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
evidence=${DONE_DONE_EVIDENCE_ROOT:?}
mkdir -p "$evidence"
{
  bash "$repo/fleet-contract-check/fleet-contract-check"
  bash "$repo/fleet-contract-check/tests/fleet-contract-check.test.sh"
} 2>&1 | tee "$evidence/fleet-contract-check.txt"
test "${PIPESTATUS[0]}" -eq 0
cat > "$evidence/steps.json" <<'J'
{"target":{"version":"fleet-contract-check from this checkout, run against the installed fork at ~/firstmate"},
 "start":"the installed fork and add-ons, with a throwaway HOME and FM_HOME",
 "steps":["run fleet-contract-check against the live fork config and read one line per caller","run the fixture journey that breaks owner-guard and dispatch-resolve and read which caller is named"],
 "result":"every caller prints ok on the installed fleet; a broken caller prints FAIL with its name and the check exits 1; the transcript ends with PASS"}
J
