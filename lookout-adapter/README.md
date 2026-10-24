# lookout-adapter

`lookout-firstmate` turns this fleet's real data into the `lookout.fleet.v1` document that [Lookout](https://github.com/umeranjum17/lookout) shows (its contract is `docs/adapter.md` there).

```
lookout-firstmate [--home DIR] [--no-build]          # print the JSON
lookout-firstmate --serve [--port N] [--bind ADDR]   # serve it at /fleet.json, for `lookout --source http://…/fleet.json`
```

It reuses the fleet dashboard builder (`fleet-dashboard/fm-dashboard.sh build`, run when `state/dashboard/data.json` is over 2 minutes old) and maps its `data.json` and `board.json` onto the contract; nothing is copied from the builder. Every home and state file is only read, and only whitelisted fields are taken (a lane's `.meta` gives model, harness and account id, nothing else).

| Contract key | Source |
| --- | --- |
| `hosts` | `/proc` load, memory and disk; the memory gate and heavy jobs from `data.json` |
| `homes`, `lanes`, `workers` | `data.json` homes and agents, `board.json` cards and tickets |
| `quota` | `data.json` quota windows per provider and each Claude account |
| `merges`, `history`, `devices` | `board.json` flow lanes (30 days), `data.json` lane history and devices |

Test with fixture homes: `LOOKOUT_DIR=<lookout clone> lookout-adapter/tests/test.sh` (the contract check runs when `LOOKOUT_DIR` is set).
