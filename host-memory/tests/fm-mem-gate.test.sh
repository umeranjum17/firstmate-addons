#!/usr/bin/env bash
# Regression check for config/fm-mem-gate.sh (16 Oct, byokit key fm-mem-gate-deadlock): an emulator job that waits
# for an emulator slot must not hold the host lock while it sleeps, so a Gradle job with room gets through.
# Usage: fm-mem-gate.test.sh [gate-script]   exit 0 = PASS. Uses a private lock dir and stub commands.
G=${1:-$(dirname "$(readlink -f "$0")")/fm-mem-gate.sh}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/run"; printf '#!/bin/sh\nexit 0\n' > "$T/bin/emulator"; cp "$T/bin/emulator" "$T/bin/gradlew"; chmod +x "$T"/bin/*
export XDG_RUNTIME_DIR=$T/run FM_MEM_MIN_GB=0
FM_EMU_MAX=0 setsid "$G" "$T/bin/emulator" 2>/dev/null & w=$!
sleep 2
FM_GRADLE_MAX=99 timeout 25 "$G" "$T/bin/gradlew" 2>/dev/null; rc=$?
kill -- -$w 2>/dev/null; wait $w 2>/dev/null
[ $rc = 0 ] && echo PASS || echo "FAIL rc=$rc (Gradle job stuck behind the waiting emulator job)"
[ $rc = 0 ]
