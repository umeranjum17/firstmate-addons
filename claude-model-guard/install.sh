#!/usr/bin/env bash
# Keep Claude Code off Sonnet and Fable for every session that reads this config dir (Main3410: a live lab ran
# --model sonnet). Three keys in <config-dir>/settings.json, edited at key level with a backup:
#   env.ANTHROPIC_DEFAULT_SONNET_MODEL, env.ANTHROPIC_DEFAULT_FABLE_MODEL = claude-haiku-5-5
#     the sonnet and fable aliases (--model sonnet, agent "model: sonnet") resolve to Haiku;
#   availableModels = ["opus", "haiku"]
#     any other model, such as a full id claude-sonnet-5-5 or claude-fable-5-1, is not selectable and Claude Code
#     falls back to the default model (Opus). Opus and Haiku in every version stay allowed.
# Usage: install.sh [--dry-run] [--restore] [--config-dir <dir>]   (default ${CLAUDE_CONFIG_DIR:-~/.claude})
# Prints only these key names and values; never the file, other keys, or credentials (never read or touched).
# --restore removes exactly these keys when they still hold the values above.
set -euo pipefail
DRY=0 RESTORE=0 DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY=1 ;;
    --restore) RESTORE=1 ;;
    --config-dir) DIR=${2:?--config-dir needs a path}; shift ;;
    *) echo "usage: install.sh [--dry-run] [--restore] [--config-dir <dir>]" >&2; exit 2 ;;
  esac
  shift
done
[ -d "$DIR" ] || { echo "install.sh: no Claude config dir at $DIR" >&2; exit 1; }
F=$DIR/settings.json
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
{ [ -s "$F" ] && cat "$F" || echo '{}'; } > "$TMP/old.json"
jq -e 'type == "object"' "$TMP/old.json" >/dev/null || { echo "install.sh: $F is not a JSON object; nothing changed" >&2; exit 1; }

H=claude-haiku-5-5
if [ "$RESTORE" -eq 1 ]; then
  jq --arg h "$H" '
    if .env.ANTHROPIC_DEFAULT_SONNET_MODEL == $h then del(.env.ANTHROPIC_DEFAULT_SONNET_MODEL) else . end
    | if .env.ANTHROPIC_DEFAULT_FABLE_MODEL == $h then del(.env.ANTHROPIC_DEFAULT_FABLE_MODEL) else . end
    | if .availableModels == ["opus", "haiku"] then del(.availableModels) else . end' "$TMP/old.json" > "$TMP/new.json"
else
  jq --arg h "$H" '.env.ANTHROPIC_DEFAULT_SONNET_MODEL = $h | .env.ANTHROPIC_DEFAULT_FABLE_MODEL = $h
    | .availableModels = ["opus", "haiku"]' "$TMP/old.json" > "$TMP/new.json"
fi

view='{ANTHROPIC_DEFAULT_SONNET_MODEL: .env.ANTHROPIC_DEFAULT_SONNET_MODEL, ANTHROPIC_DEFAULT_FABLE_MODEL: .env.ANTHROPIC_DEFAULT_FABLE_MODEL, availableModels}'
if jq -e --slurpfile o "$TMP/old.json" '. == $o[0]' "$TMP/new.json" >/dev/null; then
  echo "unchanged: $F $(jq -c "$view" "$TMP/new.json")"
  exit 0
fi
echo "$F: $(jq -c "$view" "$TMP/old.json") -> $(jq -c "$view" "$TMP/new.json")"
[ "$DRY" -eq 0 ] || { echo "dry run: nothing written"; exit 0; }
STAMP=$(date +%s)
cp "$TMP/new.json" "$F.tmp-$STAMP"
if [ -e "$F" ]; then
  cp -p "$F" "$F.bak-claude-model-guard-$STAMP" && chmod --reference="$F" "$F.tmp-$STAMP"
  echo "backup: $F.bak-claude-model-guard-$STAMP"
fi
mv "$F.tmp-$STAMP" "$F"
echo "written: $F"
