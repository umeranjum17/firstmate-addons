# Quota failover screen matching

## User outcome

Claude's route remains available when a worker screen contains the failover wrapper's `quota exhausted` text; Claude's own usage-limit banner removes the route only after its one-line probe confirms the limit.

## Drive

Run `bash quota-failover/tests/quota-failover-real-proof.sh` from the repository root. It invokes the real failover script against a disposable fixture home twice: first with wrapper text, then with Claude's exact usage-limit banner and a confirming probe. It does not use a real home or credentials.

## Evidence

The journey writes both `.screen` inputs, dispatch state before and after, dead-route state, and the failover log under `DONE_DONE_EVIDENCE_ROOT`. Check that `after-wrapper.json` still contains `claude-haiku-5-5` and `after-limit-banner.json` has no route; `dead-routes.json` records the removed route.
