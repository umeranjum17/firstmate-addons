#!/usr/bin/env bash
# Behavior tests for bin/fm-supervisor-work-thin.sh over a primary checkout, a marked
# secondmate home and a linked worker worktree. The Firstmate checkout (FM_CODE_ROOT, or
# else fetched read-only at the pinned upstream commit) supplies the scope and the lexer.
set -u

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
THIN="$ROOT/bin/fm-supervisor-work-thin.sh"
UPSTREAM_SHA=07912680c1cdedc91018a8df1c798e86fbe1cac5
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/supervisor-work-thin.XXXXXX")
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT

have() { command -v "$1" >/dev/null 2>&1; }
have jq || { echo "skip: jq missing"; exit 0; }
have node || { echo "skip: node missing"; exit 0; }

fail() { printf 'not ok: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok: %s\n' "$*"; }

checkout() {
  if [ -n "${FM_CODE_ROOT:-}" ]; then printf '%s\n' "$FM_CODE_ROOT"; return; fi
  local src="$TMP_ROOT/firstmate"
  mkdir -p "$src"
  git init -q "$src" || fail "cannot init the upstream fetch"
  git -C "$src" fetch -q --depth 1 https://github.com/kunchenguid/firstmate.git "$UPSTREAM_SHA" \
    || fail "cannot fetch upstream firstmate at $UPSTREAM_SHA"
  git -C "$src" checkout -q FETCH_HEAD || fail "cannot check out upstream firstmate"
  printf '%s\n' "$src"
}

CODE=$(checkout)
[ -f "$CODE/bin/fm-arm-command-policy.mjs" ] || fail "no shell lexer under $CODE"
[ -f "$CODE/bin/fm-primary-scope-lib.sh" ] || fail "no scope library under $CODE"

PRIMARY=$TMP_ROOT/primary
mkdir -p "$PRIMARY/bin" "$PRIMARY/state"
printf '# primary fixture\n' > "$PRIMARY/AGENTS.md"
printf 'keep\n' > "$PRIMARY/bin/keep"
git init -q "$PRIMARY"
git -C "$PRIMARY" add -A
git -C "$PRIMARY" -c user.name=test -c user.email=test@example.com commit -q -m fixture
SECOND=$TMP_ROOT/secondmate
cp -R "$PRIMARY" "$SECOND"
printf 'lead\n' > "$SECOND/.fm-secondmate-home"
WORKER=$TMP_ROOT/worker
git -C "$PRIMARY" worktree add -q "$WORKER" -b worker
mkdir -p "$WORKER/state"

RC=0
OUT=""
ERR=""
run() {  # <home> <args...>: sets RC, OUT and ERR
  local home=$1
  shift
  RC=0
  OUT=$(FM_CODE_ROOT="$CODE" FM_HOME="$home" "$THIN" "$@" 2> "$TMP_ROOT/err") || RC=$?
  ERR=$(cat "$TMP_ROOT/err")
}

expect_deny() {  # <label> <home> <rule> <command>
  run "$2" --claude --command "$4"
  [ "$RC" -eq 2 ] || fail "$1: want deny (exit 2), got $RC"
  [ -z "$OUT" ] || fail "$1: --claude deny must leave stdout empty, got: $OUT"
  case "$ERR" in *"[$3]"*) ;; *) fail "$1: deny reason lacks [$3]: $ERR" ;; esac
  pass "$1"
}

expect_allow() {  # <label> <home> <command>
  run "$2" --claude --command "$3"
  [ "$RC" -eq 0 ] || fail "$1: want allow (exit 0), got $RC: $ERR"
  [ -z "$OUT$ERR" ] || fail "$1: allow must be silent, got: $OUT$ERR"
  pass "$1"
}

expect_deny "a supervisor never drives a crew-owned run" "$PRIMARY" supervisor-no-mistakes-run 'no-mistakes axi run --wait'
expect_deny "a global flag does not hide respond" "$PRIMARY" supervisor-no-mistakes-run 'no-mistakes --json axi respond --action fix'
expect_allow "status stays allowed" "$PRIMARY" 'no-mistakes axi status'
expect_deny "a sleep past the turn budget is a poll" "$PRIMARY" supervisor-poll-in-turn 'sleep 110; no-mistakes axi status'
expect_allow "a short sleep is allowed" "$PRIMARY" 'sleep 30'
expect_deny "a loop around a sleep is a poll" "$PRIMARY" supervisor-poll-in-turn 'for i in 1 2; do sleep 5; done'
expect_deny "a secondmate lead never types into a pane" "$SECOND" supervisor-pane-typing 'herdr pane send-text w1 hi'
expect_allow "a primary may type into a pane" "$PRIMARY" 'herdr pane send-text w1 hi'
expect_allow "a linked worker worktree is inert" "$WORKER" 'sleep 110; no-mistakes axi run'
expect_allow "malformed shell fails open" "$PRIMARY" 'sleep 110; echo "unterminated'

PAYLOAD='{"tool_input":{"command":"no-mistakes axi run --wait"}}'
RC=0
OUT=$(printf '%s' "$PAYLOAD" | FM_CODE_ROOT="$CODE" FM_HOME="$PRIMARY" "$THIN" 2> "$TMP_ROOT/err") || RC=$?
[ "$RC" -eq 2 ] || fail "stdin payload: want deny (exit 2), got $RC"
case "$OUT" in *'"decision":"deny"'*) ;; *) fail "stdin payload: no Grok deny object on stdout: $OUT" ;; esac
pass "a stdin PreToolUse payload is judged and denied"

RC=0
OUT=$(env -u FM_CODE_ROOT FM_HOME="$PRIMARY" "$THIN" --command 'no-mistakes axi run' 2> "$TMP_ROOT/err") || RC=$?
[ "$RC" -eq 0 ] && [ -z "$OUT" ] || fail "no checkout must fail open, got $RC: $OUT"
pass "a missing checkout fails open"

printf 'ok: all supervisor-work thin checks passed\n'
