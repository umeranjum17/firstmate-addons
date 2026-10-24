#!/usr/bin/env bash
# Live proof journey: Lookout shows this fleet's real data. Serves lookout-firstmate on the real home (read-only) on a spare port,
# points a lookout clone at it on another, and captures the screens the adapter fills at 390 px light and 1440 px dark into
# $DONE_DONE_EVIDENCE_ROOT, with the document's counts. FM_HOME is the home to read, LOOKOUT_DIR a lookout clone.
set -Eeuo pipefail
: "${FM_HOME:?}" "${LOOKOUT_DIR:?}" "${DONE_DONE_EVIDENCE_ROOT:?}"
here=$(cd "$(dirname "$0")" && pwd)
export CHROME_DEVTOOLS_AXI_SESSION=lookout-adapter-proof-$$
tmp=$(mktemp -d)
pids=()
cleanup() {
  chrome-devtools-axi stop >/dev/null 2>&1 || true
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  rm -rf -- "$tmp"
}
trap cleanup EXIT
free_port() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
ap=$(free_port); lp=$(free_port)
"$here/lookout-firstmate" --home "$FM_HOME" --no-build --serve --port "$ap" >"$tmp/adapter.log" 2>&1 & pids+=("$!")
(cd "$LOOKOUT_DIR" && exec node server.js --source "http://127.0.0.1:$ap/fleet.json" --port "$lp" >"$tmp/lookout.log" 2>&1) & pids+=("$!")
for _ in $(seq 50); do curl -fs "http://127.0.0.1:$lp/api/fleet" -o "$tmp/api.json" && break; sleep 0.2; done
python3 - "$tmp/api.json" >"$DONE_DONE_EVIDENCE_ROOT/document.txt" <<'P'
import json, sys
f = json.load(open(sys.argv[1]))['fleet']
print(f['name'], '| lists:', ', '.join(f'{k} {len(v)}' for k, v in f.items() if isinstance(v, list)))
assert f['name'] != 'Sample fleet' and f['lanes'] and f['quota'] and f['merges']
P
for shot in "overview 390 844 light" "lanes 390 844 light" "flow 1440 900 dark" "capacity 1440 900 dark"; do
  read -r s w h theme <<<"$shot"
  chrome-devtools-axi open "http://127.0.0.1:$lp/?theme=$theme#/$s" >/dev/null
  chrome-devtools-axi resize "$w" "$h" >/dev/null
  chrome-devtools-axi wait 1500 >/dev/null
  chrome-devtools-axi screenshot "$DONE_DONE_EVIDENCE_ROOT/$s-$w-$theme.png" >/dev/null
done
