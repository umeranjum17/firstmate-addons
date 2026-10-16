#!/usr/bin/env bash
# End to end: install into a throwaway HOME's ~/.claude, then drive the real claude binary with the model arguments labs
# and tools pass. The throwaway HOME has NO credential, so no API call is ever made (a banned model cannot run here);
# Claude Code still logs the model it dispatches to ("dispatching to firstParty model=<id>" in ~/.claude/debug), which is
# what each case asserts. Also: the installer never prints other settings, keeps them, backs up, is idempotent, restores.
# shellcheck disable=SC2016 # jq programs are literal
set -uo pipefail
ADDON=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
command -v claude >/dev/null || { echo "FAIL: claude not on PATH"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf -- "$T"' EXIT
fail=0
ok() { echo "ok: $*"; }; no() { echo "FAIL: $*"; fail=1; }
mkdir -p "$T/home/.claude" "$T/w"
echo '{"theme":"dark","env":{"KEEP_ME":"1","FAKE_SECRET":"sk-do-not-print-0000"},"hooks":{"PreToolUse":[]}}' > "$T/home/.claude/settings.json"
printf '{"hasCompletedOnboarding":true}\n' > "$T/home/.claude.json"
inst() { env -u CLAUDE_CONFIG_DIR HOME="$T/home" "$ADDON/install.sh" "$@"; }

inst --dry-run > "$T/dry.out"
jq -e '.availableModels == null' "$T/home/.claude/settings.json" >/dev/null && ok "dry run writes nothing" || no "dry run wrote"
inst > "$T/install.out" && inst > "$T/reinstall.out"
cat "$T/dry.out" "$T/install.out" "$T/reinstall.out" | grep -q 'sk-do-not-print\|KEEP_ME\|theme' && no "installer printed other settings" || ok "installer prints only its own keys"
grep -q '^unchanged: ' "$T/reinstall.out" && ok "reinstall changes nothing" || no "reinstall not idempotent"
ls "$T/home/.claude/"settings.json.bak-claude-model-guard-* >/dev/null 2>&1 && ok "backup made" || no "no backup"
jq -e '.theme == "dark" and .env.KEEP_ME == "1" and .env.FAKE_SECRET == "sk-do-not-print-0000" and .hooks.PreToolUse == []
  and .env.ANTHROPIC_DEFAULT_SONNET_MODEL == "claude-haiku-5-5" and .env.ANTHROPIC_DEFAULT_FABLE_MODEL == "claude-haiku-5-5"
  and .availableModels == ["opus","haiku"]' "$T/home/.claude/settings.json" >/dev/null && ok "keys set, other settings kept" || no "settings content"

# dispatched <model-arg|"">: the model the real claude dispatches to, from its debug log.
dispatched() {
  rm -rf "$T/home/.claude/debug"
  local -a m=(); [ -z "$1" ] || m=(--model "$1")
  (cd "$T/w" && env -u CLAUDE_CONFIG_DIR -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_MODEL \
    -u ANTHROPIC_DEFAULT_SONNET_MODEL -u ANTHROPIC_DEFAULT_FABLE_MODEL HOME="$T/home" DISABLE_AUTOUPDATER=1 \
    timeout 60 claude -p hi "${m[@]}" --debug --output-format json >/dev/null 2>&1)
  grep -rhoE 'dispatching to [A-Za-z]+ model=[^ ]+' "$T/home/.claude/debug" 2>/dev/null | sed 's/.*model=//' | sort -u | tr '\n' ' ' | sed 's/ $//'
}
for c in sonnet:claude-haiku-5-5 fable:claude-haiku-5-5 claude-sonnet-5-5:claude-opus-5-5 claude-sonnet-4-5-20250929:claude-opus-5-5 \
  claude-fable-5-1:claude-opus-5-5 opus:claude-opus-5-5 haiku:claude-haiku-5-5 claude-opus-5-5:claude-opus-5-5 :claude-opus-5-5; do
  got=$(dispatched "${c%%:*}")
  [ "$got" = "${c#*:}" ] && ok "--model ${c%%:*} -> $got" || no "--model ${c%%:*} -> '${got:-no dispatch}', want ${c#*:}"
done

inst --restore > "$T/restore.out"
jq -e '.env.ANTHROPIC_DEFAULT_SONNET_MODEL == null and .env.ANTHROPIC_DEFAULT_FABLE_MODEL == null and .availableModels == null
  and .env.KEEP_ME == "1" and .theme == "dark"' "$T/home/.claude/settings.json" >/dev/null && ok "restore removes only its keys" || no "restore"
[ "$(dispatched claude-haiku-5-5)" = claude-haiku-5-5 ] && ok "restored config still runs" || no "restored config"

[ "$fail" -eq 0 ] && echo PASS || { echo FAIL; exit 1; }
