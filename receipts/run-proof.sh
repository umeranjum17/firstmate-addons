#!/usr/bin/env bash
# run-proof.sh: the receipt-candidate hook proof for done-done. Runs the receipts hook journey, which drives the
# real fork bin/fm-pr-check.sh with this add-on's fm_receipts_pr_candidate, and keeps its transcript as evidence.
# FM_TEST_FORK names a read-only Firstmate checkout (default ~/firstmate); nothing in it is changed.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
evidence=${DONE_DONE_EVIDENCE_ROOT:?}
mkdir -p "$evidence"
export FM_TEST_FORK=${FM_TEST_FORK:-$HOME/firstmate}
bash "$repo/receipts/tests/receipts-hook-e2e.sh" 2>&1 | tee "$evidence/receipt-candidate.txt"
test "${PIPESTATUS[0]}" -eq 0
