#!/usr/bin/env bash
# run-live-proof.sh: a controlled real route failure recovers with no human. One disposable live lab
# (FM_CHECKOUT/bin/fm-live-lab.sh: a real Claude Haiku lab main and its watcher) gets one real fm-spawn worker on
# pi, pinned to a local provider that answers every call with HTTP 429, and this checkout's watcher installed into a
# lab-only data path. The proof is the lab watcher's own pass moving the worker to Claude Haiku (subscription) and the
# worker finishing its task there. Lab processes use the normal HOME and logins; the lab pi agent dir defines only
# the local provider and holds no credential. Evidence: route.log, screens, the watcher log, the worker's status.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
evidence=${DONE_DONE_EVIDENCE_ROOT:?}
FMC=${FM_CHECKOUT:?set FM_CHECKOUT to a Firstmate checkout}
port=${LAB_429_PORT:-18429} wait=${LAB_WAIT_SECS:-1800} ID=lab429-worker
mkdir -p "$evidence"
work=$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/fm-quota-failover-live.XXXXXX")
ROOT=$work/lab srv=''
done_lab() { [ -z "$srv" ] || kill "$srv" 2>/dev/null; "$FMC/bin/fm-live-lab.sh" down "$ROOT" >"$evidence/lab-down.txt" 2>&1 || true; rm -rf -- "$work"; }
trap done_lab EXIT
log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$evidence/route.log"; }

mkdir -p "$work/pi-agent"
printf '{"providers":{"lab429":{"name":"Lab 429","baseUrl":"http://127.0.0.1:%s/v1","api":"openai-completions","apiKey":"lab-placeholder","models":[{"id":"rl-model","name":"Lab rate-limited model","contextWindow":8000,"maxTokens":1000,"input":["text"],"reasoning":false}]}}}\n' "$port" >"$work/pi-agent/models.json"
python3 -I -c '
import http.server, json, sys, time
class H(http.server.BaseHTTPRequestHandler):
    def _go(self):
        self.rfile.read(int(self.headers.get("content-length") or 0))
        open(sys.argv[2], "a").write(time.strftime("%Y-%m-%dT%H:%M:%SZ ", time.gmtime()) + self.path + " -> 429\n")
        b = json.dumps({"error": {"message": "Rate limit exceeded: too many requests", "type": "rate_limit_error", "code": 429}}).encode()
        self.send_response(429); self.send_header("content-type", "application/json"); self.send_header("content-length", str(len(b))); self.end_headers(); self.wfile.write(b)
    do_POST = do_GET = _go
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()' "$port" "$evidence/provider-429-hits.txt" &
srv=$!

