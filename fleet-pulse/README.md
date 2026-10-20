# fleet-pulse
Append redacted captain messages from Claude session JSONL files to the private `<FM_HOME>/data/chat.tsv` file.
## Install and run
- Run `install.sh [--dry-run] <home>` to install `chat-tsv.py` in `<home>/bin`, then schedule it periodically with `FM_HOME=<home>`.
- Set `CHAT_TSV_TRANSCRIPTS` to override the default Claude projects directory.
- The extractor refuses to write unless Git confirms that `data/chat.tsv` is ignored in the home repository.
- Rows contain UTC ISO-8601 `at`, best-effort `work` (session cwd basename, or `main` for the home checkout/missing cwd), and one-line `text` columns.
- Metadata, sidechains, tool results, commands, reminders, injected wake text, mirror/summary/artifact wrappers are discarded; human text outside a wrapper is retained.
- Secrets and numeric codes are redacted before append; text is capped at 4000 characters with `[truncated]`, and per-reason drop counts go to stderr without message text.
- The output and sidecar are mode 600, the data directory is mode 700, and `uninstall.sh <home>` removes only the installed script.
## Check
- Run `bash tests/chat-tsv.test.sh` for wrapper filtering, mixed human retention, drop counts, redaction, the text cap, permissions, and rerun idempotency using disposable fixtures.
