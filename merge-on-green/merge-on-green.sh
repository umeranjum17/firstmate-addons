#!/usr/bin/env bash
# merge-on-green watcher check: merge a yolo task's PR through bin/fm-pr-merge.sh once its required
# checks are green, so the merge wait after green (about 21 min per change) disappears.
# Usage: merge-on-green.sh check <fm-home>
#
# Per home, for each state/<task>.meta with yolo=on and a recorded pr= and pr_head=, it acts only when the
# task's resolved state (bin/fm-crew-state.sh <task>) says checks green / PR ready. Then, in this order and
# as separate sequential commands, never piped and never in parallel:
#   1. FM_HOME=<home> fm-checks-lint.sh <PR URL> <home>/data/<task> - require a PASS in its output.
#   2. state/<task>.run-receipt.json - require verdict PASS, head == pr_head, spawn_gen == the meta's spawn_gen.
#   3. FM_HOME=<home> bin/fm-pr-merge.sh <task> <PR URL> - never --auto, never gh merge directly.
# Any refusal or FAIL: one wake line naming the task, the PR URL and the first refusal reason, so the lead
# acts; the refusal is remembered per task+head+reason+receipt state and repeats stay silent until pr_head,
# the run receipt or the reason changes. A merge: one wake line with the verified merged URL, so the lead
# does the post-merge steps (install from main, teardown).
# One merge attempt per task per head: the attempted head and the last gate refusal are remembered in this
# add-on's own data dir (<home>/data/fm-merge-on-green/<task>.head, <task>.refused), never in state/.
# Nothing is printed when nothing happened.
# Every command is bounded with timeout, so the check finishes well within FM_CHECK_TIMEOUT.
set -u
[ "$#" -eq 2 ] && [ "$1" = check ] && [ -d "$2/state" ] || { echo "usage: merge-on-green.sh check <fm-home>" >&2; exit 2; }
FMH=$(cd "$2" && pwd -P)
STATE=$FMH/state
LINT=${FM_MOG_CHECKS_LINT:-/home/umer/firstmate/config/fm-checks-lint.sh}
DATA=$FMH/data/fm-merge-on-green
umask 077
# One third of the watcher's per-check bound per command (floor 5s), and the whole check stops
# at 80% of it: the watcher kills at FM_CHECK_TIMEOUT and a check killed mid-merge helps nobody.
BUDGET=$(( ${FM_CHECK_TIMEOUT:-30} / 3 )); [ "$BUDGET" -ge 5 ] || BUDGET=5
START=$(date +%s)
DEADLINE=$(( START + ${FM_CHECK_TIMEOUT:-30} * 4 / 5 ))

meta_get() { # <meta-file> <key> -> last value, the same rule fm_meta_get applies
  local line value=''
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "$2="*) value=${line#*=} ;; esac
  done < "$1"
  printf '%s' "$value"
}

first_reason() { # first non-empty line of a command's output, trimmed to keep the wake line short
  local r
  r=$(printf '%s' "$1" | sed '/^[[:space:]]*$/d' | head -1)
  [ -n "$r" ] || r="exit code ${2:-?} with no output"
  [ "${#r}" -le 140 ] || r=${r:0:137}'...'
  printf '%s' "$r"
}

refuse() { # <reason> <receipt-stamp>: the wake line prints once per task+head+reason+receipt state,
  # remembered like the merge path in <task>.refused; silent while all three hold.
  [ "$(cat "$DATA/$task.refused" 2>/dev/null)" = "$(printf '%s\n%s\n%s\n' "$pr_head" "$1" "$2")" ] && return 0
  echo "merge-on-green: NOT merging $task $pr: $1"
  mkdir -p "$DATA" 2>/dev/null
  printf '%s\n%s\n%s\n' "$pr_head" "$1" "$2" > "$DATA/$task.refused" 2>/dev/null || :
}

