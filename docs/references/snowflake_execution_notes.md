# Snowflake execution notes: how CoCo runs Claude Code's SQL

> **Fetched / verified**: 2026-09-29, live on account `DA53081` (`AZURE_CENTRALINDIA`,
> **Enterprise** edition), Snowflake 10.35.101, through CoCo's SQL tool.
> **Sources**: CoCo's own test queries (query IDs below), plus
> <https://docs.snowflake.com/en/sql-reference/functions/random>,
> <https://docs.snowflake.com/en/sql-reference/functions/hash>,
> <https://docs.snowflake.com/en/sql-reference/functions/get_query_operator_stats>.
> Written by CoCo for Claude Code (B08b); Claude Code owns this file afterwards. CoCo adds
> new findings to the run reports (`docs/artifacts/runs/`), not here.

Read with `docs/DATA_SPEC.md` §8. Everything here was **observed**, unless marked
**INFERRED**.

---

## 1. The tool

CoCo runs SQL through one tool call per submission. Each call:
- takes **one statement, or several separated by `;`**, and returns **only the last
  statement's result** (verified: `USE ROLE FORGE_ADMIN; SELECT CURRENT_ROLE()` returned one
  row, `FORGE_ADMIN`)
- has a default timeout of **180 s**; CoCo raises it to 1,200 s for long statements.
  Budget: **≤ 15 min per call**
- has a compile-only mode (`only_compile`), which CoCo uses first on every file

## 2. Session state is NOT kept between calls

| Test | Result |
|---|---|
| `SET FORGE_PROBE = 'persisted'`, then `SELECT $FORGE_PROBE` in the next call | worked (same session `…363634`) |
| a multi-statement call, then `SELECT $FORGE_PROBE` | **failed**: `Session variable '$FORGE_PROBE' does not exist`; the session id had changed (`…347258`) |
| `USE ROLE FORGE_ADMIN` in one call, `CURRENT_ROLE()` in the next | **`ACCOUNTADMIN`**: the role did not carry over |

**So:**
- Don't rely on session variables, `USE ROLE`, `USE WAREHOUSE`, `USE DATABASE` or
  `ALTER SESSION` carrying from one statement of your file to the next.
- Put anything that needs shared state **inside one Scripting block or one procedure**. A
  block runs as one call in one session.
- Parameters go into **procedure arguments**, not session variables. This is why
  DATA_SPEC §7 defines the generator as procedures.
- Defaults when nothing is set: role **`ACCOUNTADMIN`**, warehouse **`COMPUTE_WH`** (XS).
  CoCo sets the card's role and warehouse at the start of each call, e.g.
  `USE ROLE FORGE_ADMIN; USE WAREHOUSE FORGE_WH; CALL …`.

## 3. What works inside a block or procedure (verified)

```sql
-- A variable as GENERATOR's row count (returned 1234)
EXECUTE IMMEDIATE $$
DECLARE n INTEGER DEFAULT 1234; c INTEGER;
BEGIN
  SELECT COUNT(*) INTO :c FROM TABLE(GENERATOR(ROWCOUNT => :n));
  RETURN c;
END;
$$;

-- Switching database, then schema-qualified names (returned SUPPLY_CHAIN_FORGE:800)
EXECUTE IMMEDIATE $$
DECLARE db VARCHAR DEFAULT 'SUPPLY_CHAIN_FORGE'; c INTEGER;
BEGIN
  EXECUTE IMMEDIATE 'USE DATABASE ' || :db;
  SELECT COUNT(*) INTO :c FROM ERP_SOURCE.VBAK;
  RETURN CURRENT_DATABASE() || ':' || c;
END;
$$;
```

- `USE DATABASE` inside a block works. In a procedure it needs **`EXECUTE AS CALLER`**
  (owner's-rights procedures can't run `USE` or most `ALTER SESSION`; see
  `snowflake_scripting_procedures.md`).
- Inside a procedure body, don't nest `$$`. Build dynamic SQL with single-quoted strings,
  or bind with `EXECUTE IMMEDIATE … USING`.

## 4. Compile-only doesn't check procedure bodies

`only_compile` on `CREATE OR REPLACE PROCEDURE … AS $$ … SELECT … FROM ERP_SOURCE.VBAK_DOES_NOT_EXIST … $$`
reported **"SQL compiled successfully"** and created nothing (query `01c76476-…c282`).
Errors in the body only show at `CALL` time.

**So:**
- Keep each procedure's statements simple enough that CoCo can compile them one by one
  outside the procedure (substituting the parameters).
- Add a **small-scale dry run** to every hand-over, e.g. `CALL OPS.SP_GENERATE_DATA('SUPPLY_CHAIN_FORGE', 0.01, 20260929, '2026-09-30')`.
  CoCo runs it before the full run.
