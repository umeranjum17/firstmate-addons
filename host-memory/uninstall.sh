#!/usr/bin/env bash
# Remove the installed host-memory gate. Usage: uninstall.sh [--dry-run]
set -euo pipefail
DRY=0; [ "${1:-}" = --dry-run ] && { DRY=1; shift; }
[ "$#" -eq 0 ] || { echo 'usage: uninstall.sh [--dry-run]' >&2; exit 2; }
f=${XDG_DATA_HOME:-$HOME/.local/share}/fm-host-memory/fm-mem-gate.sh
slice=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/fm-heavy.slice
reload=0
[ ! -e "$f" ] || { echo "remove: $f"; [ "$DRY" -eq 1 ] || rm -f -- "$f"; }
[ ! -e "$slice" ] || { echo "remove: $slice"; [ "$DRY" -eq 1 ] || { rm -f -- "$slice"; reload=1; }; }
if [ "$DRY" -eq 0 ]; then
  rmdir "${f%/*}" 2>/dev/null || true
  [ "$reload" -eq 0 ] || systemctl --user daemon-reload || { echo 'host-memory: systemctl --user daemon-reload failed' >&2; exit 1; }
else echo 'dry run: nothing written'; fi
