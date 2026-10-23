#!/usr/bin/env bash
# run-live-proof.sh: the pipeline's review, test and fix calls recover from a Claude account limit on the one allowed
# route. Each call goes through this checkout's wrapper with no-mistakes' argv shape, on the default chain (Claude Haiku
# through claude-bridge) and a throwaway config/account-pool: the real claude-accounts-pick and accounts, with rests in
# a throwaway pool state folder. The first account a call lands on is limited by a pi shim (claude-bridge's own limit
# text); the next account's answer is real Haiku through the real pi and bridge. No paid route exists
# in the chain. Captures name account ids only, never a folder or a credential.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
evidence=${DONE_DONE_EVIDENCE_ROOT:?}
real_pi=${PI_QUOTA_FAILOVER_REAL_PI:-$(command -v pi)}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$evidence" "$work/home/state" "$work/pool" "$work/cwd"
pick="$repo/claude-accounts/bin/claude-accounts-pick"
printf 'command=%s\nstate=%s\n' "$pick" "$work/pool" >"$work/account-pool"
cat >"$work/pi" <<EOF
#!/usr/bin/env bash
# The controlled limit: the first account folder a role's call runs on answers claude-bridge's own limit text; every
# other call is real pi.
[ "\${1:-}" = list ] || [ -s "$work/limited" ] || printf '%s' "\${CLAUDE_CONFIG_DIR:-}" >"$work/limited"
if [ "\${CLAUDE_CONFIG_DIR:-}" = "\$(cat "$work/limited" 2>/dev/null)" ] && [ "\${1:-}" != list ]; then
  cat >/dev/null
  printf '%s\n' '{"type":"message_end","stopReason":"error","errorMessage":"Claude rate limit (five_hour) resets in 3h: You are out of usage"}'
  exit 0
fi
exec "$real_pi" "\$@"
EOF
chmod +x "$work/pi"
export FM_HOME=$work/home PI_QUOTA_FAILOVER_REAL_PI=$work/pi PI_QUOTA_FAILOVER_ACCOUNT_POOL=$work/account-pool \
  PI_QUOTA_FAILOVER_LOG=$evidence/wrapper.log PI_QUOTA_FAILOVER_PROBE=0 PI_QUOTA_FAILOVER_GATE=
: >"$evidence/wrapper.log"
fails=0 n=0
for role in review test fix; do
  rm -rf "$work/pool/claude-accounts-rested" # each role starts with every account back, so each shows the move
  : >"$work/limited"
  case $role in
    review) prompt='You are the review step of a code pipeline. Review this one-line change: "- x = 1\n+ x = 2". Reply with exactly one line that starts with REVIEW-OK.' ;;
    test) prompt='You are the test step of a code pipeline. The tests printed "3 passed". Reply with exactly one line that starts with TEST-OK.' ;;
    fix) prompt='You are the fix step of a code pipeline. The review asked to rename x to count. Reply with exactly one line that starts with FIX-OK.' ;;
  esac
  marker=$(tr '[:lower:]' '[:upper:]' <<<"$role")-OK
  set +e
  out=$(cd "$work/cwd" && printf '%s' "$prompt" | "$repo/pipeline-quota-failover/pi-quota-failover" \
    --model claude-bridge/claude-haiku-5-5 --mode json --no-session 2>>"$evidence/$role.stderr.txt")
  rc=$?
  set -e
  answer=$(grep -o "${marker}[^\"\\\\]*" <<<"$out" | head -n 1)
  move=$(grep -o 'quota-error on account [^ ]* .*same route on account [^ ]*' "$evidence/wrapper.log" | tail -n 1 | sed 's/ in [0-9]*ms (.*);/;/')
  printf '%s: exit %s; %s; answer: %s\n' "$role" "$rc" "${move:-no account move}" "${answer:-none}" | tee -a "$evidence/roles.txt"
  n=$((n + 1))
  [ "$rc" = 0 ] && [ -n "$answer" ] && [ "$(grep -c "quota-error on account .*same route on account" "$evidence/wrapper.log")" = "$n" ] ||
    fails=$((fails + 1))
done
sed -i "s|$HOME|~|g" "$evidence"/*.txt "$evidence/wrapper.log"
[ "$fails" = 0 ] || { echo "FAIL: $fails role(s) did not recover" | tee -a "$evidence/roles.txt"; exit 1; }
echo "PASS: review, test and fix each moved off a limited account and answered on Claude Haiku" | tee -a "$evidence/roles.txt"
