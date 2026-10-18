#!/usr/bin/env bash
# End to end: install into a throwaway HOME, then drive the guard, Claude hook and adapters with command strings. Only this
# test's own sleep children and fake systemd and herdr processes are ever signalled.
# shellcheck disable=SC2016 # the cases are literal commands, never expanded here
set -euo pipefail; unset FM_TASK_ID FM_TASK_INBOX FM_HOME
ADDON=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
T=$(mktemp -d); FAKES=()
cleanup() { for p in "${FAKES[@]}"; do pkill -P "$p" 2>/dev/null || true; kill "$p" 2>/dev/null || true; done; rm -rf -- "$T"; }
trap cleanup EXIT
mkdir -p "$T/home/.claude" "$T/home/.pi/agent" "$T/home/.config/opencode" "$T/bin"
echo '{"env":{"KEEP":"1"},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"other-hook"}]}]}}' > "$T/home/.claude/settings.json"
fail=0
ok() { echo "ok: $*"; }; no() { echo "FAIL: $*"; fail=1; }
inst() { env -u XDG_DATA_HOME HOME="$T/home" "$ADDON/install.sh" "$@"; }

inst --dry-run > /dev/null && [ ! -e "$T/home/.local/share/fm-kill-guard/guard.mjs" ] && ok "dry run writes nothing" || no "dry run wrote files"
inst > /dev/null && inst > "$T/re.out"
[ "$(grep -c '^unchanged: ' "$T/re.out")" -eq 4 ] && ok "reinstall changes nothing" || no "reinstall not idempotent"
jq -e '([.hooks.PreToolUse[].hooks[].command] | index("other-hook") == 0) and ([.hooks.PreToolUse[].hooks[].command | select(contains("fm-kill-guard"))] | length == 1) and .env.KEEP == "1"' "$T/home/.claude/settings.json" >/dev/null && ok "claude settings merged, existing kept" || no "claude settings merge"

cat > "$T/adapters.mjs" <<'EOF'
import { spawn } from "node:child_process";
const file = process.argv[2], child = spawn("sleep", ["300"]), hooks = {}, pi = file.endsWith(".ts");
const mod = await import(file);
if (pi) mod.default({ on: (n, h) => (hooks[n] = h) }); else Object.assign(hooks, await mod.FmKillGuard({}));
const run = async (tool, command) => {
  try {
    if (pi) return (await hooks.tool_call({ toolName: tool, input: { command } }))?.reason ?? null;
    await hooks["tool.execute.before"]({ tool }, { args: { command } });
    return null;
  } catch (e) { return e.message; }
};
const out = { kill1: await run("bash", "kill 1"), own: await run("bash", `kill ${child.pid}`), nonBash: await run("read", "kill 1") };
child.kill();
console.log(JSON.stringify(out));
EOF
for a in "pi:$T/home/.pi/agent/extensions/fm-kill-guard.ts" "opencode:$T/home/.config/opencode/plugins/fm-kill-guard.js"; do
  out=$(node "$T/adapters.mjs" "${a#*:}" 2>"$T/adp.err" || true)
  jq -e '(.kill1 | contains("PID 1 (init)")) and .own == null and .nonBash == null' <<<"$out" >/dev/null && ok "${a%%:*} adapter runs the guard" || no "${a%%:*} adapter: $out $(cat "$T/adp.err")"
done
HOOK=$(jq -r '.hooks.PreToolUse[].hooks[] | select(.command | contains("fm-kill-guard")) | .command' "$T/home/.claude/settings.json")

# fake <name> <args>: a child named <name> that has exec'd under that name; sets FAKE_PID.
fake() {
  printf '#!/bin/bash\nsleep 300; true\n' > "$T/bin/$1"; chmod +x "$T/bin/$1"
  "$T/bin/$1" "${@:2}" >/dev/null 2>&1 & FAKE_PID=$!; FAKES+=("$FAKE_PID")
  for _ in $(seq 100); do [ "$(cat "/proc/$FAKE_PID/comm" 2>/dev/null)" = "$1" ] && break; sleep 0.05; done
}
fake systemd --user; SYSD=$FAKE_PID
fake herdr server; HERDR=$FAKE_PID
sleep 300 >/dev/null 2>&1 & C=$!; sleep 300 >/dev/null 2>&1 & H=$!; sleep 300 >/dev/null 2>&1 & S=$!
FAKES+=("$C" "$H" "$S")

