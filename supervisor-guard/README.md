# supervisor-guard

A thin wrapper for the supervisor-work guard: the pre-tool check that stops a
supervisor session from doing a worker's job. The guard itself is not in this
add-on. The Firstmate checkout owns it, and this entry point runs that checkout's
guard with the same arguments, stdin and exit code.

## Layout

- `bin/fm-supervisor-work-thin.sh` — the wrapper. It resolves the checkout from
  `FM_CODE_ROOT`, defaulting to `FM_HOME` (the checkout a home runs from), then
  `exec`s `<checkout>/bin/fm-supervisor-work-pretool-check.sh` unchanged. With no
  checkout or no executable guard in it, it exits 2 with a message that names
  `FM_CODE_ROOT`.
- `tests/fm-supervisor-work-thin.test.sh` — the hermetic wrapper test. It drives
  the wrapper against a stub checkout in a throwaway directory and checks that
  arguments, stdin, stderr and exit codes pass through, that `FM_CODE_ROOT` wins
  over `FM_HOME`, and that a missing guard fails closed.

## Status

- Dormant. Nothing wires this wrapper into a hook yet. The fork still registers
  and runs its own guard, and the hook swap lands in a later fork PR.
- 0 copied upstream lines: no non-blank, non-comment, 20-character-or-longer line
  in `supervisor-guard/` matches a whole line of any file in kunchenguid/firstmate
  main. Evidence is in `data/thin-supervisor-guard/overlap-final.txt` in the
  supervising Firstmate home.

## Fork-only rules

The rules the fork's guard enforces (no driving a crew-owned no-mistakes run
from a supervisor, no sleep over the turn budget, no pane typing outside a
secondmate lead) stay in the checkout's guard, where they run today. This add-on
adds no rule of its own, so there is no second policy to drift. Moving any of
them here is a later slice.

## Checks

- `bash supervisor-guard/tests/fm-supervisor-work-thin.test.sh` — the wrapper test.
- `shellcheck -x -e SC2015,SC1091 supervisor-guard/bin/*.sh supervisor-guard/tests/*.sh`
  and `bash -n` on each script, the same as the add-ons CI gate.
- The overlap count above, re-run on the PR head against a fresh upstream clone.

The wrapper test needs no jq, node or network, and it never touches a real home.
