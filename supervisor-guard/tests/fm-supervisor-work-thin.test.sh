#!/usr/bin/env bash
# The supervisor-work guard wrapper, driven against a stub Firstmate checkout in a
# throwaway directory. The stub guard records its argv and stdin, prints a marker
# on stderr and exits with the code it was built with, so the test shows that the
# wrapper forwards arguments, stdin, stderr and exit code unchanged, and that it
# fails closed with a clear message when no checkout guard is present.
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WRAPPER="$HERE/bin/fm-supervisor-work-thin.sh"
TMP=$(mktemp -d)
on_exit() {
  rm -rf -- "$TMP"
}
trap on_exit EXIT
FAILS=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

# make_checkout DIR EXIT_CODE: a stub checkout whose guard logs argv and stdin.
make_checkout() {
  mkdir -p "$1/bin"
  cat > "$1/bin/fm-supervisor-work-pretool-check.sh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$1/argv"
cat > "$1/stdin"
echo "stub-guard-marker" >&2
exit $2
SH
  chmod +x "$1/bin/fm-supervisor-work-pretool-check.sh"
}

# 1. Arguments, stdin, stderr and a deny exit code pass through unchanged.
CK="$TMP/ck1"
make_checkout "$CK" 2
out=$(printf 'payload-json' | env -u FM_CODE_ROOT FM_HOME="$CK" "$WRAPPER" --command 'ls' --secondmate 2>"$TMP/err1")
rc=$?
[ "$rc" = 2 ] && pass "deny exit code forwarded" || fail "deny exit code forwarded (rc=$rc)"
[ "$(cat "$CK/argv")" = "$(printf -- '--command\nls\n--secondmate')" ] \
  && pass "arguments forwarded" || fail "arguments forwarded"
[ "$(cat "$CK/stdin")" = "payload-json" ] && pass "stdin forwarded" || fail "stdin forwarded"
grep -q stub-guard-marker "$TMP/err1" && pass "stderr forwarded" || fail "stderr forwarded"
[ -z "$out" ] && pass "stdout empty as the guard left it" || fail "stdout empty as the guard left it"

# 2. An allow (exit 0) passes through as exit 0.
CK="$TMP/ck2"
make_checkout "$CK" 0
printf '{}' | env -u FM_CODE_ROOT FM_HOME="$CK" "$WRAPPER" --claude 2>/dev/null
rc=$?
[ "$rc" = 0 ] && pass "allow exit code forwarded" || fail "allow exit code forwarded (rc=$rc)"

# 3. FM_CODE_ROOT wins over FM_HOME.
HOME_CK="$TMP/home-ck"; ROOT_CK="$TMP/root-ck"
make_checkout "$HOME_CK" 7
make_checkout "$ROOT_CK" 0
printf '{}' | FM_HOME="$HOME_CK" FM_CODE_ROOT="$ROOT_CK" "$WRAPPER" --claude 2>/dev/null
rc=$?
[ "$rc" = 0 ] && [ -f "$ROOT_CK/argv" ] && [ ! -f "$HOME_CK/argv" ] \
  && pass "FM_CODE_ROOT overrides FM_HOME" || fail "FM_CODE_ROOT overrides FM_HOME"

# 4. FM_HOME alone names the checkout.
CK="$TMP/ck4"
make_checkout "$CK" 7
printf '{}' | env -u FM_CODE_ROOT FM_HOME="$CK" "$WRAPPER" --claude 2>/dev/null
rc=$?
[ "$rc" = 7 ] && pass "FM_HOME default checkout" || fail "FM_HOME default checkout (rc=$rc)"

# 5. No checkout named: exit 2 with a message that says what to set.
env -u FM_HOME -u FM_CODE_ROOT "$WRAPPER" --claude >/dev/null 2>"$TMP/err5"
rc=$?
[ "$rc" = 2 ] && grep -q 'set FM_CODE_ROOT' "$TMP/err5" \
  && pass "no checkout fails closed with a message" || fail "no checkout fails closed with a message (rc=$rc)"

# 6. A checkout without an executable guard is the same failure.
CK="$TMP/ck6"
mkdir -p "$CK/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$CK/bin/fm-supervisor-work-pretool-check.sh"
env -u FM_CODE_ROOT FM_HOME="$CK" "$WRAPPER" --claude >/dev/null 2>&1
rc=$?
[ "$rc" = 2 ] && pass "non-executable guard fails closed" || fail "non-executable guard fails closed (rc=$rc)"

if [ "$FAILS" -gt 0 ]; then
  echo "$FAILS check(s) failed"
  exit 1
fi
echo "all supervisor-work wrapper checks passed"
