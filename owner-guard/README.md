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
  kept when the new home has no file), chains both hooks
  through the git-identity `hooks.d/` dir so every lane commit runs them,
  and points the user's global `core.hooksPath` at `global-hook.sh`
  wrappers so plain-shell commits and pushes are checked too. Each wrapper
  runs the guard (pre-commit and pre-push only), then the previous global
  hooks dir's hook and the repository's own hook, so repos with their own
  hooks keep working. Install is idempotent, records a replaced global
  hooksPath instead of dropping it, and `--uninstall` restores it; a
  repo-local `core.hooksPath` is never touched.
- `tests/owner-guard.test.sh` — fixture-repo proof (throwaway HOME and repo,
  made-up patterns only): matching commit refused, clean commit passes,
  matching push refused, removal-only commit passes, the repo's own hook
  still chains. The patterns file is never copied into the repo or a log.
- `tests/owner-guard-global.test.sh` — fixture proof for the machine-wide
  guard (throwaway HOME and global gitconfig, made-up patterns only):
  plain-shell and lane leaks refused, clean commits and pushes pass, the
  repo's own hooks and a previous global hooks dir still chain, double
  install is a no-op, uninstall restores the previous global hooksPath.

## Known limits

A refusal only fires when a client-side hook runs: `git commit --no-verify`
skips the pre-commit check, and a repo-local `core.hooksPath` (for example
a hook manager) replaces the global wrappers for that repo, so neither is
caught.

## Placeholders

Replace a refused detail with `you@example.com`, `~/firstmate`, `/home/you`.
