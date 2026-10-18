#!/usr/bin/env bash
# Remove fleet-stall's home shim, check registration, and installed script. Usage: uninstall.sh [--dry-run]
set -euo pipefail
DRY=0; [ "${1:-}" = --dry-run ] && { DRY=1; shift; }; [ "$#" -eq 0 ] || { echo 'usage: uninstall.sh [--dry-run]' >&2; exit 2; }
FM_HOME=${FM_HOME:?set FM_HOME to the firstmate home}; DEST=${XDG_DATA_HOME:-$HOME/.local/share}/fm-fleet-stall; f=$FM_HOME/state/fleet-stall.check.sh
[ ! -e "$f" ] || { echo "remove: $f"; [ "$DRY" -eq 1 ] || rm -f -- "$f"; }
if [ -x "$FM_HOME/bin/fm-check-unregister.sh" ]; then [ "$DRY" -eq 1 ] || env -u FM_STATE_OVERRIDE FM_HOME="$FM_HOME" "$FM_HOME/bin/fm-check-unregister.sh" fleet-stall; fi
[ ! -e "$DEST/fleet-stall-check" ] || { echo "remove: $DEST/fleet-stall-check"; [ "$DRY" -eq 1 ] || rm -f -- "$DEST/fleet-stall-check"; }
[ "$DRY" -eq 1 ] || rmdir "$DEST" 2>/dev/null || true
[ "$DRY" -eq 0 ] || echo 'dry run: nothing written'
