# bearings-board

The Bearings board, run from the Firstmate checkout. This add-on is a thin wrapper: it copies no upstream code, so checkout updates reach it with no merge.

- `bin/fm-bearings-board.sh build <data.json>` runs the checkout's own build with every argument it was given; `path` does the same for the checkout's path and prints the board path it reports. The checkout validates its own payload.
- `FM_CODE_ROOT` (or `FM_HOME`) names the checkout.
- Dormant until wired. `install.sh <home>` points the home's `config/bearings-board-command` at a launcher; `uninstall.sh <home>` restores the hook and removes the launcher, keeping it when the home's board command may still name it.
- Not in this slice: the board extras (projects strip, underway/landed rows, Captain's Call cards, evidence thumbnails). They follow as separate slices.
- Upstream seam for those extras, if upstream wants them in the template: one empty named slot before `</body>` in `assets/board-template.html` (e.g. `<!-- fm-extras -->`) filled from an optional payload key. Until upstream has one, a later slice injects the extras before `</body>` itself, so no upstream line is copied either way.

Test: `bash bearings-board/tests/bearings-board.test.sh`.