# hook <caller> <command>: the guard as the Claude hook runs it; sets rc and err.
hook() {
  jq -n --arg c "$2" '{tool_input:{command:$c}}' > "$T/in.json"
  if err=$(node "$T/home/.local/share/fm-kill-guard/guard.mjs" --caller "$1" < "$T/in.json" 2>&1 >/dev/null); then rc=0; else rc=$?; fi
}
block() { hook "$1" "$2"; if [ "$rc" -eq 2 ] && [[ "$err" == *"BLOCKED by the fleet kill guard"* && "$err" == *"$3"* ]]; then ok "blocked: $2"; else no "not blocked: $2 (rc=$rc) $err"; fi; }
allow() { hook "$1" "$2"; [ "$rc" -eq 0 ] && ok "allowed: $2" || no "blocked: $2 ($err)"; }

block "$$" 'kill 1' 'PID 1 (init)'
block "$$" 'kill -9 1' 'PID 1 (init)'
block "$$" 'kill -s TERM 1' 'PID 1 (init)'
block "$$" 'kill 1 -l' 'PID 1 (init)'
block "$$" 'timeout -s KILL 5 kill -9 1' 'PID 1 (init)'
block "$$" 'env -u HOME kill 1' 'PID 1 (init)'
block "$$" 'k\ill 1' 'PID 1 (init)'
block "$$" "sh -c 'kill -KILL 1'" 'PID 1 (init)'
block "$$" "sh -e -c 'kill 1'" 'PID 1 (init)'
block "$$" "bash -x -c 'kill 1'" 'PID 1 (init)'
block "$$" "kill $SYSD" 'the systemd user manager'
block "$$" "pkill -f 'systemd --user'" 'the systemd user manager'
block "$$" "kill -9 $HERDR" 'the herdr server'
block "$$" 'killall herdr' 'the herdr server'
block "$$" 'pkill herd' 'the herdr server'
block "$$" 'timeout -s TERM 5 killall herdr' 'the herdr server'
block "$$" "pkill 'h[[:lower:]]rdr'" 'cannot be resolved to processes'
block "$$" "pkill 'herdr{,1}'" 'cannot be resolved to processes'
block "$H" "kill $S" 'which this task did not start'
block "$H" "kill $C" 'which this task did not start'
block "$$" 'kill 99999999' 'no such process'
block "$$" 'kill $X' 'cannot be resolved to processes'
block "$$" 'kill %1' 'cannot be resolved to processes'
block "$$" 'kill -- -1' 'cannot be resolved to processes'
block "$$" 'kill -9 -1' 'cannot be resolved to processes'
block "$$" 'kill -s 9 -1' 'cannot be resolved to processes'
block "$$" 'kill -KILL -1' 'cannot be resolved to processes'
block "$$" 'kill -9 -1234' 'cannot be resolved to processes'
block "$$" 'xargs kill' 'come from xargs'
block "$$" 'pkill -u umer x' 'cannot be resolved to processes'
block "$$" 'pkill -x herdr' 'cannot be resolved to processes'
block "$$" 'killall -r herd' 'cannot be resolved to processes'
block "$$" 'killall /usr/bin/herdr' 'cannot be resolved to processes'
block "$$" 'echo $(kill 1)' 'PID 1 (init)'
block "$$" 'echo `kill 1`' 'PID 1 (init)'
block "$$" 'echo $(kill -9 $(pgrep -x herdr))' 'cannot be resolved to processes'
block "$$" 'x=$(kill -9 $(pgrep herdr))' 'cannot be resolved to processes'
block "$$" 'ionice -c3 kill 1' 'PID 1 (init)'
block "$$" 'taskset -c 0 kill 1' 'PID 1 (init)'
block "$$" 'stdbuf -oL kill 1' 'PID 1 (init)'
block "$$" 'doas kill 1' 'PID 1 (init)'
block "$$" 'if false; then :; elif kill 1; then :; fi' 'PID 1 (init)'
block "$$" 'case 1 in 1) kill 1;; esac' 'PID 1 (init)'
block "$$" 'f() { kill 1; }; f' 'PID 1 (init)'
allow "$$" "kill $C"
allow "$$" "kill $C 2>/dev/null"
allow "$$" "kill $C 2>&1"
allow "$$" 'kill -l'
allow "$$" 'pkill nomatch_zz_no_such'
allow "$$" 'echo kill 1'
allow "$$" 'grep -r kill src'

hookrun() { jq -n --arg c "$1" '{tool_input:{command:$c}}' > "$T/in.json"; if sh -c "$HOOK" < "$T/in.json" 2> "$T/err"; then rc=0; else rc=$?; fi; err=$(cat "$T/err"); }
hookrun "kill $C" && ok "installed hook allows own child" || no "installed hook blocked own child: $err"
hookrun 'kill 1'; [ "$rc" -eq 2 ] && [[ "$err" == *"PID 1 (init)"* ]] && ok "installed hook blocks kill 1" || no "installed hook did not block kill 1"

[ "$fail" -eq 0 ] && echo "kill-guard e2e: all passed" || { echo "kill-guard e2e: FAILED"; exit 1; }
