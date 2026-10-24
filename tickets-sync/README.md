# Tickets sync

Publishes each registered home's tasks-axi backlog to the sign-off board named by `config/fleet-board`.
Run `FM_HOME=<fleet-home> bash tickets-sync/install.sh` from merged main to register a lightweight watcher check; no daemon is added.
Requires Python 3.11+, tasks-axi, sign-off-axi and the Firstmate backlog reader libraries.
The installer supports `--dry-run`; pre-merge tests use a temporary `XDG_DATA_HOME` and fixture home.

The check includes open work and work closed in the last seven days, reading the configured markdown archive through tasks-axi after normalizing its Archived headings in a retained private copy under `state/tickets-sync/`.
Each pass yields after 20 seconds so large backfills continue on subsequent watcher checks within the usual 30-second check budget.
Ticket IDs are stable hashes of `home/item` (the public CLI disallows `/`); only changed fields are published, and previously published items close even after the backfill window.
Parked homes and held items are On hold; completion clears hold and sets progress to 100.
Queued work starts at 0%, active work at 17%, and completed work at 100%; these are lifecycle markers, not measured effort.
Epic progress follows sign-off's child average.
An explicit `parent:` or `epic:` body line supplies hierarchy; absent hierarchy is left empty.
Public ticket titles cap at 160 characters: long names are abbreviated, and links that exceed the available suffix space are counted in the sync output.
Release, state and source links use a title suffix because public ticket flags have no fields for them; source cards need their producer to supply `--ticket`.
The command fails visibly for unreadable, capped, remote or unsupported non-markdown backlogs; it never closes missing items by inference or mutates a backlog.
Run `FM_TEST_FORK=<Firstmate-checkout> bash tickets-sync/tests/sync.test.sh` for the installed check's idempotency, hierarchy, parking and archive close journey.
