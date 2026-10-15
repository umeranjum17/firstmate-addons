# firstmate-addons

Fleet dashboard and add-ons for running a fleet of coding agents.

## merge-card

Every merge runs done-done and posts one evidence card to a sign-off board, with nobody posting by hand.

`merge-card/merge-card` is one bash script with two subcommands:

- `merge-card gate <task-id> <worktree|-> <head|-> <pr-url|->` runs `done-done check --from <source> --judge --json` in the task's worktree, where `<source>` is the pull request when there is one and `$FM_HOME/data/<task-id>/checks.md` otherwise.
  It prints the verdict and saves it for the card in `$FM_HOME/data/<task-id>/merge-card.json`.
  It is report only: it always exits 0, so it never refuses a merge the checks lint passes.
  Hand-captured evidence legitimately comes back inconclusive and the merge still lands.
  A judge that is not configured degrades to a plain "not checked" verdict.
- `merge-card post --board <board.json> <task-id> <worktree|-> <head|-> <pr-url|->` posts exactly one card per merge.
  The card carries the Checks outcome as the title, done-done's verdict in plain words, the pull request link (the merged commit when there is no PR), and the Checks evidence media (at most 12 screens or recordings), or those of a done-done evidence run at the merged head.
  The card key is the merge's own (`merge-<owner>-<repo>-pull-<n>`, or `merge-<head>` for a local merge), so a repeat post or a second home adds nothing.
  sign-off-axi writes the board under its lock and only appends.

Both subcommands need `done-done`, `sign-off-axi`, `jq` and `gh` on `PATH`, plus `FM_HOME` set.

Install into one home, so the post-merge hook calls `post` once for each recorded merge:

```sh
printf '#!/bin/sh\nexec <addons>/merge-card/merge-card gate "$@"\n' > $FM_HOME/config/merge-gate
printf '#!/bin/sh\nexec <addons>/merge-card/merge-card post --board <board.json> "$@"\n' > $FM_HOME/config/post-merge
chmod +x $FM_HOME/config/merge-gate $FM_HOME/config/post-merge
```

## quota-failover

Workers stopped by a provider usage limit move to the next live route on their own, with nobody relaunching them by hand.

`quota-failover/quota-failover <fm-home>` is one bash script that makes one pass over the home's workers under a lock, so any cadence can run it.
A worker counts as stopped by a limit when all of these hold:

- its status says working, or it has no status yet;
- it has written no status, turn end or progress for `QUOTA_FAILOVER_STALL_SECS` (default 240), and it was not spawned or relaunched inside that window;
- it is not busy, where a harness that is only retrying a provider error counts as not busy;
- its visible screen shows a provider limit error, or `quota-axi` reads its route's provider as exhausted now.

A busy worker that is making progress is never touched.
A stopped worker gets the routes of the `config/crew-dispatch.json` rules that hold its current route, then the default list, in order.
Routes whose provider reads exhausted are passed over, and the first other route that answers a one-prompt live test (`QUOTA_FAILOVER_TEST_SECS`, default 90) wins.
The worker is relaunched there with `bin/fm-control.sh <task> relaunch`, with a note naming the old route, the new route and why.
A route that sits only in rules whose models all contain `opus` moves only to another such model; with none live, the worker is left waiting and the reason is logged.
Leads and remote tasks are detected and logged, never switched.
Every decision is one line in `state/quota-failover.log`.
A worker left with no live route also gets one failed line on the home's parent channel; nothing else is sent there, and `config/` is never edited.

It needs `quota-axi`, `jq`, `flock` and the harness command of each dispatch route on `PATH`.
`QUOTA_FAILOVER_MAX_AGE` (default `10m`) is the oldest quota reading it trusts.

Install into one home as a watcher check, so it runs on the watcher's own cadence:

```sh
printf 'setsid -f <addons>/quota-failover/quota-failover %s >/dev/null 2>&1 </dev/null\n' "$FM_HOME" > $FM_HOME/state/quota-failover-watch.check.sh && chmod 700 $FM_HOME/state/quota-failover-watch.check.sh && $FM_HOME/bin/fm-check-register.sh quota-failover-watch
```

Remove it with `$FM_HOME/bin/fm-check-unregister.sh quota-failover-watch`.
