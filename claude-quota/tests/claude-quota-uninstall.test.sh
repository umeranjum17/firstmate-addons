#!/usr/bin/env bash
set -euo pipefail
A=$(cd "$(dirname "$0")/.." && pwd -P); T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/home/bin" "$T/home/state"; printf '#!/bin/sh\nexit 0\n' > "$T/home/bin/fm-check-register.sh"; cp "$T/home/bin/fm-check-register.sh" "$T/home/bin/fm-check-unregister.sh"; chmod +x "$T/home/bin/"fm-check-*.sh; printf unrelated > "$T/home/state/other"
E=(env HOME="$T/user" XDG_DATA_HOME="$T/data"); "${E[@]}" "$A/install.sh" "$T/home" >/dev/null; "${E[@]}" "$A/uninstall.sh" "$T/home" >/dev/null
[ ! -e "$T/home/state/claude-quota.check.sh" ] && [ ! -e "$T/data/fm-claude-quota/claude-quota.check.sh" ] && [ "$(cat "$T/home/state/other")" = unrelated ]; "${E[@]}" "$A/uninstall.sh" "$T/home" >/dev/null; echo 'PASS claude-quota uninstall'
