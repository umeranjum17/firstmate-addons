#!/usr/bin/env bash
# The supervisor-work guard end to end: install into a throwaway HOME, run the
# installed hook against a fixture home, a linked worktree and a worker session,
# then uninstall. Needs a Firstmate checkout (FM_CODE_ROOT) for the scope predicate
# and the shell lexer, and fails (not skips) without jq or node.
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CK=${FM_CODE_ROOT:-}
[ -n "$CK" ] && [ -f "$CK/bin/fm-primary-scope-lib.sh" ] \
  || { echo "FAIL: set FM_CODE_ROOT to a Firstmate checkout"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node is required"; exit 1; }

TMP=$(mktemp -d)
on_exit() {
  rm -rf -- "$TMP"
}
trap on_exit EXIT
export HOME=$TMP/home XDG_DATA_HOME=$TMP/xdg
mkdir -p "$HOME" "$XDG_DATA_HOME"
DEST=$XDG_DATA_HOME/fm-supervisor-guard
HOOK=$DEST/fm-supervisor-work-pretool-check.sh
SETTINGS=$HOME/.claude/settings.json
FAILS=0

check() {
  if "$@"; then echo "PASS: $CHECK_NAME"; else echo "FAIL: $CHECK_NAME"; FAILS=$((FAILS + 1)); fi
}

# A fixture Firstmate home: a plain checkout with AGENTS.md, bin and state, and the
# checkout's scope lib and lexer linked in, as the real home has them.
FMH=$(cd "$TMP" && pwd -P)/fmhome
mkdir -p "$FMH/bin" "$FMH/state"
git init -q "$FMH"
: > "$FMH/AGENTS.md"
ln -s "$CK/bin/fm-primary-scope-lib.sh" "$FMH/bin/fm-primary-scope-lib.sh"
ln -s "$CK/bin/fm-arm-command-policy.mjs" "$FMH/bin/fm-arm-command-policy.mjs"

# run_hook <command> <session-dir> [--claude]: the installed hook on one Bash payload.
run_hook() {
  local payload
  payload=$(jq -nc --arg c "$1" --arg d "$2" '{tool_input: {command: $c}, cwd: $d}')
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$2" "$HOOK" ${3:+"$3"}
}

CHECK_NAME="dry run writes nothing"
"$HERE/install.sh" --dry-run "$FMH" >/dev/null
check test ! -e "$SETTINGS" && check test ! -e "$DEST"

CHECK_NAME="install copies the guard and records the home"
"$HERE/install.sh" "$FMH" >/dev/null
check test -x "$HOOK" && check test "$(cat "$DEST/home")" = "$FMH"

CHECK_NAME="install registers one Bash PreToolUse hook"
check jq -e '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[] | select(.command | contains("fm-supervisor-work-pretool-check.sh"))] | length == 1' "$SETTINGS"

CHECK_NAME="reinstall is idempotent"
cp "$SETTINGS" "$TMP/settings.once"
"$HERE/install.sh" "$FMH" >/dev/null
check cmp -s "$SETTINGS" "$TMP/settings.once"

CHECK_NAME="primary session denies a no-mistakes run with exit 2 and stdout empty"
out=$(run_hook 'no-mistakes axi run --intent x' "$FMH" --claude 2>"$TMP/err")
rc=$?
check test "$rc" = 2 && check test -z "$out" && check grep -q supervisor-no-mistakes-run "$TMP/err"

CHECK_NAME="no-mistakes status stays allowed in the primary session"
run_hook 'no-mistakes axi status' "$FMH" --claude >/dev/null 2>&1
check test "$?" = 0

CHECK_NAME="a sleep of 60 seconds or less is allowed, a longer one is denied"
run_hook 'sleep 30' "$FMH" --claude >/dev/null 2>&1
check test "$?" = 0
run_hook 'sleep 120' "$FMH" --claude >/dev/null 2>&1
check test "$?" = 2

CHECK_NAME="without --claude the deny is also written to stdout"
out=$(run_hook 'sleep 120' "$FMH" 2>/dev/null)
check jq -e '.decision == "deny"' <<< "$out"

CHECK_NAME="a linked worktree of the home is a worker and stays allowed"
git -C "$FMH" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
git -C "$FMH" worktree add -q "$TMP/wt" -b wt-check
run_hook 'no-mistakes axi run --intent x' "$TMP/wt" >/dev/null 2>&1
check test "$?" = 0

CHECK_NAME="a session outside the registered home stays allowed"
run_hook 'sleep 120' "$TMP" >/dev/null 2>&1
check test "$?" = 0

CHECK_NAME="uninstall removes the hook and the installed files"
"$HERE/uninstall.sh" >/dev/null
check jq -e '[.hooks.PreToolUse[]?.hooks[]?.command? | select(contains("fm-supervisor-work-pretool-check.sh"))] | length == 0' "$SETTINGS"
check test ! -e "$DEST"

CHECK_NAME="uninstall is idempotent"
"$HERE/uninstall.sh" >/dev/null
check test "$?" = 0

if [ "$FAILS" -gt 0 ]; then
  echo "$FAILS check(s) failed"
  exit 1
fi
echo "all supervisor-work guard checks passed"
