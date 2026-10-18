# pi-quota-failover

Drop-in pi wrapper for the no-mistakes pipeline agent. It runs the real pi and moves to the next chain model when a call hits a quota error or goes silent.

## Quota pre-check

Before each route is called, `quota-axi --provider <prefix> --json` is asked about that route's provider. A route whose
`effectiveAvailability` has `runway.status` `exhausted_now` for `all_models` or its own `model:<id>` scope is skipped
without a pi call and gets a quota marker.

Fail-open cases (the route is tried as before, one log line says so):

- `quota-axi` is missing, exits non-zero (for example `error: unsupported provider: <name>` for a pi provider name it does not know) or takes longer than 10s. The wrapper maps the pi provider `openai-codex` to quota-axi's `codex`; other names pass unchanged.
- `jq` is not installed; the pre-check is off for every route.

An answer that is not parseable JSON is treated as not exhausted, without a log line.

## Idle watchdog

A pi call that writes no stdout and no stderr for `PI_QUOTA_FAILOVER_IDLE_SECS` (default 120) is ended with TERM to pi
and its descendants, then KILL of the same set after a 5 s grace. A stall is not a quota error: the chain moves on to the next model for that
call only and writes no quota marker, so the stalled route is tried again on the next call. A stall on the last route is retried once on that same route before the call fails. Only a real quota error
(or quota-axi `exhausted_now`) writes a marker. pi stays in the wrapper's process group, so a group kill of the wrapper
reaches it.

The watch starts at the call's first byte, session header included, with no separate start limit: the extension set below
removes pi-hermes-memory's startup sync, so a pi start is about 1 s (measured 2026-10-18: session header 1.0 s after pi
starts, `agent_start` 82 ms later). Before that change the silence between the session header and `agent_start` was 5 s to
134 s on this host (persistence sync 91.5 s with no prompt, 5.0 s with five other pi processes alive, up to 134 s in the
wrapper probes under load), so the 120 s watch killed those starts.

## Extensions

Every call runs `pi -ne` followed by `-e <path>` for each extension pi would load here, except `pi-hermes-memory`:

- the user packages from `pi list`: each package's `pi.extensions` entries (a directory entry loads its `index.ts`/`index.js`), or its `extensions/` directory when it has no manifest;
- the user extensions dir (`$PI_CODING_AGENT_DIR`, default `~/.pi/agent/extensions`): direct `.ts`/`.js` files and subdirectories with an `index`, so `fm-rm-guard` and `fm-literal-delete` load and backup copies do not;
- the `extensions` array of the agent-dir `settings.json`;
- pi's built-ins `builtin:mcp`, `builtin:llama.cpp`, `builtin:codemode` and `builtin:tool-search`, minus any the settings turn off with `-builtin:<name>`.

The list is read at call time. `pi-hermes-memory` is dropped by its package source (`npm:pi-hermes-memory`). Why: its
`session_start` sync runs before pi emits `agent_start`, and the 120 s watch above counted that silence as a stall.
If the list cannot be read (`pi list` fails, `jq` is missing, or `settings.json` does not parse), the wrapper runs pi as
before and logs one line naming the reason.

Not in the set: project-level extensions (`.pi/extensions/` and a project `.pi/settings.json`). pi loads those only for a
trusted project and `pi list` reports user packages only. Under `-ne` a pipeline call run from a trusted checkout that has
them loses them; the firstmate checkout has `fm-calm` and `fm-branch-supervision` in its `.pi/extensions/`.