"$FMC/bin/fm-live-lab.sh" up --harness claude --model claude-haiku-5-5 "$ROOT" >"$evidence/lab-up.txt" 2>&1
rec() { sed -n "s/^$1=//p" "$ROOT/.fm-live-lab" | head -n 1; }
LAB=$(rec home) TMUX_DIR=$(rec tmux_dir)
lab_run() { (cd "$LAB" && env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" PATH="$PATH" SHELL="${SHELL:-/bin/bash}" \
  TERM=xterm-256color LANG="${LANG:-en_US.UTF-8}" TMUX_TMPDIR="$TMUX_DIR" TREEHOUSE_ROOT="$ROOT/treehouse" FM_BACKEND=tmux \
  DISABLE_AUTOUPDATER=1 FM_HOME="$LAB" "$@"); }

git init -q -b main "$work/seed" && mkdir -p "$work/seed/notes"
printf 'NOTES = []\n\n\ndef add_note(text):\n    NOTES.append(text)\n    return len(NOTES) - 1\n' >"$work/seed/notes/__init__.py"
git -C "$work/seed" add -A && git -C "$work/seed" -c user.name=lab -c user.email=lab@example.invalid commit -q -m "seed notes"
git clone -q --bare "$work/seed" "$ROOT/origins/notes.git" && git clone -q "$ROOT/origins/notes.git" "$LAB/projects/notes"
printf 'root = "%s"\n' "$ROOT/treehouse" >"$LAB/projects/notes/treehouse.toml"
printf '# Projects\n\n- notes [local-only +yolo] - tiny lab notes library\n' >"$LAB/data/projects.md"
printf '{"rules":[{"when":"Lab work on the notes project.","use":[{"harness":"pi","model":"lab429/rl-model","effort":"low"},{"harness":"claude","model":"claude-haiku-5-5","effort":"low"}]}],"default":[{"harness":"claude","model":"claude-haiku-5-5","effort":"low"}]}\n' >"$LAB/config/crew-dispatch.json"
# shellcheck disable=SC2016 # "$1" belongs to the hook it writes
printf '#!/bin/sh\nprintf "export PI_CODING_AGENT_DIR=%%s\\n" %q >"$1"\n' "$work/pi-agent" >"$LAB/config/launch-env-hook"
chmod +x "$LAB/config/launch-env-hook"
XDG_DATA_HOME=$ROOT/xdg "$repo/quota-failover/install.sh" "$LAB" | tee -a "$evidence/route.log"

lab_run "$LAB/bin/fm-brief.sh" "$ID" notes --mode local-only >/dev/null
sed -i 's|{TASK}|Add count_notes(), which returns how many notes are stored, to notes/__init__.py.|; s|{FIRSTMATE_SPEC}|Implement count_notes(), commit, and report done. Nothing else is in scope.|' "$LAB/data/$ID/brief.md"
lab_run "$LAB/bin/fm-tasks-axi.sh" add "$ID" "lab worker on a rate-limited route" --kind ship --repo notes --priority 3 >/dev/null
# A host tool that hangs at spawn (seen: the pi shim stuck on `pi --help` for 4 h) fails the run instead.
lab_run timeout "${LAB_SPAWN_SECS:-600}" "$LAB/bin/fm-spawn.sh" "$ID" "$LAB/projects/notes" --mode local-only --yolo on --harness pi --model lab429/rl-model --effort low >>"$evidence/route.log" 2>&1
log "spawned $ID on pi lab429/rl-model"
"$FMC/bin/fm-live-lab.sh" say "$ROOT" "Lab note: one worker, $ID, is running; keep watcher supervision on. This lab tests the quota-failover watcher: do not message, relaunch, steer or stop $ID yourself, whatever its screen or status shows. End your turn."

end=$(($(date +%s) + wait)) qlog=$LAB/state/quota-failover.log
until grep -q "^[^ ]* $ID: switched pi lab429/rl-model -> claude claude-haiku-5-5" "$qlog" 2>/dev/null || [ "$(date +%s)" -gt "$end" ]; do
  grep -q 'Error: 429' "$evidence/screen-before.txt" 2>/dev/null ||
    "$FMC/bin/fm-live-lab.sh" pane "$ROOT" --window "fm-$ID" --lines 12 >"$evidence/screen-before.txt" 2>&1 || true
  sleep 15
done
cp "$qlog" "$evidence/quota-failover.log" 2>/dev/null || true
grep -q "$ID: switched" "$evidence/quota-failover.log" 2>/dev/null || { log "FAIL: no move in ${wait}s"; exit 1; }
log "the lab watcher moved $ID: $(grep "$ID: switched" "$evidence/quota-failover.log" | tail -n 1)"
end=$(($(date +%s) + wait))
until grep -q '^done' "$LAB/state/$ID.status" 2>/dev/null || [ "$(date +%s)" -gt "$end" ]; do sleep 15; done
"$FMC/bin/fm-live-lab.sh" pane "$ROOT" --window "fm-$ID" --lines 20 >"$evidence/screen-after.txt" 2>&1 || true
cp "$LAB/state/$ID.status" "$evidence/worker-status.txt"
grep "^harness=\|^model=" "$LAB/state/$ID.meta" >"$evidence/worker-route-after.txt"
grep -q '^done' "$evidence/worker-status.txt" || { log "FAIL: the worker did not finish on its new route"; exit 1; }
log "PASS: $ID finished on $(paste -sd' ' "$evidence/worker-route-after.txt") with no human step"