for m in "$STATE"/*.meta; do
  [ -f "$m" ] || exit 0
  task=$(basename "$m" .meta)
  case "$task" in [A-Za-z0-9]*) ;; *) continue ;; esac
  yolo=$(meta_get "$m" yolo); pr=$(meta_get "$m" pr); pr_head=$(meta_get "$m" pr_head); gen=$(meta_get "$m" spawn_gen)
  [ "$yolo" = on ] || continue
  [ -n "$pr" ] && [ -n "$pr_head" ] || continue
  # One merge attempt per head: a head already attempted (merged or refused) is never retried.
  [ "$(cat "$DATA/$task.head" 2>/dev/null)" = "$pr_head" ] && continue
  [ "$(date +%s)" -lt "$DEADLINE" ] || exit 0

  # Gate: the task's resolved state must say checks green / PR ready. "PR merged" means the work
  # already landed; nothing happened, so nothing is printed.
  cs=$(FM_HOME="$FMH" timeout "$BUDGET" "$FMH/bin/fm-crew-state.sh" "$task" 2>/dev/null) || continue
  case "$cs" in
    *"checks green: PR ready"*|*"checks green: PR held for merge"*) ;;
    *) continue ;;
  esac

  # 1. The evidence gate, run as its own command, must print PASS.
  lint_out=$(FM_HOME="$FMH" timeout "$BUDGET" "$LINT" "$pr" "$FMH/data/$task" 2>&1); lint_rc=$?
  if [ "$lint_rc" -ne 0 ] || ! printf '%s\n' "$lint_out" | grep -q 'PASS'; then
    refuse "checks lint refused: $(first_reason "$lint_out" "$lint_rc")" ''
    continue
  fi

  # 2. The completion receipt must be a PASS for exactly this head and spawn generation.
  rcpt=$STATE/$task.run-receipt.json
  if [ ! -f "$rcpt" ]; then
    refuse "no run receipt at state/$task.run-receipt.json" ''
    continue
  fi
  if ! command -v jq >/dev/null 2>&1; then
    refuse "jq is unavailable, cannot read the run receipt" ''
    continue
  fi
  rstamp=$(cksum < "$rcpt" 2>/dev/null)
  verdict=$(timeout "$BUDGET" jq -r '.verdict // ""' "$rcpt" 2>/dev/null); jq_rc=$?
  rhead=$(timeout "$BUDGET" jq -r '.head // ""' "$rcpt" 2>/dev/null)
  rgen=$(timeout "$BUDGET" jq -r '.spawn_gen // ""' "$rcpt" 2>/dev/null)
  if [ "$jq_rc" -ne 0 ] || [ -z "$verdict$rhead$rgen" ]; then
    refuse "run receipt is unreadable JSON" "$rstamp"
    continue
  fi
  if [ "$verdict" != PASS ]; then
    refuse "run receipt verdict is ${verdict:-empty}, not PASS" "$rstamp"
    continue
  fi
  if [ "$rhead" != "$pr_head" ]; then
    refuse "run receipt head ${rhead:-empty} != meta pr_head" "$rstamp"
    continue
  fi
  if [ "$rgen" != "$gen" ]; then
    refuse "run receipt spawn_gen ${rgen:-empty} != meta spawn_gen" "$rstamp"
    continue
  fi

  # 3. Merge through fm-pr-merge.sh only: its own live green check, head pin and refusal rules stay in
  # charge, no --auto is ever passed. The attempted head is recorded first, so a check killed between
  # record and merge cannot retry the same head next sweep.
  # A merge killed by the watcher after the head was recorded burns it with no wake line:
  # start one only when it still fits inside the watcher's whole-check bound.
  [ $(( $(date +%s) + BUDGET + 1 )) -le $(( START + ${FM_CHECK_TIMEOUT:-30} )) ] || exit 0
  mkdir -p "$DATA" || { echo "merge-on-green: NOT merging $task $pr: cannot write $DATA"; continue; }
  printf '%s\n' "$pr_head" > "$DATA/$task.head" || { echo "merge-on-green: NOT merging $task $pr: cannot write $DATA/$task.head"; continue; }
  merge_out=$(FM_HOME="$FMH" timeout "$BUDGET" "$FMH/bin/fm-pr-merge.sh" "$task" "$pr" 2>&1); merge_rc=$?
  if [ "$merge_rc" -eq 0 ]; then
    echo "merge-on-green: merged $task $pr through fm-pr-merge; lead: run the post-merge steps (install from main, teardown)"
  else
    echo "merge-on-green: NOT merging $task $pr: fm-pr-merge refused: $(first_reason "$merge_out" "$merge_rc")"
  fi
done
