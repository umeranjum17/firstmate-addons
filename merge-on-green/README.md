# merge-on-green

A yolo task's PR merges itself once the required checks are green, instead of waiting for the
lead to notice and merge (about 21 minutes per change).

`merge-on-green/merge-on-green.sh check <fm-home>` is the watcher check. For each
`state/<task>.meta` in that home with `yolo=on` and a recorded `pr=` and `pr_head=`, it acts only
when the task's resolved state (`bin/fm-crew-state.sh <task>`) says checks green / PR ready. Then
it runs, in this order and as separate sequential commands, never piped and never in parallel:

1. `FM_HOME=<home> /home/umer/firstmate/config/fm-checks-lint.sh <PR URL> <home>/data/<task>` —
   the evidence gate must print PASS.
2. `state/<task>.run-receipt.json` must read verdict PASS, head == the meta's `pr_head`, and
   spawn_gen == the meta's `spawn_gen`.
3. `FM_HOME=<home> <home>/bin/fm-pr-merge.sh <task> <PR URL>` — the merge goes through
   `bin/fm-pr-merge.sh` only, so its live green check, head pin and refusal rules stay in charge.
   No `--auto` is ever passed, `gh merge` is never called directly, and a refusal is never
   bypassed.

Any refusal or FAIL prints one wake line naming the task, the PR URL and the first refusal reason,
so the lead acts; the refusal is remembered per task+head+reason+receipt state in
`<home>/data/fm-merge-on-green/<task>.refused` (never in `state/`), and repeats stay silent until
`pr_head`, the run receipt or the reason changes. An evidence gate or the merge this check itself kills
on its timeout wakes truthfully once per task+head+reason like a refusal, records no merge attempt, and
is retried next sweep; a `fm-crew-state` timeout stays silent and is retried next sweep. A merge prints one
wake line with the verified merged URL, so the lead runs the post-merge steps (install from main,
teardown). Nothing is printed
when nothing happened. One merge attempt per task per head: the attempted head is remembered in
`<home>/data/fm-merge-on-green/<task>.head`, so a refused head stays quiet until the lead pushes a
new one. Every command is bounded with `timeout` (a third of `FM_CHECK_TIMEOUT` each, floor 5 s):
gate commands start only before 80% of the bound, a merge only when it fits inside the whole bound,
so the watcher's kill can at worst cut a gate command (harmlessly retried next sweep), never a
merge.

## Install

`merge-on-green/install.sh [--dry-run] <fm-home>` copies `merge-on-green.sh` to
`${XDG_DATA_HOME:-~/.local/share}/fm-merge-on-green/`, writes the shim
`state/merge-on-green.check.sh` (mode 0700), and registers it with `bin/fm-check-register.sh`.
It is idempotent; `--dry-run` prints the steps and writes nothing. Run it once per home; the lead
installs it from merged main, never from a branch.

## Test

`merge-on-green/tests/merge-on-green.test.sh` drives the check end to end against a fixture home
with a stub `fm-crew-state.sh` and `fm-pr-merge.sh` in the home's `bin/` and a stub
`fm-checks-lint.sh` behind `FM_MOG_CHECKS_LINT`. It covers: `yolo=off` skipped, lint FAIL -> no
merge and one wake line, receipt head mismatch -> no merge, all gates pass -> `fm-pr-merge` called
once with exactly the task and PR URL, the same head never retried after a merge or a refusal, a
gate refusal waking once per task+head+reason+receipt state with repeats silent and a changed
reason, receipt or head waking again, and `install.sh` in both `--dry-run` and real mode (register
runs with `FM_STATE_OVERRIDE` unset, the shim execs the installed script with the home).
