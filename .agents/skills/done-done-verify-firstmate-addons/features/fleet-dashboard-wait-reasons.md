# Fleet dashboard wait reasons

## User outcome

Insights names each waiting task's recorded reason, leaves only missing reasons under Unclassified, and excludes parked in-flight tasks from Open.

## Drive

Use the task-approved live dashboard URL in an isolated Chrome page with `chrome-devtools-axi`. Open Insights, resize to `390 844`, capture the before screen, then refresh the candidate dashboard and capture the after screen. Expand each wait group and the parked group; check home/task names, the source reason, and that Open excludes parked tasks. The card must distinguish captain holds, parked projects, dependencies, lane caps and truly unrecorded reasons.

## Evidence

Keep the before and after captures and the observed counts under the task's done-done evidence folder. The Unclassified rows must enumerate each genuinely unrecorded home/task; do not use synthetic fixtures as the real-fleet proof.
