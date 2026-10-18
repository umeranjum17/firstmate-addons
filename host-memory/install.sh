#!/usr/bin/env bash
# Install or update the memory gate for this user. Idempotent. Usage: install.sh [--dry-run]
# Main's config/fm-mem-gate.sh becomes a shim that execs the installed copy; this script never writes it.
set -euo pipefail
DRY=0
[ "${1:-}" = --dry-run ] && { DRY=1; shift; }
[ "$#" -eq 0 ] || { echo "usage: install.sh [--dry-run]" >&2; exit 2; }
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/bin/fm-mem-gate.sh
DEST=${XDG_DATA_HOME:-$HOME/.local/share}/fm-host-memory/fm-mem-gate.sh
SLICE=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/fm-heavy.slice
if cmp -s "$SRC" "$DEST"; then echo "unchanged: $DEST"
elif [ "$DRY" -eq 1 ]; then echo "would copy: $SRC -> $DEST"
else mkdir -p "${DEST%/*}"; install -m 755 "$SRC" "$DEST"; echo "copied: $SRC -> $DEST"
fi
if [ -f "$SLICE" ] && grep -qx 'CPUWeight=20' "$SLICE" && grep -qx 'IOWeight=20' "$SLICE"; then
  [ "$DRY" -eq 1 ] && echo "unchanged: $SLICE"
else
  if [ "$DRY" -eq 1 ]; then echo "would write: $SLICE"
  else
    mkdir -p "${SLICE%/*}"
    printf '[Slice]\nCPUWeight=20\nIOWeight=20\n' > "$SLICE"
    echo "wrote: $SLICE"
  fi
fi
if [ "$DRY" -eq 0 ]; then systemctl --user daemon-reload || { echo 'host-memory: systemctl --user daemon-reload failed' >&2; exit 1; }; fi
