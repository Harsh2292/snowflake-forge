# `quality/`: data-quality checks and the data-health tool (C10)

Snowflake measures both data layers every time the data changes, and one procedure turns
those measurements into a short, governed answer: how fresh an entity is, the as-of date,
and which checks pass. The agent calls it as a custom tool (B10), and the app reads it for
the as-of date and the Data health screen.

Written by Claude Code; run by CoCo at **B12** (handoff lock). Card:
`.agents/tasks/claude/C10_data_quality.md`. Spec: `docs/DATA_SPEC.md` §7.2 and §4.

## Files, in run order

| File | Role | What it creates |
|---|---|---|
| `00_setup.sql` | `ACCOUNTADMIN` | `OPS.DQ_CHECKS` (the check catalogue), `OPS.DQ_VALID_<DOMAIN>` (contract codes), `OPS.V_CONFORMED_FACTS` (aggregates only), grants |
| `10_custom_dmfs.sql` | `ACCOUNTADMIN` | 7 custom DMFs in `OPS` (`CREATE OR ALTER`) |
| `20_sp_attach_dmfs.sql` | `ACCOUNTADMIN` | `OPS.SP_ATTACH_DMFS(TARGET_DB, SCHEDULE)` |
| `30_sp_data_health.sql` | `FORGE_ADMIN` | `SEMANTIC.SP_DATA_HEALTH(ENTITY)`, owner's rights, `USAGE` to the 3 persona roles |
| `40_sp_dq_self_checks.sql` | `ACCOUNTADMIN` (called as `FORGE_ADMIN`) | `OPS.SP_DQ_SELF_CHECKS(TARGET_DB)`, the gate |
| `99_run.sql` | per step | the calls: attach (warm-up) → health → self-checks → steady schedule → art 10 |

## How it fits together

```
OPS.DQ_CHECKS (77 rows: 46 checks + 21 ROW_COUNT + 10 FRESHNESS)
   ├─ SP_ATTACH_DMFS ──► ALTER TABLE … ADD DATA METRIC FUNCTION   (SOURCE and CONFORMED)
   │                         │  serverless, on the table's schedule
   │                         ▼
   │              SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS ◄── the app's Data health table
   ├─ SP_DATA_HEALTH ──► latest result per check + OPS.V_CONFORMED_FACTS ──► §7.2 JSON
   └─ SP_DQ_SELF_CHECKS ──► SP_DATA_HEALTH for every entity + OPS.GEN_MESS_LOG (C08) ──► gate
```

**How each layer is judged** (the `EXPECT` column of the catalogue):

| Check (code) | `SOURCE` (raw) | `CONFORMED` (cleaned) |
|---|---|---|
| duplicate keys (M01/M02), non-contract codes (M03), test records (M04) | `INFO`: expected, always OK | `ZERO`: FAIL unless 0 |
| missing promised date (E01) | `MAX_RATE` 1.6% | `MAX_RATE` 1.6% (the row stays visible by rule) |
| over-shipment (E04), negative on-hand (E05), orphans (E09a/b) | `MAX_RATE` 2% / 0.6% / 0.4% | `ZERO` (capped, zeroed, dropped) |
| cost outliers (E08) | — (needs FX) | `MAX_RATE` 0.2% (flag `COST_OUTLIER`) |

A rate is `value ÷ ROW_COUNT` of the same table, both taken from the DMF results.

## Custom DMFs

| DMF | Arguments | Counts |
|---|---|---|
| `DMF_OVERSHIP_COUNT` | ordered, shipped | shipped > ordered |
| `DMF_NEGATIVE_ON_HAND_COUNT` | on hand | < 0 |
| `DMF_TEST_RECORD_COUNT` | id, name | the §4 M04 rule |
| `DMF_NONCONTRACT_CODE_COUNT` | code, `TABLE(OPS.DQ_VALID_<DOMAIN>(CODE))` | codes outside the domain's contract values |
| `DMF_ORPHAN_ORDER_LINES` / `DMF_ORPHAN_SHIPMENTS` | order id, `TABLE(<orders>(<key>))` | no matching order, on `UPPER(TRIM())` |
| `DMF_COST_OUTLIER_COUNT` | `dq_flags` | rows flagged `COST_OUTLIER` |

## Privileges (least privilege)

- `SP_DATA_HEALTH` runs as `FORGE_ADMIN`. It reads only:
  - the DMF results, through the `DATA_QUALITY_MONITORING_VIEWER` application role
  - `OPS.V_CONFORMED_FACTS`, 9 aggregate rows
  - `OPS.DQ_CHECKS`

  `FORGE_ADMIN` gets no `SELECT` on the source tables or on `CONFORMED`.
- Scheduled DMFs run as the table owner. `00` grants `EXECUTE DATA METRIC FUNCTION` and
  `SNOWFLAKE.DATA_METRIC_USER` to `ACCOUNTADMIN` and `FORGE_ADMIN`.

## To verify live (CoCo, in `docs/artifacts/runs/C10_run.md`)

1. The format of `argument_names` in `DATA_QUALITY_MONITORING_RESULTS`: the matching accepts
   plain strings or objects that contain the column name.
2. Whether dynamic tables take `ALTER TABLE … ADD DATA METRIC FUNCTION` and
   `TRIGGER_ON_CHANGES`. `SP_ATTACH_DMFS` falls back to `ALTER DYNAMIC TABLE` and to CRON,
   and says which path it took.
3. The error text for an association that already exists; it's classified `EXISTS` when it
   contains "already".
4. Whether an `ARRAY` column (`dq_flags`) is accepted as a DMF argument.
5. Whether owner's-rights `SP_DATA_HEALTH` sees all results through `FORGE_ADMIN`'s
   application role, including those on source tables it can't `SELECT`.
6. Whether `CREATE OR ALTER DATA METRIC FUNCTION` is accepted. If not, use
   `CREATE DATA METRIC FUNCTION IF NOT EXISTS`, which is a run-blocking fix of one word per
   function.
7. The owner of the `CONFORMED` dynamic tables. Attaching needs that owner's rights (or
   `ACCOUNTADMIN` above it).
8. For B13: whether a clone keeps the DMF associations. If it does, call
   `SP_ATTACH_DMFS('<clone>', '')` before generating data there.

## Freshness on static demo data

`LOAD_TS` stops at `END_DATE` 05:00 (`2026-09-30`), so freshness reads `WARN` after 36 h and
`FAIL` after 72 h. That's true, not a bug (§7.2). Reload closer to the recording day if it
should read `OK` on camera.
