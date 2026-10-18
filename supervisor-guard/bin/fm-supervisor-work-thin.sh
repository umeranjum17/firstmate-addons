#!/usr/bin/env bash
# fm-supervisor-work-thin.sh - add-on entry point for the supervisor-work guard.
# The guard is not copied here: the Firstmate checkout owns
# bin/fm-supervisor-work-pretool-check.sh, and this wrapper runs that script with
# the same arguments, stdin and exit code, so checkout updates apply with no merge
# and no copy to drift. Dormant: nothing wires this into a hook yet.
# Usage: FM_HOME=<home> [FM_CODE_ROOT=<checkout>] fm-supervisor-work-thin.sh --claude
# FM_CODE_ROOT defaults to FM_HOME, the checkout a home runs from.
set -u

CODE_ROOT=${FM_CODE_ROOT:-${FM_HOME:-}}
GUARD="$CODE_ROOT/bin/fm-supervisor-work-pretool-check.sh"
if [ -z "$CODE_ROOT" ] || [ ! -x "$GUARD" ]; then
  echo "fm-supervisor-work: no Firstmate checkout with bin/fm-supervisor-work-pretool-check.sh; set FM_CODE_ROOT" >&2
  exit 2
fi
exec "$GUARD" "$@"
