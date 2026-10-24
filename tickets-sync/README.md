# Tickets sync

Run `FM_HOME=<fleet-home> bash tickets-sync/install.sh` from merged main to register the existing watcher's poll; `--dry-run` writes nothing.
Requires Python 3.11+, tasks-axi, sign-off-axi and Firstmate's backlog libraries; the board comes from `config/fleet-board`.
Backlogs stay read-only: archive headings are normalized in retained copies under `state/tickets-sync/` before tasks-axi reads them.
Open work and seven days of completed work are backfilled by stable home/item hashes; closed items get 100%, active items 17%, and queued work 0%.
Parked homes and held items stay On hold; completion clears hold.
Captain asks are epic roots; `parent: <item id>` confirms hierarchy, `parent: upkeep` alone means System, and unconfirmed items sit under Needs a parent.
Project names resolve from the clone's origin when available; icons require matching names in the board's project registry.
Each poll yields after 20 seconds and saves its cursor; remote, capped and unsupported backlogs fail visibly.
Public titles cap at 160 characters: names may be abbreviated and excess links counted; release/state use the suffix, and existing cards need their producer to set `--ticket`.
Run `FM_TEST_FORK=<checkout> bash tickets-sync/tests/sync.test.sh` for the real-CLI install, hierarchy, parking, cutoff, idempotency and archive-close journey.
