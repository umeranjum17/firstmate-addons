#!/usr/bin/env bash
# Remove the Z.AI quota check from one firstmate home. Usage: uninstall.sh [--dry-run]
set -euo pipefail
DRY=0; [ "${1:-}" = --dry-run ] && { DRY=1; shift; }; [ "$#" -eq 0 ] || { echo 'usage: uninstall.sh [--dry-run]' >&2; exit 2; }
FM_HOME=${FM_HOME:?set FM_HOME to the firstmate home}; f=$FM_HOME/state/zai-quota.check.sh
[ ! -e "$f" ] || { echo "remove: $f"; [ "$DRY" -eq 1 ] || rm -f -- "$f"; }
if [ -x "$FM_HOME/bin/fm-check-unregister.sh" ]; then [ "$DRY" -eq 1 ] || env -u FM_STATE_OVERRIDE FM_HOME="$FM_HOME" "$FM_HOME/bin/fm-check-unregister.sh" zai-quota; fi
[ "$DRY" -eq 0 ] || echo 'dry run: nothing written'