- Wrap risky statements in `EXCEPTION WHEN OTHER THEN` blocks that return `SQLERRM` with
  the stage name, so the run report can say exactly where a run broke.

## 5. Determinism (the generator)

- `RANDOM(seed)` and `UNIFORM(…, RANDOM(seed))` **are not reproducible across runs** (docs:
  a different worker count or row order changes the values). Don't use them.
- `HASH` is stable for the same input **types**: `HASH(10)` ≠ `HASH('10')` (docs). Keep the
  argument types fixed.
- **Verified**: this recipe gave `HASH_AGG` `5241903297775745443` on 5M rows twice, on
  `COMPUTE_WH` and on `FORGE_WH`, with `USE_CACHED_RESULT = FALSE` (queries
  `01c76463-…61ce`, `01c76464-…b06e`):

```sql
WITH ids AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ8()) AS n
             FROM TABLE(GENERATOR(ROWCOUNT => 5000000))),
u AS (SELECT n, BITAND(HASH(20260929, 'VBAK', n, 'date'), 4294967295) / 4294967295.0 AS u_date
      FROM ids)
SELECT COUNT(*), HASH_AGG(n, DATEADD(day, -FLOOR(u_date * 3653)::INT, '2026-09-29'::DATE)) FROM u;
```

- Speed: 3M hash-derived rows (3 attributes, a date) took **0.39 s on XS** (query
  `01c76453-…c11a`, count only, no write). Writing costs more; **INFERRED**: 2M rows well
  under a minute per table on XS.

## 6. Time-window patterns in `SEMANTIC_VIEW` (verified on the v1 view)

All three ran (DATA_SPEC §5.2):
- `WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE()`
  with OTD and landed cost
- `WHERE orders.order_date > …` with `order_lines.fill_rate` (a filter on a related table)
- `WHERE inventory.snapshot_date = (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY)`
  (a scalar subquery) with DOI by region

## 7. Query history and pruning (for the scale harness)

- `TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION())` has `TOTAL_ELAPSED_TIME`,
  `COMPILATION_TIME`, `EXECUTION_TIME`, `BYTES_SCANNED`, `ROWS_PRODUCED`, `WAREHOUSE_SIZE`,
  `QUERY_TAG`, but **no partition counts**.
- `TABLE(GET_QUERY_OPERATOR_STATS('<query_id>'))` has them, available right after the query
  finishes: `operator_statistics:pruning:partitions_scanned` and `:partitions_total` on
  `TableScan` rows (verified: `{"partitions_scanned":1,"partitions_total":1}`). Sum them over
  all `TableScan` operators.
- Use `LAST_QUERY_ID()` right after each statement in the same procedure.
- CoCo's tool sets its own JSON `QUERY_TAG` (`{"app":"cortex_code_cli",…}`). Set your own
  `QUERY_TAG` inside the procedure to find your queries.
- Turn off the result cache inside the procedure (`ALTER SESSION SET USE_CACHED_RESULT =
  FALSE`, caller's rights), or repeat timings are 0 ms.

## 8. Objects, owners and roles today

| Object | Owner | Notes |
|---|---|---|
| 9 source tables (`ERP/WMS/TMS/SRM_SOURCE`) | `ACCOUNTADMIN` | `FORGE_ADMIN` has **no** `SELECT` on them (until B15 grants 2 tables for §8) |
| 9 `GOVERNED` views | `ACCOUNTADMIN` | `SELECT` to `FORGE_ADMIN` and the 3 persona roles |
| `SEMANTIC.SUPPLY_CHAIN_SV` | `FORGE_ADMIN` | `SELECT` to the 3 persona roles |
| `SP_SAMPLE_AS_*`, `SP_METRICS_AS_*` | the persona roles | owner's rights; `USAGE` to `FORGE_ADMIN` |
| Schemas `CONFORMED`, `OPS` | — | created by CoCo at B08c, **before** C08 runs |

- Warehouses: `FORGE_WH` (XS, auto-suspend 60 s) for the project; `COMPUTE_WH` (XS) is the
  tool default. B13 creates a temporary larger one.
- As of v1, every source column is `NOT NULL`. DATA_SPEC §1 relaxes that at B08c; your
  generator writes into the v2 tables.
- Snowflake **enforces `NOT NULL`**, and does **not** enforce PK, FK or UNIQUE.

## 9. What CoCo does with a hand-over

1. Reads the header (card, role, warehouse, parameters, run order, expected results).
2. Compiles every top-level statement (`only_compile`).
3. Runs the dry run if one is given, then the real run, one call per top-level statement,
   with the card's role and warehouse set in each call.
4. Writes `docs/artifacts/runs/<card>_run.md`: each statement's outcome, verbatim errors,
   row counts, timings and query IDs. A run-blocking fix of a few lines is shown as a
   diff; anything bigger returns the file to you.
5. Marks the row in the HANDOFF "Ready for CoCo to run" table DONE or RETURNED.
