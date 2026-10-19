#!/usr/bin/env bash
# Wrapper test: a stub Firstmate checkout stands in for the real board. Covers
# build, payload refusal, argument forwarding, the recursion guard, and install and
# uninstall round trips including their failure paths and hook cleanup.
set -eu

ADDON=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WRAPPER="$ADDON/bin/fm-bearings-board.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bearings-board-test.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT
command -v jq >/dev/null 2>&1 || { echo "skip: jq not found"; exit 0; }

fail() { printf 'not ok: %s\n' "$*" >&2; exit 1; }
FMH="$TMP/fm"
mkdir -p "$FMH/bin" "$FMH/state" "$FMH/config"
cat > "$FMH/bin/fm-bearings-board.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FM_HOME/state/build-args"
case "$1" in
  build) printf 'built\n' > "$FM_HOME/state/board.html" ;;
  path) printf '%s/state/board.html\n' "$FM_HOME" ;;
esac
STUB
chmod +x "$FMH/bin/fm-bearings-board.sh"
printf 'old\n' > "$FMH/config/bearings-board-command"
export FM_CODE_ROOT="$FMH" FM_HOME="$FMH"

printf 'not json\n' > "$TMP/bad.json"; echo '{"projects":[]}' > "$TMP/good.json"
"$WRAPPER" build "$TMP/bad.json" 2>/dev/null && fail "bad JSON was accepted"
[ ! -e "$FMH/state/board.html" ] || fail "bad JSON still ran the checkout build"
"$WRAPPER" build "$TMP/good.json" || fail "good payload refused"
grep -q built "$FMH/state/board.html" || fail "checkout build did not run"
[ -z "$(sed -n 3p "$FMH/state/build-args")" ] || fail "unexpected extra argument forwarded"
"$WRAPPER" build "$TMP/good.json" --flag || fail "payload with a flag refused"
[ "$(sed -n 3p "$FMH/state/build-args")" = --flag ] || fail "extra argument dropped"
[ "$("$WRAPPER" path)" = "$FMH/state/board.html" ] || fail "path is not the checkout's board"
FM_CODE_ROOT="$ADDON" "$WRAPPER" build "$TMP/good.json" >/dev/null 2>&1 && fail "wrapper re-entered itself"

LAUNCHER="$FMH/state/bearings-board-thin"
rm -rf -- "$FMH/state"; : > "$FMH/state"
"$ADDON/install.sh" "$FMH" >/dev/null 2>&1 && fail "install survived an unusable state dir"
[ "$(cat "$FMH/config/bearings-board-command")" = old ] || fail "failed install changed the hook"
rm -f -- "$FMH/state"; mkdir -p "$FMH/state"

"$ADDON/install.sh" "$FMH" >/dev/null || fail "install failed"
grep -q "$LAUNCHER" "$FMH/config/bearings-board-command" || fail "hook not pointed at the launcher"
"$LAUNCHER" path | grep -q board.html || fail "launcher does not run the checkout board"
"$ADDON/uninstall.sh" "$FMH" >/dev/null || fail "uninstall failed"
[ ! -e "$LAUNCHER" ] || fail "launcher left behind"
[ "$(cat "$FMH/config/bearings-board-command")" = old ] || fail "hook not restored"

"$ADDON/install.sh" "$FMH" >/dev/null || fail "second install failed"
printf 'exec %s "$@"\n' "$LAUNCHER" > "$FMH/config/bearings-board-command"
"$ADDON/uninstall.sh" "$FMH" >/dev/null || fail "uninstall of an edited hook failed"
grep -q "$LAUNCHER" "$FMH/config/bearings-board-command" || fail "edited hook was overwritten"
[ -x "$LAUNCHER" ] || fail "launcher removed from under a surviving hook"

# Hand-wire the hook as install's message suggests, rerun install, then uninstall:
# the hook must not survive naming a launcher that uninstall removed.
rm -f -- "$FMH/config/bearings-board-command" "$LAUNCHER" "$FMH/config/"*.bak-bearings-board-thin-*
"$ADDON/install.sh" "$FMH" >/dev/null || fail "install without a hook failed"
[ ! -e "$FMH/config/bearings-board-command" ] || fail "install created a hook"
printf '%s\n' "$LAUNCHER" > "$FMH/config/bearings-board-command"
"$ADDON/install.sh" "$FMH" >/dev/null || fail "install rerun over a hand-wired hook failed"
"$ADDON/uninstall.sh" "$FMH" >/dev/null || fail "uninstall after the rerun failed"
[ ! -e "$LAUNCHER" ] || fail "launcher left behind after the rerun"
[ "$(cat "$FMH/config/bearings-board-command" 2>/dev/null)" != "$LAUNCHER" ] || fail "hook still names the removed launcher"

# A backup cleaned up before uninstall must not abort it or leave a dangling hook.
printf 'old\n' > "$FMH/config/bearings-board-command"
"$ADDON/install.sh" "$FMH" >/dev/null || fail "install before backup removal failed"
rm -f -- "$FMH/config/"*.bak-bearings-board-thin-*
"$ADDON/uninstall.sh" "$FMH" >/dev/null || fail "uninstall without its backup failed"
[ ! -e "$LAUNCHER" ] || fail "launcher left behind without a backup"
[ "$(cat "$FMH/config/bearings-board-command" 2>/dev/null)" != "$LAUNCHER" ] || fail "hook still names the removed launcher without a backup"
echo "ok: wrapper build, forwarding, recursion guard, and install round trips"
