#!/usr/bin/env bash
# Real tasks-axi -> installed watcher check -> real sign-off-axi, in isolated homes.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d "${FM_TICKETS_TEST_ROOT:-${TMPDIR:-/tmp}}/tickets-sync.XXXXXX")
trap 'echo "retained fixture and normalized archives: $work"' EXIT
fork=${FM_TEST_FORK:-$HOME/firstmate}
export HOME=$work/user XDG_DATA_HOME=$work/xdg SIGN_OFF_HOME=$work/signoff
export FM_HOME=$work/main
mkdir -p "$HOME" "$FM_HOME"/{data,config,state} "$work/parked/data"
ln -s "$fork/bin" "$FM_HOME/bin"
printf '{"schema":2,"items":[]}\n' > "$work/board.json"
printf '%s\n' "$work/board.json" > "$FM_HOME/config/fleet-board"
printf '%s\n' "- parked - Umer project (home: $work/parked; scope: demo)" > "$FM_HOME/data/secondmates.md"
printf 'parked\n' > "$FM_HOME/config/parked-homes"
printf '[markdown]\npath="data/backlog.md"\narchive="data/done-archive.md"\ndone_keep=0\n' > "$FM_HOME/.tasks.toml"
cp "$FM_HOME/.tasks.toml" "$work/parked/.tasks.toml"
(cd "$FM_HOME"; tasks-axi add parent 'Umer release' --repo alpha --priority 1 >/dev/null
 tasks-axi add held 'Umer paused item' --repo alpha --priority 1 >/dev/null
 tasks-axi hold held --reason 'Umer parked this item' --kind parked >/dev/null
 tasks-axi add child '[captain-ask] Umer settings' --repo alpha --priority 0 --body $'release: next\nepic: parent' >/dev/null)
(cd "$work/parked"; tasks-axi add parent 'Umer paused project' --repo beta --priority 2 >/dev/null)
printf '\n## Done\n- [x] recent - Umer shipped feature (repo: alpha) (done %s)\n- [x] old - Umer historical work (repo: alpha) (done 2000-01-01)\n' "$(date +%F)" >> "$FM_HOME/data/backlog.md"
source_before=$(sha256sum "$FM_HOME/data/backlog.md" "$work/parked/data/backlog.md")
bash "$root/tickets-sync/install.sh" --dry-run
test ! -d "$XDG_DATA_HOME/fm-tickets-sync"
bash "$root/tickets-sync/install.sh"
env -u FM_HOME "$FM_HOME/state/tickets-sync.check.sh"
ticket_id() { printf 'fm-%s\n' "$(printf '%s' "$1" | sha256sum | cut -c1-32)"; }
child=$(ticket_id main/child) parent=$(ticket_id main/parent) parked=$(ticket_id parked/parent)
sign-off-axi ticket "$work/board.json" --json > "$work/first.json" || { cat "$work/first.json"; exit 1; }
jq -e '.tickets | length == 5' "$work/first.json"
jq -e --arg id "$child" --arg parent "$parent" '.tickets[] | select(.id == $id) | .parent == $parent and .priority == "P0" and .asked == true and (.title | contains("next"))' "$work/first.json"
jq -e --arg id "$parked" '.tickets[] | select(.id == $id) | .hold == true' "$work/first.json"
jq -e --arg id "$(ticket_id main/held)" '[.tickets[] | select(.id == $id and .hold == true)] | length == 1' "$work/first.json"
before=$(sha256sum "$work/board.tickets.jsonl")
"$FM_HOME/state/tickets-sync.check.sh"
test "$before" = "$(sha256sum "$work/board.tickets.jsonl")"
test "$source_before" = "$(sha256sum "$FM_HOME/data/backlog.md" "$work/parked/data/backlog.md")"
echo 'PASS: repeat sync writes no tickets; same item id in different homes stays distinct'
(cd "$FM_HOME"; tasks-axi 'done' child --pr https://github.com/example/alpha/pull/1 >/dev/null)
"$FM_HOME/state/tickets-sync.check.sh"
sign-off-axi ticket "$work/board.json" --id "$child" --json > "$work/closed.json"
jq -e '.ticket | .progress == 100 and .hold == false and (.title | contains("https://github.com/example/alpha/pull/1"))' "$work/closed.json"
echo 'PASS: close-on-done reads the pruned archive and retains PR and epic'
before=$(sha256sum "$work/board.tickets.jsonl")
"$FM_HOME/state/tickets-sync.check.sh"
test "$before" = "$(sha256sum "$work/board.tickets.jsonl")"
echo 'PASS: completed sync stays idempotent'
