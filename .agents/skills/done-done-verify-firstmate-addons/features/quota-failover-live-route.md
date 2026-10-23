# Quota failover: install in every home, and a real route failure recovers

## User outcome

The quota-failover watcher runs in Main and every active local secondmate home, and a worker stopped by a provider limit or a 429 moves to the next live route, or the next pool account, without a human. A worker on an account the pool does not name (such as the `ambient` id given to a codex or pi launch) takes the route move.

## Drive

- `FM_TEST_FORK=<Firstmate checkout> bash quota-failover/tests/install.test.sh`: `install.sh --all` on throwaway homes with the fork's own check registration; a parked, a remote and a broken home are named, a rerun changes nothing, `uninstall.sh --all` retires every check.
- `bash quota-failover/tests/quota-failover-e2e.sh`: the watcher on a fixture home; pass 3 holds the `ambient` codex worker's route move.
- Live: `FM_CHECKOUT=<Firstmate checkout> done-done run quota-failover-live-route` (`bash quota-failover/run-live-proof.sh`). It stands up a disposable lab (Haiku main), spawns one real worker on pi pinned to a local provider that answers HTTP 429, installs this checkout's watcher into a lab-only data path, and waits for the lab watcher's own pass to move the worker to Claude Haiku and for the worker to finish there. About 10 minutes; Haiku only; nothing is installed outside the lab.

## Evidence

`route.log` (install line, the move, PASS), `screen-before.txt` (the worker's real 429 error), `provider-429-hits.txt`, `quota-failover.log` (the watcher's `switched pi lab429/rl-model -> claude claude-haiku-5-5` line), `worker-route-after.txt`, `worker-status.txt` (the worker's `done` line) and `screen-after.txt`.
