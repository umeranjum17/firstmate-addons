#!/usr/bin/env bash
# Remove merge-on-green's registered check and installed command. Usage: uninstall.sh [--dry-run] <fm-home>
set -euo pipefail
DRY=0; [ "${1:-}" = --dry-run ] && { DRY=1; shift; }
[ "$#" -eq 1 ] && [ -d "$1" ] || { echo 'usage: uninstall.sh [--dry-run] <fm-home>' >&2; exit 2; }
FMH=$(cd "$1" && pwd -P); DEST=${XDG_DATA_HOME:-$HOME/.local/share}/fm-merge-on-green; f=$FMH/state/merge-on-green.check.sh
[ ! -e "$f" ] || { echo "remove: $f"; [ "$DRY" -eq 1 ] || rm -f -- "$f"; }
if [ -x "$FMH/bin/fm-check-unregister.sh" ]; then
  if [ "$DRY" -eq 1 ]; then echo "would run: $FMH/bin/fm-check-unregister.sh merge-on-green"; else env -u FM_STATE_OVERRIDE FM_HOME="$FMH" "$FMH/bin/fm-check-unregister.sh" merge-on-green; fi
fi
[ ! -e "$DEST/merge-on-green.sh" ] || { echo "remove: $DEST/merge-on-green.sh"; [ "$DRY" -eq 1 ] || rm -f -- "$DEST/merge-on-green.sh"; }
[ "$DRY" -eq 1 ] || rmdir "$DEST" 2>/dev/null || true
[ "$DRY" -eq 0 ] || echo 'dry run: nothing written'
