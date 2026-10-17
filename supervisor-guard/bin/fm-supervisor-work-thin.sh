#!/usr/bin/env bash
# Thin PreToolUse guard for the supervisor-work rules (fm-supervisor-work-thin-policy.mjs).
# The primary-home scope and shell lexer come from the Firstmate checkout in FM_CODE_ROOT,
# so nothing upstream is copied here. Inert outside a primary home; fail-open on failure.
#
# Usage: FM_CODE_ROOT=<checkout> FM_HOME=<home> bin/fm-supervisor-work-thin.sh [--claude] [--command '<cmd>']
# Without --command it reads a PreToolUse JSON payload on stdin. DENY exits 2 with a deny
# object on stderr (and on stdout unless --claude); ALLOW and every failure exit 0.
set -u

have() { command -v "$1" >/dev/null 2>&1; }

CMD=""
CMD_SET=0
CLAUDE_MODE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --command) [[ $# -gt 1 ]] || exit 0; CMD=$2; CMD_SET=1; shift 2 ;;
    --claude) CLAUDE_MODE=1; shift ;;
    *) exit 0 ;;
  esac
done

if [[ $CMD_SET -eq 0 ]]; then
  PAYLOAD=$(cat 2>/dev/null) || exit 0
  [[ -n $PAYLOAD ]] || exit 0
  have jq || exit 0
  CMD=$(printf '%s' "$PAYLOAD" | jq -r '.toolInput.command // .tool_input.command // empty' 2>/dev/null) || exit 0
fi
[[ -n $CMD ]] || exit 0

# Superset prefilter, transport only: quoting bytes are folded out, and a command
# with an ANSI-C or locale quote is always judged, because the policy decodes those.
FOLDED=${CMD//[\\\"\']/}
case "$FOLDED" in
  *no-mistakes*|*sleep*|*herdr*|*tmux*) ;;
  *) case "$CMD" in *\$\'*|*\$\"*) ;; *) exit 0 ;; esac ;;
esac

CODE_ROOT=${FM_CODE_ROOT:-}
HOME_ROOT=${FM_HOME:-}
[[ -n $CODE_ROOT && -n $HOME_ROOT ]] || exit 0
[[ -f $CODE_ROOT/bin/fm-primary-scope-lib.sh ]] || exit 0

# The checkout's scope library decides whether this is a genuine primary home.
# shellcheck disable=SC1090
. "$CODE_ROOT/bin/fm-primary-scope-lib.sh"
fm_primary_scope_matches "$HOME_ROOT" "$HOME_ROOT/state" || exit 0
POLICY_ARGS=(--code-root "$CODE_ROOT" --command "$CMD")
fm_root_is_secondmate_home "$HOME_ROOT" && POLICY_ARGS+=(--secondmate)

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || exit 0
POLICY="$HERE/fm-supervisor-work-thin-policy.mjs"
have node || exit 0
[[ -f $POLICY ]] || exit 0

VERDICT=$(node "$POLICY" "${POLICY_ARGS[@]}" 2>/dev/null) || exit 0
IFS=$'\t' read -r DECISION RULE REASON <<< "$VERDICT"
[[ $DECISION == deny && -n $RULE && -n $REASON ]] || exit 0

have jq || exit 0
MESSAGE="[$RULE] $REASON"
jq -nc --arg m "$MESSAGE" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny"}, systemMessage: $m}' >&2
[[ $CLAUDE_MODE -eq 1 ]] || jq -nc --arg m "$MESSAGE" '{decision: "deny", reason: $m}'
exit 2
