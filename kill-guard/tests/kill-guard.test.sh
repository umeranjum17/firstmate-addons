#!/usr/bin/env bash
# End to end: install into a throwaway HOME, then drive the installed guard and the installed Claude hook command with
# command strings only. A test signals nothing it did not start: its own sleep children, and fake systemd and herdr
# processes (scripts named like them), are the only targets of a real kill, in cleanup.
# shellcheck disable=SC2016 # the cases are literal commands, never expanded here
set -euo pipefail
unset FM_TASK_ID FM_TASK_INBOX FM_HOME
ADDON=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
T=$(mktemp -d)
FAKES=()
cleanup() {
  for p in "${FAKES[@]}"; do for c in $(pgrep -P "$p" 2>/dev/null || true); do kill "$c" 2>/dev/null || true; done; kill "$p" 2>/dev/null || true; done
  rm -rf -- "$T"
}
trap cleanup EXIT
mkdir -p "$T/home/.claude" "$T/home/.pi/agent" "$T/home/.config/opencode" "$T/bin"
echo '{"env":{"KEEP":"1"},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"other-hook"}]}]}}' > "$T/home/.claude/settings.json"
fail=0
ok() { echo "ok: $*"; }; no() { echo "FAIL: $*"; fail=1; }
inst() { env -u XDG_DATA_HOME HOME="$T/home" "$ADDON/install.sh" "$@"; }

inst --dry-run > "$T/dry.out"
[ ! -e "$T/home/.local/share/fm-kill-guard/guard.mjs" ] && ok "dry run writes nothing" || no "dry run wrote files"
inst > /dev/null && inst > "$T/reinstall.out"
[ "$(grep -c '^unchanged: ' "$T/reinstall.out")" -eq 4 ] && ok "reinstall changes nothing" || no "reinstall not idempotent: $(cat "$T/reinstall.out")"
jq -e '([.hooks.PreToolUse[].hooks[].command] | index("other-hook") == 0) and ([.hooks.PreToolUse[].hooks[].command | select(contains("fm-kill-guard"))] | length == 1) and .env.KEEP == "1"' "$T/home/.claude/settings.json" >/dev/null && ok "claude settings merged once, existing settings kept" || no "claude settings merge"
grep -q 'fm-kill-guard/guard.mjs' "$T/home/.pi/agent/extensions/fm-kill-guard.ts" && grep -q 'fm-kill-guard/guard.mjs' "$T/home/.config/opencode/plugins/fm-kill-guard.js" && ok "pi and opencode adapters installed" || no "adapters not installed"
HOOK=$(jq -r '.hooks.PreToolUse[].hooks[] | select(.command | contains("fm-kill-guard")) | .command' "$T/home/.claude/settings.json")

# The real systemd --user manager, when this host runs one (read only: never signalled).
REAL_SYSD=$(for p in $(pgrep -x systemd 2>/dev/null || true); do tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q -- '--user' && echo "$p"; done | head -1 || true)

# fake <name> <args>: a child of this test named <name>; waits until it has exec'd under that name, then sets FAKE_PID.
fake() {
  printf '#!/bin/bash\nsleep 300; true\n' > "$T/bin/$1"; chmod +x "$T/bin/$1"
  "$T/bin/$1" "${@:2}" >/dev/null 2>&1 &
  FAKE_PID=$!; FAKES+=("$FAKE_PID")
  for _ in $(seq 100); do [ "$(cat "/proc/$FAKE_PID/comm" 2>/dev/null)" = "$1" ] && break; sleep 0.05; done
  [ "$(cat "/proc/$FAKE_PID/comm" 2>/dev/null)" = "$1" ] || { echo "FAIL: fake $1 did not start under its own name"; exit 1; }
}
fake systemd --user; SYSD=$FAKE_PID
fake herdr server; HERDR=$FAKE_PID
sleep 300 >/dev/null 2>&1 & C=$!
sleep 300 >/dev/null 2>&1 & H=$!
sleep 300 >/dev/null 2>&1 & S=$!
FAKES+=("$C" "$H" "$S")

# hook <caller> <command>: the guard as the Claude hook runs it (--caller names the agent); sets rc and err.
hook() {
  jq -n --arg c "$2" '{tool_input:{command:$c}}' > "$T/in.json"
  if err=$(node "$T/home/.local/share/fm-kill-guard/guard.mjs" --runtime claude --caller "$1" < "$T/in.json" 2>&1 >/dev/null); then rc=0; else rc=$?; fi
}
block() { hook "$1" "$2"; if [ "$rc" -eq 2 ] && [[ "$err" == *"BLOCKED by the fleet kill guard"* && "$err" == *"$3"* ]]; then ok "blocked: $2"; else no "not blocked: $2 (rc=$rc) $err"; fi; }
allow() { hook "$1" "$2"; [ "$rc" -eq 0 ] && ok "allowed: $2" || no "blocked: $2 ($err)"; }

block "$$" 'kill 1' 'PID 1 (init)'
block "$$" 'kill -9 1' 'PID 1 (init)'
block "$$" 'kill -s TERM 1' 'PID 1 (init)'
block "$$" "sh -c 'kill -KILL 1'" 'PID 1 (init)'
block "$$" "kill $SYSD" 'the systemd user manager'
block "$$" "kill -9 $HERDR" 'the herdr server'
[ -n "$REAL_SYSD" ] && block "$$" "kill $REAL_SYSD" 'the systemd user manager' || echo "skipped: no real systemd --user on this host, the fake covers it"
block "$$" "pkill -f 'systemd --user'" 'the systemd user manager'
block "$$" 'killall herdr' 'the herdr server'
block "$H" "kill $S" 'which this task did not start'
block "$H" "kill $C" 'which this task did not start'
block "$$" 'kill $X' 'cannot be resolved to processes'
block "$$" 'kill %1' 'cannot be resolved to processes'
block "$$" 'kill -- -1' 'cannot be resolved to processes'
block "$$" 'xargs kill' 'come from xargs'
block "$$" 'pkill -u umer x' 'cannot be resolved to processes'
block "$$" 'kill 99999999' 'no such process'
allow "$$" "kill $C"
allow "$$" 'kill -l'
allow "$$" 'echo kill 1'
allow "$$" 'grep -r kill src'

# The hook command as installed (--caller $PPID): this shell is the agent, so its own sleep child is allowed.
hookrun() { jq -n --arg c "$1" '{tool_input:{command:$c}}' > "$T/in.json"; if sh -c "$HOOK" < "$T/in.json" 2> "$T/err"; then rc=0; else rc=$?; fi; err=$(cat "$T/err"); }
hookrun "kill $C" && ok "installed hook allows own child" || no "installed hook blocked own child: $err"
hookrun 'kill 1'; [ "$rc" -eq 2 ] && [[ "$err" == *"PID 1 (init)"* ]] && ok "installed hook blocks kill 1" || no "installed hook did not block kill 1 (rc=$rc)"
kill "$C" && ok "own child stopped by its owner"

[ "$fail" -eq 0 ] && echo "kill-guard e2e: all passed" || { echo "kill-guard e2e: FAILED"; exit 1; }
