# C12 — Scale-test harness (`tests/scale/`)

| | |
|---|---|
| **Owner** | Claude Code writes; CoCo runs (handoff lock) at **B13**, on a zero-copy clone loaded at a large scale factor, and captures **art 12** |
| **Milestone** | M5, replan Day 2 (30 Sep) |
| **Prerequisite** | `docs/DATA_SPEC.md` §7.4 (B08b ✅); contract v1.5 §3a, §4, §5, §8 ✅. **To run**: B09 (the view has `orders.order_year_quarter`), then B13's clone with its own regenerated semantic view and procedures |
| **Writes** | `tests/scale/00_setup.sql`, `10_scale_queries.sql` (generated), `20_sp_scale_run.sql`, `99_run.sql`, `build_scale_queries.py` (the generator), `report_template.md`, `README.md`; `tests/unit/test_scale_sql.py` |
| **Status** | ✅ **READY** 2026-09-29: approved by the user, built, and handed to CoCo (HANDOFF "Ready for CoCo to run"). Offline gate green: `tests/unit/test_scale_sql.py` 16 checks; I made 5 deliberate breaks and each was caught. `pytest -q` 400 passed. The live gate is CoCo's `C12_run.md` + art 12 (B13) |

---

## Goal

One procedure runs **every query the core system sends** against any database: the
original at SF 1, or a clone with 100M+ order lines. For each query it records how long it
took, how much data it read, how much Snowflake skipped (pruning), a fingerprint of the
answer and a fingerprint of the SQL text. Art 12 then shows three things with numbers:
- **the same SQL** runs at every scale (identical SQL fingerprints)
- **the same answer for every persona** at every scale (identical answer fingerprints)
- **the cost and speed** of each path on a small and a larger warehouse

## Why

- The core claim for a real business: the question → definition → SQL → governance path
  doesn't change with data size; only the infrastructure knobs do (warehouse size,
  clustering). This harness is the evidence.
- The queries are **the exact SQL the app sends** (generated from
  `forge_data.build_metric_sql` and `NAIVE_OTD_SQL`, with the database name swapped for a
  placeholder). So "scales" is proven for the real product, not for a test copy.

## Design

**A query catalogue, `OPS.SCALE_QUERIES`**, generated from the app's own code by
`build_scale_queries.py`, which writes `10_scale_queries.sql`. A test fails if the file
drifts from the app. It holds about 75 queries:

| Path | Queries | Time window |
|---|---|---|
| `SEMANTIC_VIEW` | the 4 metrics, all-time | `ALL` |
| `SEMANTIC_VIEW` | the 4 metrics, the §3a default window | `T12M` (DOI: `LATEST`) |
| `SEMANTIC_VIEW` | every valid metric × dimension pairing: **58** (the contract's 55 + `orders.order_year_quarter` from CR-006) | `T12M` / `LATEST` |
| `PROCEDURE` | `SP_METRICS_AS_{PLANNER,BUYER,LOGISTICS}` | as the procedures define |
| `NAIVE` | the §8 naive OTD query (raw source tables) | `T12M` |
| `AGENT` | 5 evaluation questions, **inactive by default**: they need a clone-local agent, which CoCo decides on at B13 | — |

Each row holds:
- the SQL, with `{{DB}}` where the database name goes
- a `HASH_EXPR` that fingerprints the answer, with numbers rounded to 6 dp. For the three
  persona procedures the persona column is left out, so identical fingerprints prove
  identical numbers.
- the path, the metric, the dimension and the time window

**The runner: `OPS.SP_SCALE_RUN(TARGET_DB, RUN_LABEL, RESULTS_TABLE)`**. Caller's rights,
run as `FORGE_ADMIN`, exactly per §7.4:
1. It turns off the result cache and sets `QUERY_TAG = 'forge_scale:<label>'`.
2. For each active query it substitutes `TARGET_DB` and runs the query. Then it collects:
   - timings, bytes scanned, rows and warehouse size, from
     `QUERY_HISTORY_BY_SESSION` for that query ID
   - partitions scanned and total, summed over `TableScan` operators, from
     `GET_QUERY_OPERATOR_STATS`
   - `RESULT_HASH`, from `RESULT_SCAN`
   - `SQL_HASH` = `HASH` of the template
3. It writes one row per query to `RESULTS_TABLE` (default `SUPPLY_CHAIN_FORGE.OPS.SCALE_RESULTS`,
   so results survive dropping the clone), with the §7.4 columns.
4. A failing query records its error, and the run continues.
5. It returns `{"run_label", "queries", "failed", "total_elapsed_ms", "max_elapsed_ms"}`.

**One small addition**: an optional 4th argument, `QUERY_FILTER` (default `NULL` = all).
It's a `LIKE` pattern, so CoCo can split a slow run on an XS warehouse into batches under
the 15-minute limit. The 3-argument call in §7.4 still works.

**`99_run.sql`**, the order for B13:
1. a baseline on `SUPPLY_CHAIN_FORGE` at SF 1, on XS
2. the clone on XS
3. the clone on the larger warehouse

It also includes the queries art 12 needs:
- SQL fingerprints identical across the three runs
- persona fingerprints identical within each run
- per-path timing and pruning (p50, max)
- credits from `WAREHOUSE_METERING_HISTORY`
- dynamic-table refresh times from `DYNAMIC_TABLE_REFRESH_HISTORY`

**`report_template.md`**: the outline of art 12, with the tables CoCo fills in and the
three claims each table proves.

## As built (29 Sep)

- As designed: 75 catalogued queries (70 active), generated by
  `tests/scale/build_scale_queries.py`. The test fails if the committed SQL differs from
  the generator's output.
- `99_run.sql`:
  - three runs, with a suggested clone name `SUPPLY_CHAIN_FORGE_SCALE` (use B13's)
  - the three claims as queries that must return 0 rows or single fingerprints
  - timing and pruning by path, the 5 slowest queries per run, data volume, DT refresh
    times, and credits
- Applies CoCo's run lessons from the start:
  - no `;` in comments
  - `COMMENT` before `EXECUTE AS`
  - scalar-subquery assignments, not `SELECT … INTO` without `FROM`
  - history selects wrapped in `MAX()`, so they always return one row
- **Claim 3 was added**: XS and the larger warehouse give identical answer fingerprints on
  the clone (a knob changes speed, never answers).

## Decisions where the spec leaves room (listed for CoCo in HANDOFF)

1. **58 pairings, not 55**: contract v1.5 added `orders.order_year_quarter`. The catalogue
   follows `config.VALID_PAIRINGS`, which the contract tests keep equal to §4.
2. **The query list is a table**, generated from the app's code, rather than strings built
   inside the procedure. It's the same queries and the same `SQL_HASH` idea, and it's
   testable offline.
3. **`RESULT_HASH` rounds by named columns** (`HASH_EXPR` per query), because a generic
   `HASH_AGG(*)` can't round.
4. **The optional `QUERY_FILTER` argument** (above).
5. **The naive query needs `SELECT` on `VTTK`/`VBAK` for `FORGE_ADMIN`**, which is B15's
   grant. Until then it records a permission error; nothing else is affected.

## To verify live (CoCo, in `docs/artifacts/runs/C12_run.md`)

- whether statements run inside a procedure appear in `QUERY_HISTORY_BY_SESSION` (the
  fallback is `QUERY_HISTORY_BY_USER`, filtered on the query ID)
- `RESULT_SCAN` on a `CALL` (the persona procedures)
- whether the clone keeps grants on its objects (`FORGE_ADMIN` on the clone's views and
  procedures)

## Steps

1. Write `build_scale_queries.py`. It generates `10_scale_queries.sql` from `forge_data`
   and `config`.
2. Write `00_setup.sql` (the catalogue table, the results table, grants),
   `20_sp_scale_run.sql`, `99_run.sql`, `report_template.md` and `README.md`.
3. Write `tests/unit/test_scale_sql.py` (offline). It checks:
   - the file equals the generator's output
   - every valid pairing is present
   - the templates equal the app's SQL with `{{DB}}`
   - there's no hard-coded database name in any template
   - the results table has the §7.4 columns
   - the persona fingerprints leave out the persona column
   - the headers, re-runnable DDL, and no `;` in comments

   Then a break-it check.
4. `pytest -q` green; hand over under the lock (HANDOFF row + "Latest from Claude Code").

## Gate (from CoCo's `docs/artifacts/runs/C12_run.md` and art 12)

- Every path returns on the clone.
- Every query's `SQL_HASH` is identical across the three runs.
- The three persona fingerprints are identical within each run.
- Timings, pruning and credits are recorded for XS and the larger warehouse.

## On completion

1. This card
2. `.agents/NEXT.md` (C12 row)
3. `.agents/HANDOFF.md` ("Latest from Claude Code" + the "Ready for CoCo to run" row)
4. `docs/SESSION_LOG.md`
5. `.agents/tasks/README.md` "Written:" list
