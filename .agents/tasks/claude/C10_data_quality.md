# C10 — Data-quality SQL + the agent's data-health tool (`quality/`)

| | |
|---|---|
| **Owner** | Claude Code writes; CoCo runs (handoff lock) at **B12**, and attaches the tool at **B10** |
| **Milestone** | M3/M4, replan Day 1–2 (29–30 Sep) |
| **Prerequisite** | `docs/DATA_SPEC.md` §4, §5.1, §7.2 (B08b ✅); contract v1.5 ✅. **To run**: B08c done (the v2 source tables loaded by C08, and the `CONFORMED` dynamic tables) |
| **Writes** | `quality/00_setup.sql`, `10_custom_dmfs.sql`, `20_sp_attach_dmfs.sql`, `30_sp_data_health.sql`, `40_sp_dq_self_checks.sql`, `99_run.sql`, `README.md`; `tests/unit/test_quality_sql.py`; small app fix in `app/utils/forge_data.py`, `app/utils/mock_data.py`, `app/ui/payloads.py`; test updates in `tests/unit/test_data_layer.py`, `tests/unit/test_data_gen_sql.py`, `tests/governance/test_source_isolation.py` |
| **Status** | ✅ **READY** 2026-09-29: approved by the user, built, and handed to CoCo (HANDOFF "Ready for CoCo to run"). Offline gate green: `tests/unit/test_quality_sql.py` 47 checks; `pytest -q` 333 passed; `pytest -m ui` 20 passed. The live gate is CoCo's run report `docs/artifacts/runs/C10_run.md` (B12) |

---

## Goal

Snowflake measures the data quality of both layers every time the data changes, and one
procedure, `SEMANTIC.SP_DATA_HEALTH(entity)`, turns those measurements into a short,
governed answer: how fresh each entity is, the as-of date, and which checks pass. The
agent calls it as a custom tool; the app already calls it for the as-of date and the Data
health screen.

## Why

- The claim "same governed number for everyone" needs a trust story: the raw systems are
  messy (DATA_SPEC §4), and the cleaned layer provably isn't. DMFs on **both** layers show
  the defects in `SOURCE` and their absence in `CONFORMED`.
- The agent must be able to say "the data is as of 29 Sep, and it's clean" without reading
  any row. `SP_DATA_HEALTH` returns counts and rates only.
- **Scale-invariant** (core rule): the procedure reads DMF results plus `COUNT(*)` /
  `MAX()` per table, which Snowflake answers from metadata. Its cost doesn't grow with the
  data. DMFs run serverless, only when the data changes.

## Design

One **check catalogue**, `OPS.DQ_CHECKS`, drives everything: which DMF is attached where
(file 20), how each result is judged (file 30), and what the self-checks expect (file 40).
One row per check:

| Column | Meaning |
|---|---|
| `CHECK_NAME`, `CODE` | e.g. `missing_promised_date`, `E01` (the §4 code) |
| `ENTITY` | one of the 9 semantic-view table names |
| `LAYER`, `SCHEMA_NAME`, `TABLE_NAME`, `COLUMNS` | where it's attached, e.g. `SOURCE`, `TMS_SOURCE`, `VTTK`, `PROM_DLV_DT` |
| `DMF`, `REF_TABLE`, `REF_COLUMN` | the function; the second table for the two orphan checks |
| `EXPECT` | `ZERO` (must be 0), `MAX_RATE` (≤ threshold), `INFO` (expected in raw data; always OK), `VOLUME` / `FRESHNESS` (attached, not listed as checks) |
| `TARGET_RATE`, `THRESHOLD_RATE` | the §4 rate and twice it (E-codes) |
| `HANDLED_BY` | the one-line rule shown to users, e.g. "Excluded from on-time delivery" |

How each layer is judged (§7.2 status rules, made explicit per row):

| Check (code) | `SOURCE` | `CONFORMED` |
|---|---|---|
| duplicate keys (M01/M02), non-contract codes (M03), test records (M04) | `INFO` (always OK) | `ZERO` |
| missing promised date (E01) | `MAX_RATE` 1.6% | `MAX_RATE` 1.6% (the row stays visible) |
| over-shipment (E04), negative on-hand (E05), orphans (E09a/b) | `MAX_RATE` 2% / 0.6% / 0.4% | `ZERO` (capped, zeroed, dropped) |
| cost outliers (E08) | — (needs FX) | `MAX_RATE` 0.2% (flag `COST_OUTLIER`) |

