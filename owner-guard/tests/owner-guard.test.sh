#!/usr/bin/env bash
# Fixture proof: a pooled-style lane worktree against a throwaway HOME, home
# and patterns file holding only made-up values. A matching commit is refused
# with file:line, a clean commit passes, a matching push is refused, a
# removal-only commit passes, and the repo's own pre-commit still chains.
# Usage: owner-guard/tests/owner-guard.test.sh
set -euo pipefail
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
GISRC=$(cd "$SRC/../git-identity" && pwd -P)
d=$(mktemp -d)
trap 'chmod -R u+w -- "$d"; rm -rf -- "$d"' EXIT
for v in $(env | sed -n 's/^\(GIT_CONFIG_[A-Z_0-9]*\)=.*/\1/p'); do unset "$v"; done
unset GIT_CONFIG_PARAMETERS GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_DIR GIT_WORK_TREE
export HOME=$d/home XDG_DATA_HOME=$d/data XDG_CONFIG_HOME=$d/xdg TMPDIR=$d GIT_CONFIG_NOSYSTEM=1
FM=$d/fm
mkdir -p "$HOME" "$FM/config" "$XDG_CONFIG_HOME"
fails=0
check() { if [ "$2" = "$3" ]; then echo "ok: $1"; else printf 'FAIL: %s\n  want: %s\n  got:  %s\n' "$1" "$3" "$2"; fails=$((fails + 1)); fi; }
has() { if printf '%s' "$2" | grep -qF -- "$3"; then echo "ok: $1"; else printf 'FAIL: %s\n  want text: %s\n  got: %s\n' "$1" "$3" "$2"; fails=$((fails + 1)); fi; }
ME=you@example.com
printf '%s\n' '# fixture-only patterns' '' 'testguard-fake-surname' 'guardtest[0-9]{3}@example\.test' >"$d/patterns"
export OWNER_GUARD_PATTERNS=$d/patterns FM_HOME=$FM

git init -q --bare -b main "$d/origin.git"
git clone -q "$d/origin.git" "$d/clone"
git -C "$d/clone" -c user.name=You -c user.email=$ME commit -q --allow-empty -m base
git -C "$d/clone" push -q origin main
printf '#!/bin/sh\necho repo-hook >>%q\n' "$d/repo-hook.log" >"$d/clone/.git/hooks/pre-commit"
chmod +x "$d/clone/.git/hooks/pre-commit"
git -C "$d/clone" worktree add -q -b lane "$d/wt" origin/main
WT=$d/wt
"$GISRC/install.sh" --email "$ME" --name You "$FM" >/dev/null
out=$("$SRC/install.sh" "$FM")
has "install chains the hooks dir" "$out" "hooks.d"
# shellcheck source=/dev/null
lane() (cd "$WT" && "$FM/config/launch-env-hook" "$d/env.sh" && . "$d/env.sh" && "$@")

printf 'reach testguard-fake-surname here\n' >"$WT/details.txt"
git -C "$WT" add details.txt
out=$(lane git commit -m 'bad commit' 2>&1) && rc=0 || rc=$?
check "matching commit refused" "$rc" 1
has "refusal prints file:line" "$out" "details.txt:1"
has "refusal hints placeholders" "$out" "you@example.com"
check "refused commit kept nothing" "$(git -C "$WT" rev-list --count HEAD)" 1
printf 'hello\n' >"$WT/clean.txt"
git -C "$WT" add clean.txt
git -C "$WT" rm -q --cached details.txt && rm -f "$WT/details.txt"
out=$(lane git commit -q -m 'clean commit' 2>&1) && rc=0 || rc=$?
check "clean commit passes" "$rc" 0
has "repo pre-commit still chained" "$(cat "$d/repo-hook.log")" "repo-hook"
printf 'me guardtest042@example.test\n' >"$WT/pushed.txt"
git -C "$WT" add pushed.txt
lane git commit -q --no-verify -m 'bad push'
out=$(lane git push origin lane 2>&1) && rc=0 || rc=$?
check "matching push refused" "$rc" 1
has "push refusal prints file:line" "$out" "pushed.txt:1"
check "refused push reached nothing" "$(git -C "$d/origin.git" branch --list lane)" ""
git -C "$WT" reset -q --hard HEAD~1
printf 'reach testguard-fake-surname here\n' >"$WT/gone.txt"
git -C "$WT" add gone.txt
lane git commit -q --no-verify -m 'seeded'
printf 'scrubbed\n' >"$WT/gone.txt"
git -C "$WT" add gone.txt
out=$(lane git commit -q -m 'removal only' 2>&1) && rc=0 || rc=$?
check "removal-only commit passes" "$rc" 0
unset OWNER_GUARD_PATTERNS
cp "$d/patterns" "$FM/config/owner-details-patterns"
printf 'reach testguard-fake-surname here\n' >"$WT/fallback.txt"
git -C "$WT" add fallback.txt
out=$(FM_HOME=$d/empty lane git commit -m 'fallback' 2>&1) && rc=0 || rc=$?
check "lane home without patterns falls back to install home" "$rc" 1
has "fallback refusal prints file:line" "$out" "fallback.txt:1"
git -C "$WT" rm -q --cached fallback.txt && rm -f "$WT/fallback.txt"
export OWNER_GUARD_PATTERNS=$d/nonexistent
out=$(FM_HOME=$d/empty lane git commit -q --allow-empty -m 'no patterns' 2>&1) && rc=0 || rc=$?
check "missing patterns allows" "$rc" 0
has "missing patterns prints one note" "$out" "nothing to protect"

if [ "$fails" -eq 0 ]; then echo "PASS"; else echo "FAILED: $fails"; exit 1; fi
