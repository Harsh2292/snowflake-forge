# `tests/scale/`: the scale harness (C12)

One procedure runs **every query the core system sends** against any database: the
original at SF 1, or B13's clone with 100M+ order lines. For each query it records:
- time and bytes scanned
- how much Snowflake pruned
- a fingerprint of the answer
- a fingerprint of the SQL

Art 12 uses those records to prove three claims:
- the same SQL runs at every scale
- every persona gets the same numbers
- the warehouse size changes speed, never answers

Written by Claude Code; run by CoCo at **B13** (handoff lock). Card:
`.agents/tasks/claude/C12_scale_harness.md`. Spec: `docs/DATA_SPEC.md` §7.4.

## Files, in run order

| File | Role | What it does |
|---|---|---|
| `00_setup.sql` | `ACCOUNTADMIN` | `FORGE_ADMIN` can create objects in `OPS` |
| `10_scale_queries.sql` | `FORGE_ADMIN` | `OPS.SCALE_QUERIES`: 75 queries (70 active). **Generated**, don't edit by hand |
| `20_sp_scale_run.sql` | `FORGE_ADMIN` | `OPS.SP_SCALE_RUN(TARGET_DB, RUN_LABEL, RESULTS_TABLE [, QUERY_FILTER])` |
| `99_run.sql` | `FORGE_ADMIN` | Three runs (`sf1-xs`, `clone-xs`, `clone-large`) + every art 12 query |
| `build_scale_queries.py` | — | Writes `10_scale_queries.sql` from the app's SQL builders |
| `report_template.md` | — | The outline of art 12 |

## The catalogue is the app's own SQL

`build_scale_queries.py` calls:
- `forge_data.build_metric_sql`
- `NAIVE_OTD_SQL`
- `build_call_sql`
- `build_agent_sql`

It then swaps the database name for `{{DB}}`. So the harness measures exactly what the app
sends. `tests/unit/test_scale_sql.py` fails if the committed file drifts from the
generator.

**After changing the app's queries or the contract pairings, run:**

```
.venv/Scripts/python tests/scale/build_scale_queries.py
```

| Path | Queries | Fingerprint |
|---|---|---|
| `SEMANTIC_VIEW` | 4 metrics all-time + 4 in the §3a window + 58 pairings | dimension + metric rounded to 6 dp |
| `PROCEDURE` | `SP_METRICS_AS_{PLANNER,BUYER,LOGISTICS}` | the 4 metrics without the persona column, so equal fingerprints mean equal numbers |
| `NAIVE` | the §8 naive OTD (raw source tables) | the value rounded to 6 dp |
| `AGENT` | 5 questions, **inactive**: they need a clone-local agent (B13 decides) | none: timing only |

## To verify live (CoCo, in `docs/artifacts/runs/C12_run.md`)

1. Whether statements run inside a procedure appear in `QUERY_HISTORY_BY_SESSION`. The
   fallback is `QUERY_HISTORY_BY_USER`, filtered on the query ID.
2. Whether `RESULT_SCAN` works on a `CALL` (the persona procedures).
3. Whether the clone keeps the grants on its objects (`FORGE_ADMIN` on the clone's views
   and procedures).
4. The naive query needs `SELECT` on `VTTK`/`VBAK` for `FORGE_ADMIN` (B15's grant). Until
   then it records a permission error.
