# lookout-adapter

`lookout-firstmate` turns this fleet's real data into the `lookout.fleet.v1` document that [Lookout](https://github.com/umeranjum17/lookout) shows (its contract is `docs/adapter.md` there).

```
lookout-firstmate [--home DIR] [--no-build]          # print the JSON
lookout-firstmate --serve [--port N] [--bind ADDR]   # serve it at /fleet.json, for `lookout --source http://…/fleet.json`
```

It reuses the fleet dashboard builder (`fleet-dashboard/fm-dashboard.sh build`, run when `state/dashboard/data.json` is over 2 minutes old) and maps its `data.json` and `board.json` onto the contract; nothing is copied from the builder. Every home and state file is only read, and only whitelisted fields are taken (a lane's `.meta` gives model, harness and account id, nothing else).

Sources: `/proc` and the memory gate for `hosts`; `data.json` homes and agents with `board.json` cards for `homes`, `lanes` and `workers`; quota windows per provider and Claude account for `quota`; `board.json`'s flow lanes (30 days) for `merges`; lane history and devices for `history` and `devices`.

Test with fixture homes: `LOOKOUT_DIR=<lookout clone> lookout-adapter/tests/test.sh` (the contract check runs when `LOOKOUT_DIR` is set).