Rates are `value ÷ ROW_COUNT` of the same table, both from the DMF results, so the
denominator is measured at the same time and nobody needs to read a source table.

### Files

1. **`00_setup.sql`** (`ACCOUNTADMIN`)
   - `OPS` if missing
   - `OPS.DQ_CHECKS` (`CREATE OR REPLACE … AS SELECT … FROM VALUES`)
   - one tiny reference table per code domain, `OPS.DQ_VALID_<DOMAIN> (CODE)`, holding the
     contract §4 values (carriers from DATA_SPEC §3.4). They're `IF NOT EXISTS` plus an
     insert of missing values, never replaced, because DMF associations point at them.
   - `OPS.V_CONFORMED_FACTS`: 9 rows (entity, table, `COUNT(*)`, `MAX(load_ts)`,
     `MAX(business date)`). It's an aggregate-only view, owned by `ACCOUNTADMIN`.
   - Grants to `FORGE_ADMIN`:
     - `SELECT` on that view and on `DQ_CHECKS`, so it never needs `SELECT` on raw or
       `CONFORMED` rows (least privilege)
     - the `SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER` application role
     - `EXECUTE DATA METRIC FUNCTION ON ACCOUNT` and `SNOWFLAKE.DATA_METRIC_USER` for the
       table-owner roles
2. **`10_custom_dmfs.sql`** (`ACCOUNTADMIN`): 7 custom DMFs in `OPS`. They use
   `CREATE OR ALTER`, so re-running never breaks an existing association. They carry the
   names the app already expects:
   - `DMF_OVERSHIP_COUNT (qty_ordered, qty_shipped)`: shipped > ordered
   - `DMF_NEGATIVE_ON_HAND_COUNT (qty)`: < 0
   - `DMF_TEST_RECORD_COUNT (id, name)`: the §4 M04 rule, i.e. an ID starting `TEST` or
     `MAT9999`, a name starting with the word `TEST`/`DUMMY`, or containing `DO NOT USE`
   - `DMF_NONCONTRACT_CODE_COUNT (code, TABLE(valid codes))`: non-NULL values outside the
     domain's contract set. It's one function, and the domain comes from which
     `DQ_VALID_<DOMAIN>` table it's attached with.
   - `DMF_ORPHAN_ORDER_LINES`, `DMF_ORPHAN_SHIPMENTS (order_id, TABLE(orders))`: compared
     on `UPPER(TRIM())`, so an M07 case variant isn't miscounted as an orphan
   - `DMF_COST_OUTLIER_COUNT (dq_flags)`: rows flagged `COST_OUTLIER`
3. **`20_sp_attach_dmfs.sql`** (`ACCOUNTADMIN`): `OPS.SP_ATTACH_DMFS(TARGET_DB, SCHEDULE)`,
   caller's rights, `RETURNS TABLE`.
   - For each table in the catalogue, it sets the schedule and then adds each DMF.
   - It's **re-runnable**: an association that already exists is reported `EXISTS`, and
     calling it again with a new schedule only changes the schedule.
   - If a dynamic table rejects `ALTER TABLE`, it retries with `ALTER DYNAMIC TABLE`. If
     it rejects `TRIGGER_ON_CHANGES`, it falls back to `USING CRON 0 6 * * * UTC` (§7.2).
   - It returns one row per statement (object, DMF, action, status, error), which is
     exactly what the run report needs.
   - `TARGET_DB` lets B13 point it at a clone; `SCHEDULE = ''` suspends every DMF there.
   - About 76 associations: 37 on `SOURCE`, 39 on `CONFORMED`.
