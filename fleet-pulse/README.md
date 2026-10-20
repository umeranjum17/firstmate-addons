# fleet-pulse

Append redacted captain messages from Claude session JSONL files to the private `<FM_HOME>/data/chat.tsv` file.

## Install and run

`install.sh [--dry-run] <home>` installs `chat-tsv.py` in `<home>/bin`.

Schedule `<home>/bin/chat-tsv.py` periodically with `FM_HOME=<home>`; the sidecar `<home>/data/chat.tsv.seen` makes repeated runs append-only and idempotent.

Set `CHAT_TSV_TRANSCRIPTS` to override the default Claude projects directory when needed.

The extractor refuses to write unless Git confirms that `data/chat.tsv` is ignored in the home repository.

It writes `at`, `work`, and `text` as tab-separated columns; timestamps are UTC ISO-8601 and text is flattened to one line.

`work` is the session cwd basename, except the home checkout itself (or missing cwd) is labelled `main`.

Only user records with textual content are considered; metadata, sidechains, tool results, commands, reminders, and injected system/hook/notification wrappers are discarded.

Known mirror, compaction-summary, and artifact wrappers are removed; human text outside a wrapper is retained.

Every discard and truncation reason is counted on stderr without including message text.

Secrets and numeric codes are redacted before append, intentionally favoring false positives over disclosure.

Text is capped at 4000 characters per row, with a `[truncated]` marker when capped.

The output and sidecar are mode 600, and the data directory is mode 700.

`uninstall.sh <home>` removes the installed extractor but leaves collected data untouched.

## Check

`bash tests/chat-tsv.test.sh` exercises wrapper filtering, retained mixed human text, drop counts, redaction, the text cap, file permissions, and rerun idempotency using a disposable transcript and home.
