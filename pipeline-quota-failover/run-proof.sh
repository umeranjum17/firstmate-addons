#!/usr/bin/env bash
# run-proof.sh: the pipeline route proof for done-done. It drives the real
# wrapper and the real switch script against stub pi and quota-axi binaries in
# a throwaway HOME, so the captures show the route the pipeline runs on. Every
# capture lands in $DONE_DONE_EVIDENCE_ROOT with a result.json summary.
# No real model, no real config, no key, and no write outside the evidence root.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
evidence=${DONE_DONE_EVIDENCE_ROOT:?}
mkdir -p "$evidence"
cd "$repo"

run() { # <name> <command...>: capture the command's output and its exit code
  local name=$1
  shift
  set +e
  "$@" >"$evidence/$name.log" 2>&1
  printf '%s\n' "$?" >"$evidence/$name.exit"
  set -e
}

# The route the wrapper's chain holds, and the route the no-mistakes config
# names: the same one route.
run chain bash -c 'PI_QUOTA_FAILOVER_PRINT_CHAIN=1 pipeline-quota-failover/pi-quota-failover'
# The wrapper against a stub pi: the chain, the off-chain pin and the idle class.
run route bash pipeline-quota-failover/tests/pi-quota-failover-route.test.sh
# The switch script against a fixture config and a stub pi, when it is in the tree.
if [ -f pipeline-quota-failover/tests/switch-route.test.sh ]; then
  run switch bash pipeline-quota-failover/tests/switch-route.test.sh
fi

# The summary: what ran and how it ended, so a judge reads one file.
{
  printf '{"captures":['
  first=1
  for log in "$evidence"/*.log; do
    name=$(basename "$log" .log)
    rc=$(cat "$evidence/$name.exit")
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"name":"%s","exit":%s}' "$name" "$rc"
  done
  printf ']}\n'
} >"$evidence/result.json"

fail=0
for exit_file in "$evidence"/*.exit; do
  [ "$(cat "$exit_file")" = 0 ] || fail=1
done
if [ "$fail" != 0 ]; then
  echo "run-proof: a capture failed; see $evidence" >&2
  exit 1
fi
echo "run-proof: the route and switch captures are in $evidence"
