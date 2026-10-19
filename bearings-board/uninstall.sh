#!/usr/bin/env bash
# Remove what install.sh added to one Firstmate home, and nothing else: the launcher,
# the install record, and the home hook (restored from its backup when install
# changed it). A hook edited since install is left alone. Usage: uninstall.sh [--dry-run] <fm-home>
set -euo pipefail
DRY=0
[ "${1:-}" = --dry-run ] && { DRY=1; shift; }
[ "$#" -eq 1 ] && [ -d "$1" ] || { echo "usage: uninstall.sh [--dry-run] <fm-home>" >&2; exit 2; }
FMH=$(cd "$1" && pwd -P)
RECORD="$FMH/state/bearings-board-thin.install"
[ -f "$RECORD" ] || { echo "nothing installed in $FMH"; exit 0; }
field() { sed -n "s/^$1=//p" "$RECORD"; }
LAUNCHER=$(field launcher)
HOOK=$(field hook)
BACKUP=$(field backup)

if [ "$HOOK" != - ] && [ -f "$HOOK" ] && [ "$(cat "$HOOK")" = "$LAUNCHER" ]; then
  if [ "$BACKUP" != - ]; then
    [ "$DRY" -eq 1 ] || mv "$BACKUP" "$HOOK"
    echo "restored $HOOK from $BACKUP"
  else
    [ "$DRY" -eq 1 ] || rm -f -- "$HOOK"
    echo "removed $HOOK"
  fi
elif [ "$HOOK" != - ]; then
  echo "left $HOOK alone: it no longer names $LAUNCHER"
fi

[ "$DRY" -eq 1 ] && { echo "dry run: nothing removed; would remove $LAUNCHER and $RECORD"; exit 0; }
rm -f -- "$LAUNCHER" "$RECORD"
echo "uninstalled from $FMH"
