# Parked-home fork call sites

Source: the task-provided fork checkout, inspected read-only from `git diff kun/main -- bin tests docs` and the current call-site files.

The compatibility form is an optional-source shim: step B adds no-op `fm_parked_refuse_meta` and `fm_parked_skip_meta` definitions to `bin/fm-parked-homes-lib.sh` before sourcing the add-on, so all replacements below remain allowed when the add-on is absent.

`fm_parked_refuse_meta META TASK ACTION` returns 1 and writes the existing refusal text to stderr only when parked; otherwise it returns 0.

`fm_parked_skip_meta META TASK ACTION` returns 0 and writes the existing skip line (when one exists) only when parked; otherwise it returns 1.

| Fork file:line | What it gates | Existing text and exit behavior | Step B one-line replacement |
|---|---|---|---|
| `bin/fm-bootstrap.sh:568` | config push and config-reread nudge | stdout `CONFIG_REREAD: secondmate $id: skipped - its home is parked (config/parked-homes)`; continue, no script exit | `fm_parked_skip_meta "$STATE/$id.meta" "$id" config-reread && continue` |
| `bin/fm-bootstrap.sh:713` | remote inheritance push and reread nudge | stdout `SECONDMATE_SYNC: secondmate $id: skipped - its home is parked (config/parked-homes)`; continue | `fm_parked_skip_meta "$meta" "$id" sync && continue` |
| `bin/fm-bootstrap.sh:767` | liveness probe and session-start relaunch | stdout `SECONDMATE_LIVENESS: secondmate $id: skipped: its home is parked (config/parked-homes)`; continue | `fm_parked_skip_meta "$meta" "$id" bootstrap-liveness && continue` |
| `bin/fm-config-push.sh:130` | config push and reread nudge | stdout `secondmate $id: skipped - its home is parked (config/parked-homes)`; continue | `fm_parked_skip_meta "$meta" "$id" config-push && continue` |
| `bin/fm-control.sh:1366` | local relaunch | stderr `error: relaunch refused for $ID: its home is parked (config/parked-homes); a parked home gets no relaunch`; exit 1 | `fm_parked_refuse_meta "$META" "$ID" relaunch || exit 1` |
| `bin/fm-model-outage-lib.sh:56` | model-outage scan and alert | no output; continue | `fm_parked_skip_meta "$meta" "$id" model-outage && continue` |
| `bin/fm-pending-reply-lib.sh:1589` | recovery resend and missed-report escalation | no output; continue, retaining the pending-reply record unchanged | `fm_parked_skip_meta "$state/${task_id}.meta" "$task_id" pending-reply && continue` |
| `bin/fm-remote-secondmate-relaunch.sh:54` | remote relaunch | stderr `error: relaunch refused for $ID: its home is parked (config/parked-homes); a parked home gets no relaunch`; `die` exits 1 | `fm_parked_refuse_meta "$META" "$ID" relaunch || exit 1` |
| `bin/fm-secondmate-reconcile.sh:473` | reconciliation, ask, and cooldown | stdout `skipped: $id parked`; continue | `fm_parked_skip_meta "$STATE/$id.meta" "$id" reconcile && continue` |
| `bin/fm-secondmate-restart.sh:136` | restart-pass relaunch | stdout `parked: $id: its home is parked (config/parked-homes); the restart pass skipped it`; excludes id from `LIVE_IDS` | `fm_parked_skip_meta "$STATE/$id.meta" "$id" restart && continue` |
| `bin/fm-send.sh:551` | message/steer/answer/nudge delivery | stderr `error: nothing sent to ${TARGET_TASK_ID:+fm-$TARGET_TASK_ID}: its home is parked (config/parked-homes); a parked home gets no message, steer, answer or nudge`; exit 1 | `fm_parked_refuse_meta "$TARGET_META" "$TARGET_TASK_ID" send || exit 1` (inside existing nonempty-meta test) |
| `bin/fm-watch.sh:617` | doorbell, re-ring, and unread-instruction escalation | no output; return 0 from containing function | `fm_parked_skip_meta "$STATE/$task.meta" "$task" wake-doorbell && return 0` |
| `bin/fm-watch.sh:1075` | wake-drain ring and stalled check | no output; remove `.secondmate-wake-stall-$task`, `.secondmate-wake-progress-$task`, `.secondmate-wake-ring-$task`, then continue | `fm_parked_skip_meta "$meta" "$task" watch-wake-stall && { rm -f "$STATE/.secondmate-wake-stall-$task" "$STATE/.secondmate-wake-progress-$task" "$STATE/.secondmate-wake-ring-$task" 2>/dev/null || true; continue; }` |
| `bin/fm-watch.sh:1259` | liveness probe and auto-relaunch | triage log `secondmate $id liveness skipped: its home is parked (config/parked-homes)`; continue | `fm_parked_skip_meta "$meta" "$id" watch-liveness && { triage_log "secondmate $id liveness skipped: its home is parked (config/parked-homes)"; continue; }` |

The fork uses three fallback predicate definitions in `fm-bootstrap.sh`; they are shared no-op predicate setup, not separate policy call sites. The shim and these predicates remain fork-only step-B work.
