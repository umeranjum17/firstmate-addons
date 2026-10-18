#!/usr/bin/env bash
set -euo pipefail
A=$(cd "$(dirname "$0")/.." && pwd -P); T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/home" "$T/bin"; cat >"$T/bin/systemctl" <<'SYSTEMCTL'
#!/bin/sh
echo "$*" >>"$LOG"
SYSTEMCTL
chmod +x "$T/bin/systemctl"
E=(env HOME="$T/home" XDG_DATA_HOME="$T/data" XDG_CONFIG_HOME="$T/config" PATH="$T/bin:$PATH" LOG="$T/systemctl.log"); printf unrelated > "$T/keep"
"${E[@]}" "$A/install.sh" >/dev/null
[ "$(cat "$T/config/systemd/user/fm-heavy.slice")" = $'[Slice]\nCPUWeight=20\nIOWeight=20' ] && grep -qx -- '--user daemon-reload' "$T/systemctl.log"
"${E[@]}" "$A/uninstall.sh" >/dev/null; [ ! -e "$T/data/fm-host-memory/fm-mem-gate.sh" ] && [ ! -e "$T/config/systemd/user/fm-heavy.slice" ] && [ "$(cat "$T/keep")" = unrelated ]
before=$(sha256sum "$T/keep"); "${E[@]}" "$A/uninstall.sh" >/dev/null; [ "$before" = "$(sha256sum "$T/keep")" ]; echo 'PASS host-memory install/uninstall'
