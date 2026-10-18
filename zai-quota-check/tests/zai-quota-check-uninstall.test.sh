#!/usr/bin/env bash
set -euo pipefail
A=$(cd "$(dirname "$0")/.." && pwd -P); T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/home/state" "$T/home/bin"; printf '#!/bin/sh\nexit 0\n' > "$T/home/bin/fm-check-register.sh"; cp "$T/home/bin/fm-check-register.sh" "$T/home/bin/fm-check-unregister.sh"; chmod +x "$T/home/bin/"fm-check-*.sh; printf other > "$T/home/state/other"
E=(env HOME="$T/user" FM_HOME="$T/home"); "${E[@]}" "$A/install.sh" >/dev/null; "${E[@]}" "$A/uninstall.sh" >/dev/null; [ ! -e "$T/home/state/zai-quota.check.sh" ] && [ "$(cat "$T/home/state/other")" = other ]; "${E[@]}" "$A/uninstall.sh" >/dev/null; echo PASS
