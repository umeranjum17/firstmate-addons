# Persisted pipeline route

## User outcome

The pipeline runs the route the no-mistakes config holds: the OpenRouter DeepSeek floor route, and a call pinned to a model outside the chain lands on that route instead of the pinned model.

## Drive

Run `bash pipeline-quota-failover/tests/pi-quota-failover-route.test.sh` from the repository root. The test drives the real wrapper against a stub pi and a stub quota-axi in a throwaway HOME and verifies that the default chain is the persisted pipeline route, that a call pinned to that route runs it, that a call pinned outside the chain lands on it and never on the pinned model, and that an `openrouter/*` route is killed by the deepseek idle limit rather than the generic one.

## Evidence

Capture the test command's output and exit status in done-done's run evidence directory. Never use a real home, a real pi or a real config.
