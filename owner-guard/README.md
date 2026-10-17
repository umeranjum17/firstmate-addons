# owner-guard

The owner-details guard — the rule that keeps a lane from committing or
pushing the owner's private details to a public repo, shaped like
`delete-guard` (a refusal is final: no bypass flag, no env skip).

## Layout

- `owner-guard` — the guard. `pre-commit` scans the staged added lines;
  `pre-push` scans the added lines of every pushed commit the destination
  ref doesn't already have (for a new branch, every commit no
  remote-tracking ref has). Each added line is
  matched case-insensitively against every extended regex in the patterns
  file: `$FM_HOME/config/owner-details-patterns` when that home holds one,
  else the installing home's file (full-line `#` comments and blank lines
  ignored). A hit refuses with
  `file:line` plus a placeholder hint, never the pattern list. A missing or
  empty patterns file allows with one note line.
- `install.sh` — installs the guard, keeps the patterns file private (mode
  600, never created and never overwritten; the recorded patterns home is
  kept when the new home has no file), and chains both hooks
  through the git-identity `hooks.d/` dir so every lane commit runs them.
- `tests/owner-guard.test.sh` — fixture-repo proof (throwaway HOME and repo,
  made-up patterns only): matching commit refused, clean commit passes,
  matching push refused, removal-only commit passes, the repo's own hook
  still chains. The patterns file is never copied into the repo or a log.

## Daily scan

`scan-check` shallow-clones (depth 1) the default branch of every fleet
public repo at most once a day and matches every line against the same
patterns file the hook uses. The repo list is
`config/owner-guard-repos` under the Main home (one `owner/repo` or clone
URL per line, full-line `#` comments allowed); when it is missing, the
account's public repos are listed through the forge CLI instead. A run with
hits prints one wake line naming each repo with its hit count and the
private `data/owner-details-scan/` report holding the full `file:line`
hits; a clean run, a run within 24 h of the last one, or a missing patterns
file prints nothing. Install with `install-scan.sh [--dry-run] [<home>]`
(the home defaults to the Main home); `tests/scan-e2e.sh` is the fixture
proof (one hit repo, one clean repo, made-up patterns only).

## Placeholders

Replace a refused detail with `you@example.com`, `~/firstmate`, `/home/you`.
