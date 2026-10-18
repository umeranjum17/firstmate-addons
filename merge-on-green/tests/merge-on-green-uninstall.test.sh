#!/usr/bin/env bash
set -euo pipefail
A=$(cd "$(dirname "$0")/.." && pwd -P); T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/home/bin" "$T/home/state" "$T/data"; : > "$T/home/bin/fm-check-register.sh"; : > "$T/home/bin/fm-check-unregister.sh"; chmod +x "$T/home/bin/"fm-check-*.sh
E=(env HOME="$T/user" XDG_DATA_HOME="$T/data")
"${E[@]}" "$A/install.sh" "$T/home" >/dev/null; "${E[@]}" "$A/uninstall.sh" "$T/home" >/dev/null
[ ! -e "$T/data/fm-merge-on-green/merge-on-green.sh" ] && [ ! -e "$T/home/state/merge-on-green.check.sh" ]; "${E[@]}" "$A/uninstall.sh" "$T/home" >/dev/null; echo PASS
