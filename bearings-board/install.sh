#!/usr/bin/env bash
# Wire the Bearings board wrapper into one Firstmate home: a launcher that runs the
# checkout's board with this add-on's extras. A home hook at config/bearings-board-command
# is pointed at the launcher only when it exists; otherwise install prints the command.
# A hook that already names the launcher is left as it is and recorded without a backup,
# so uninstall never restores a hook that names a launcher it removes.
# The launcher and the install record are written before the hook is repointed, so a
# failed install leaves the home's board command working and removable.
# Idempotent: rerun it to update. Usage: install.sh [--dry-run] <fm-home>
set -euo pipefail
DRY=0
[ "${1:-}" = --dry-run ] && { DRY=1; shift; }
[ "$#" -eq 1 ] && [ -x "$1/bin/fm-bearings-board.sh" ] || { echo "usage: install.sh [--dry-run] <fm-home>" >&2; exit 2; }
FMH=$(cd "$1" && pwd -P)
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
LAUNCHER="$FMH/state/bearings-board-thin"
HOOK="$FMH/config/bearings-board-command"
RECORD="$FMH/state/bearings-board-thin.install"
STAMP=$(date +%s)

[ "$DRY" -eq 1 ] || { [ ! -f "$RECORD" ] || "$SRC/uninstall.sh" "$FMH"; }

hook_state=- hook_backup=-
if [ -e "$HOOK" ]; then
  hook_state=$HOOK
  grep -qF -- "$LAUNCHER" "$HOOK" || hook_backup="$HOOK.bak-bearings-board-thin-$STAMP"
fi

if [ "$DRY" -eq 1 ]; then
  echo "dry run: nothing written; would write $LAUNCHER and $RECORD"
  if [ "$hook_state" = - ]; then
    echo "no home hook at $HOOK: set this home's board command to $LAUNCHER"
  elif [ "$hook_backup" = - ]; then
    echo "would leave $HOOK alone: it already names $LAUNCHER"
  else
    echo "would back up $HOOK to $hook_backup, then point it at $LAUNCHER"
  fi
  exit 0
fi

mkdir -p "$FMH/state"
printf '#!/usr/bin/env bash\nexec env FM_CODE_ROOT=%q FM_HOME=%q %q "$@"\n' "$FMH" "$FMH" "$SRC/bin/fm-bearings-board.sh" > "$LAUNCHER.tmp-$STAMP"
chmod 700 "$LAUNCHER.tmp-$STAMP" && mv "$LAUNCHER.tmp-$STAMP" "$LAUNCHER"
printf 'launcher=%s\nhook=%s\nbackup=%s\n' "$LAUNCHER" "$hook_state" "$hook_backup" > "$RECORD"
echo "installed: $LAUNCHER"

if [ "$hook_state" = - ]; then
  echo "no home hook at $HOOK: set this home's board command to $LAUNCHER"
  exit 0
fi
if [ "$hook_backup" = - ]; then
  echo "left $HOOK alone: it already names $LAUNCHER"
  exit 0
fi
cp -p "$HOOK" "$hook_backup"
printf '%s\n' "$LAUNCHER" > "$HOOK.tmp-$STAMP" && mv "$HOOK.tmp-$STAMP" "$HOOK"
echo "pointed $HOOK at $LAUNCHER (backup $hook_backup)"