4. **`30_sp_data_health.sql`** (`FORGE_ADMIN`): `SEMANTIC.SP_DATA_HEALTH(ENTITY VARCHAR)
   RETURNS VARIANT`, `EXECUTE AS OWNER`, `USAGE` to the 3 persona roles. It builds exactly
   the §7.2 shape:
   - Input:
     - the entity is case-insensitive
     - `ALL` gives all 9 entities in spec order
     - anything else returns `status: "ERROR"` with a message, never an exception
   - What it reads (static SQL, no dynamic SQL):
     - the latest result per association from `DATA_QUALITY_MONITORING_RESULTS`, joined to
       the catalogue
     - `OPS.V_CONFORMED_FACTS`
   - Statuses:
     - freshness is judged against `SYSDATE()`: `OK` up to 36 h, `WARN` 36–72 h, `FAIL`
       beyond 72 h (`LOAD_TS` is UTC)
     - a check is `UNKNOWN` until its DMF has a result
     - entity and top-level status are the worst of their parts, in the order
       OK < UNKNOWN < WARN < FAIL
   - `as_of_date`:
     - for one entity, that entity's latest business date
     - for `ALL`, the shipments' date (§5.2)
   - `summary`: one plain sentence, e.g. "Shipments are fresh (loaded 5 h ago). 2 edge
     cases handled; no repairable defects left."
   - **Size guard**: if `ALL` would exceed 16 KB (≈ 45 checks × 330 B is close), it lists
     only the checks that aren't OK and says so in the summary. It's deterministic, and
     the shape is unchanged.
   - If `CONFORMED` or the DMF results aren't there yet, it still returns the full shape,
     with `UNKNOWN` and `null`s.
   - The header carries the agent tool YAML from §7.2, for B10.
5. **`40_sp_dq_self_checks.sql`** (`ACCOUNTADMIN`): `OPS.SP_DQ_SELF_CHECKS(TARGET_DB)
   RETURNS TABLE (CHECK_ID, TABLE_NAME, EXPECTED, ACTUAL, TOLERANCE, PASSED, DETAIL)`, the
   same shape as C08's self-checks. It's the gate as a query:
   - every association has a result
   - every `SOURCE` defect is non-zero, and each E-rate is within tolerance of its §4 rate
   - every `CONFORMED` `ZERO` check is 0
   - `SP_DATA_HEALTH` returns every key for all 9 entities and `ALL`, `ERROR` for a bad
     entity, and ≤ 16 KB for `ALL`
