# Claude accounts: the chooser for new workers

## User outcome

New workers spread across eligible accounts of their provider in proportion to quota headroom, starting with the most headroom.

## Drive

Run `bash claude-accounts/tests/claude-accounts-pick.test.sh` (fixture registry, stub quota-axi, the add-on's own pool pick; 60:30:10 Claude headroom produces 6:3:1 across ten picks, Codex balances independently, concurrent picks retain assignments, and old assignments expire). For the real accounts, `FM_BIN=<fork bin> done-done run claude-accounts-pick` runs the pool pick fm-spawn calls against a throwaway config/account-pool, starts one tiny Haiku task on the picked profile folder and reads every account's quota before and after.

## Evidence

Capture `pick.txt` (ids, names and percentages only). Never open files inside a login folder or print a folder path or credential.
