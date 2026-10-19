# bearings-board

The Bearings board, run from the Firstmate checkout. This add-on is a thin wrapper: it copies no upstream code, so checkout updates reach it with no merge.

- `bin/fm-bearings-board.sh build <data.json>` checks the payload is JSON, then runs the checkout's own build with the arguments it was given. `path` prints the board path the checkout reports.
- `FM_CODE_ROOT` (or `FM_HOME`) names the checkout.
- Dormant until wired. `install.sh <home>` points the home's `config/bearings-board-command` at a launcher; `uninstall.sh <home>` restores the hook and removes the launcher, keeping it when the home's board command may still name it.
- Not in this slice: the board extras (projects strip, underway/landed rows, Captain's Call cards, evidence thumbnails). They follow as separate slices.

Test: `bash bearings-board/tests/bearings-board.test.sh`.