6. **`99_run.sql`**: the driver, one `CALL` per statement:
   - create 00 → 40
   - attach with `'5 MINUTE'`, so results appear for the gate: the data is already
     loaded, so `TRIGGER_ON_CHANGES` wouldn't fire
   - wait at least 10 minutes, then run the self-checks
   - switch to the steady schedule, `TRIGGER_ON_CHANGES` (CRON where it's refused)
7. **`README.md`**: what each file does, the run order and the to-verify list.

### App and tests

- **App fix (one line + mock).**
  - `NULL_COUNT` leaves `_QUALITY_EXPECT_ZERO`: in `CONFORMED`, missing promised dates
    stay visible by rule (E01), so a non-zero value there is correct, not a failure.
  - The mock row for `CONFORMED.SHIPMENT` `NULL_COUNT` goes from 0 to a realistic count.
- **`tests/unit/test_quality_sql.py`** (offline), checking that:
  - the files exist, with headers (card, role, warehouse, run order, expected results)
  - they're re-runnable (`CREATE OR REPLACE`, `CREATE OR ALTER` or `IF NOT EXISTS`), with
    balanced `$$`
  - no file names the account (the existing account test gains `quality/`)
  - the DMF names equal the names the app labels
  - the catalogue covers every row of the §7.2 minimum table
  - the thresholds are twice the §4 rates
  - the valid-code tables equal the contract §4 values in `config.py`
  - the entity order equals `forge_data.HEALTH_ENTITIES`
  - the procedure FQN equals `config.DATA_HEALTH_PROC`, with `EXECUTE AS OWNER`
  - every §7.2 JSON key is built
  - `SP_DATA_HEALTH` never reads a masked column or a source schema
- The source-isolation test also forbids `CONFORMED` and `OPS` in `app/`.

## As built (29 Sep)

- Everything in the design above, as written. The catalogue has 77 rows: 46 checks
  (suppliers 4, parts 4, sourcing 1, plants 2, inventory 4, customers 8, orders 6,
  order lines 6, shipments 11), 21 `ROW_COUNT` and 10 `FRESHNESS`.
- `CONFORMED.SOURCING` gets a duplicate-key check too (§5.1 rule 1). Check names are
  unique per table (`noncontract_region`, `noncontract_segment`, …), so the self-checks can
  match `SP_DATA_HEALTH`'s output back to the catalogue.
- `SP_DATA_HEALTH` stays readable before B12 and even before B08c. It returns the full
  shape, with `UNKNOWN` and a note in the summary.
- The self-checks accept a `SOURCE` E-code count between the injected count
  (`OPS.GEN_MESS_LOG`) and 1.25 × it + 5, because M01/M02 copies can repeat a defective
  row (E01 up to about +11%).
- App:
  - the Data health label for `NULL_COUNT` is now "Missing promised dates, left out of
    on-time delivery" (informational)
  - raw-data rows say "handled before use" instead of "repaired before use", since E01 rows
    are excluded, not repaired
  - `test_quality_results_have_status` follows the new rule
- Break-it check: 5 deliberate edits, each turning a test red: a threshold, a JSON key, a
  read of `CONFORMED`, a contract value and a DMF name.

## Decisions where the spec leaves room (listed for CoCo in HANDOFF)

1. **`FORGE_ADMIN` reads `CONFORMED` only through `OPS.V_CONFORMED_FACTS`** (counts and
   maxima, 9 rows). §7.2 says the procedure reads `COUNT(*)`/`MAX()` "on the `CONFORMED`
   table". The numbers are the same, but the app's owner role never gets `SELECT` on
   unmasked rows.
2. **Source rates use the `ROW_COUNT` DMF as the denominator**: `FORGE_ADMIN` has no
   `SELECT` on the source tables, and shouldn't get it. For E-codes whose §4 base is a
   subset (for example delivered shipments), the rate over all rows is slightly lower. It
   can never cause a false `WARN`.
3. **`NULL_COUNT` on `CONFORMED.SHIPMENT.promised_delivery_date` is `MAX_RATE`, not
   `ZERO`**: E01 rows stay visible by rule. The app's judgement changes to match.
4. **M03 per domain**: one DMF plus a reference table per domain. A DMF can't take a
   constant argument, and a view as the reference table is unverified.
5. **Warm-up schedule**: `5 MINUTE` for the gate, then `TRIGGER_ON_CHANGES`. Attaching
   before the load would re-run every DMF after each of the generator's ~40 chunked
   inserts.
6. **Freshness during the video**: with the fixed `END_DATE` `2026-09-30`, the data was
   loaded at 05:00 on 30 Sep. On 2 Oct that reads `WARN`, and later `FAIL`. §7.2 says
   this is true, not a bug. The agent will say so if asked. Raised for the user and CoCo;
   no change unless they want one.

## To verify live (CoCo, in the B12 run report)

- `argument_names` format in `DATA_QUALITY_MONITORING_RESULTS`: matching tolerates both
  plain strings and objects.
- Whether dynamic tables take `ALTER TABLE … ADD DATA METRIC FUNCTION` and
  `TRIGGER_ON_CHANGES`; the procedure falls back either way and reports which path it used.
- The error text for an association that already exists (it's classified `EXISTS` on
  `%already%`).
- Whether an `ARRAY` column (`dq_flags`) is accepted as a DMF argument.
- Whether owner's-rights `SP_DATA_HEALTH` sees `DATA_QUALITY_MONITORING_RESULTS` through
  `FORGE_ADMIN`'s application role.
- For B13: whether a clone keeps the DMF associations. If it does, call
  `SP_ATTACH_DMFS(<clone>, '')` before generating.

## Steps

1. Write the 6 SQL files and the README, following the design above.
2. Make the app fix and write the offline tests; `pytest -q` and `pytest -m ui` green.
3. Hand over: a row in the HANDOFF "Ready for CoCo to run" table, with the run order,
   roles and expected results; post the decisions and the to-verify list in "Latest from
   Claude Code".

## Gate (from CoCo's run report `docs/artifacts/runs/C10_run.md`)

- Every statement runs; `SP_ATTACH_DMFS` reports no `ERROR` rows.
- Results appear for every association.
- **`SOURCE` shows the injected defects** (§4 rates within tolerance), and **`CONFORMED`
  shows none of the repairable ones** (every `ZERO` check is 0).
- `SP_DATA_HEALTH` returns the §7.2 shape for all 9 entities and `ALL` (≤ 16 KB), `ERROR`
  for an unknown entity, and the same result when called as a persona role.
- `OPS.SP_DQ_SELF_CHECKS` returns every row `PASSED` (or `NULL` where it only reports).

## On completion

1. This card
2. `.agents/NEXT.md` (C10 row)
3. `.agents/HANDOFF.md` ("Latest from Claude Code" + the "Ready for CoCo to run" row)
4. `docs/SESSION_LOG.md`
5. `.agents/tasks/README.md` "Written:" list
