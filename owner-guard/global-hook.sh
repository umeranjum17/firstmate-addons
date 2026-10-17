#!/usr/bin/env bash
# fm-owner-guard global hook template (install.sh stamps one copy per hook
# name, replacing __NAME__). Runs the owner-details guard first (__NAME__
# runs it only for pre-commit and pre-push), then chains the previous global
# hooks dir's hook and the repository's own hook, so repos with their own
# hooks keep working — including bare repos' server-side hooks, which a
# global hooksPath would otherwise hide. Never touches repo-local
# core.hooksPath. Pre-push and the stdin-fed receive hooks (pre-receive,
# post-receive, proc-receive, reference-transaction) replay git's input to
# every chained hook on stdin.
set -u -o pipefail
unset CDPATH
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
NAME=__NAME__
PREV=$(cat "$HERE/prev-hooks-path" 2>/dev/null || true)
if [ "$NAME" = pre-commit ]; then
  "$HERE/owner-guard" pre-commit "$@" || exit $?
else
  # Pre-push and the receive hooks replay git's stream to everything below
  # (the guard only runs for pre-push): receive stdin is ref lines, not a
  # push range, so the guard must never scan it. The here-string replay is
  # byte-identical (cat strips the trailing newline, <<< adds it back) and
  # lets the consumer's exit status win even when it stops reading early.
  case $NAME in
  pre-push|pre-receive|post-receive|proc-receive|reference-transaction)
    INPUT=$(cat)
    FED_STDIN=1 ;;
  esac
  if [ "$NAME" = pre-push ]; then
    if [ -n "$INPUT" ]; then
      "$HERE/owner-guard" pre-push "$@" <<<"$INPUT" || exit $?
    else
      "$HERE/owner-guard" pre-push "$@" || exit $?
    fi
  fi
fi
chain() { # chain <hookfile> [args...]: run it when executable and not this wrapper.
  local f=$1
  shift
  [ -n "$f" ] && [ -f "$f" ] && [ -x "$f" ] || return 0
  [ "$f" != "$HERE/hooks/$NAME" ] || return 0
  if [ -n "${FED_STDIN:-}" ] && [ -n "${INPUT:-}" ]; then
    "$f" "$@" <<<"$INPUT" || exit $?
  else
    "$f" "$@" || exit $?
  fi
}
[ -n "$PREV" ] && [ -d "$PREV" ] && chain "$PREV/$NAME" "$@"
COMMON=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
[ -n "$COMMON" ] && chain "$COMMON/hooks/$NAME" "$@"
exit 0
