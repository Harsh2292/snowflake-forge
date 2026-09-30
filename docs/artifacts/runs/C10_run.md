# C10 run report — data quality: DMFs + `SP_DATA_HEALTH` (run by CoCo at B12)

| | |
|---|---|
| **Date** | 2026-09-30 (09:44–10:24 UTC) |
| **Account** | `tyduokn-gf25237` (DA53081, AZURE_CENTRALINDIA, Enterprise) |
| **Role / warehouse** | per file header: `00`, `10`, `20`, `40` and attach steps as `ACCOUNTADMIN`; `30`, `SP_DATA_HEALTH` and `SP_DQ_SELF_CHECKS` as `FORGE_ADMIN`; `FORGE_WH` (XS) throughout |
| **Parameters** | `TARGET_DB 'SUPPLY_CHAIN_FORGE'`; warm-up `'5 MINUTE'`, steady `'TRIGGER_ON_CHANGES'` |
| **Data** | B08c (C08 SF 1 + mess, `CONFORMED` dynamic tables) |
| **Method** | every top-level statement as its own call, with `USE ROLE …; USE WAREHOUSE FORGE_WH;` prefixed |
| **Status** | **DONE**: one small run-blocking fix (below). Self-checks 90/91; the one FALSE doesn't block (below) |
| **Artifact** | `docs/artifacts/10_dmf_results.json` |

## Fix CoCo applied (run-blocking, `00_setup.sql`, 10 catalogue rows + 1 comment line)

Step 1's first call returned 98 rows: 21 SET SCHEDULE OK, 67 ADD DMF ADDED, **10 ERROR**, every
one a `SNOWFLAKE.CORE.FRESHNESS` row. Verbatim:

```
SUPPLY_CHAIN_FORGE.CONFORMED.INVENTORY  SNOWFLAKE.CORE.FRESHNESS  load_ts |
SQL compilation error: Function 'FRESHNESS$V1' does not exist or not authorized.
(same for CONFORMED.ORDER_LINE, SALES_ORDER, SHIPMENT; ERP_SOURCE.TCURR, VBAK, VBAP; TMS_SOURCE.VTTK; WMS_SOURCE.MARD)
SUPPLY_CHAIN_FORGE.CONFORMED.FX_RATE  SNOWFLAKE.CORE.FRESHNESS  load_ts |
SQL compilation error: column 'LOAD_TS' does not exist
```

Cause: `SHOW FUNCTIONS LIKE 'FRESHNESS' IN SCHEMA SNOWFLAKE.CORE` lists four signatures:
`FRESHNESS()`, `FRESHNESS(TABLE(DATE))`, `FRESHNESS(TABLE(TIMESTAMP_LTZ))` and
`FRESHNESS(TABLE(TIMESTAMP_TZ))`. **There is no `TIMESTAMP_NTZ` form**, and every `LOAD_TS` is
`TIMESTAMP_NTZ` (DATA_SPEC §1). `CONFORMED.FX_RATE` has no `load_ts` at all (columns
`CURRENCY`, `USD_RATE`, `RATE_DATE`).

Fix: the no-argument form, `ON ()` = *"seconds between the last update of the table and the
scheduled run"*. Tested first on a dynamic table (`FX_RATE`) and a source table (`TCURR`);
both attached. In the catalogue `COLUMNS NULL` already means `ON ()`, and
`SP_DQ_SELF_CHECKS` matches FRESHNESS results by table and metric name only, so nothing else
changes. `SP_DATA_HEALTH` computes `freshness_hours` from `MAX(load_ts)` in
`V_CONFORMED_FACTS`, not from this DMF, so it is unaffected.

```diff
-    -- FRESHNESS on the load timestamp of the transactional tables (seconds since MAX(load_ts))
-    ('S_VBAK_FRESH',  95, 'orders', 'freshness', NULL, 'SOURCE', 'ERP_SOURCE', 'VBAK',  'SNOWFLAKE.CORE.FRESHNESS', 'LOAD_TS', NULL, NULL, 'FRESHNESS', NULL, NULL, NULL),
+    -- FRESHNESS of the transactional tables: ON () = seconds since the table last changed
+    -- (FRESHNESS has no TIMESTAMP_NTZ signature, and LOAD_TS is NTZ; B12 run fix)
+    ('S_VBAK_FRESH',  95, 'orders', 'freshness', NULL, 'SOURCE', 'ERP_SOURCE', 'VBAK',  'SNOWFLAKE.CORE.FRESHNESS', NULL, NULL, NULL, 'FRESHNESS', NULL, NULL, NULL),
 (the same 'LOAD_TS' / 'load_ts' → NULL change on the other 9 *_FRESH rows:
  S_VBAP, S_VTTK, S_MARD, S_TCURR, C_SALES_ORDER, C_ORDER_LINE, C_SHIPMENT, C_INVENTORY, C_FX_RATE)
```

**For Claude Code:** if you want freshness on the load timestamp rather than on the table's
last change, add a `LOAD_TS_LTZ` column or a custom DMF that takes `TIMESTAMP_NTZ`. `ON ()` is
enough for the Data health screen. The self-check detail string
("seconds since the latest load timestamp") now describes the table's last change.

## Outcome by file

| File | Statements | Outcome |
|---|---|---|
| `00_setup.sql` | 33 | all OK; `DQ_CHECKS` 77 rows; the 7 `DQ_VALID_*` hold 3, 4, 3, 3, 9, 6, 3 codes; `V_CONFORMED_FACTS` created; `DATA_QUALITY_MONITORING_VIEWER`, `EXECUTE DATA METRIC FUNCTION` and `DATA_METRIC_USER` granted. After the fix: `DQ_CHECKS` re-created + 77 rows, the view and its 2 grants re-run |
| `10_custom_dmfs.sql` | 7 | 7 × "Function DMF_… successfully created" |
| `20_sp_attach_dmfs.sql` | 1 | `SP_ATTACH_DMFS` created |
| `30_sp_data_health.sql` | 4 | `SP_DATA_HEALTH` created (FORGE_ADMIN); USAGE to the 3 personas |
| `40_sp_dq_self_checks.sql` | 2 | `SP_DQ_SELF_CHECKS` created; USAGE to FORGE_ADMIN |

## `99_run.sql`

| Step | Call | Time | Result |
|---|---|---|---|
| 1 | `SP_ATTACH_DMFS(…, '5 MINUTE')` | 26 s | first call: 10 ERROR (above); **after the fix: 98 rows, 21 SET SCHEDULE OK, 77 ADD DMF ADDED, 0 ERROR** (the 67 existing associations also report ADDED, not EXISTS, on a re-run) |
| 2 | `SP_DATA_HEALTH('shipments')` | 4 s | the §7.2 shape; 11 checks, all `UNKNOWN` before the first DMF result; freshness already from `CONFORMED` |
| 3 | `SP_DQ_SELF_CHECKS` (~30 min after step 1) | ~40 s | **91 rows: 90 TRUE, 1 FALSE** (below) |
| 4 | `SP_ATTACH_DMFS(…, 'TRIGGER_ON_CHANGES')` | 31 s | 98 rows: **21 SET SCHEDULE OK (no CRON fallback needed)**, 77 ADD DMF ADDED, 0 ERROR |
| 5 | `SP_DATA_HEALTH('ALL')` as FORGE_ADMIN, PLANNER_ROLE, BUYER_ROLE, LOGISTICS_ROLE | ~3 s each | 2,608 bytes, **identical for all four roles** apart from `generated_at`; `as_of_date` 2026-09-29 |

DMF results landed in `SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS` for **all 77
associations** (CONFORMED 40, ERP 17, SRM 7, TMS 7, WMS 6), first result 09:50 UTC.

### Self-checks: the one FALSE (non-blocking)

`DQ_S_VBAP_E04` (over-shipped lines in `ERP_SOURCE.VBAP`): measured **19,390**, injected
19,589. The rule is `VALUE >= INJECTED AND VALUE <= INJECTED * 1.25 + 5`. The value is 1% under
the injected count; the rate is 0.93%, inside the DATA_SPEC §4 band. Most likely a later
injection (M01 duplicates or E09a orphans) changed some of those lines, as with C08's
`DATA_NON_CONTRACT_CODES`. Suggestion: allow a small undercount (`VALUE >= INJECTED * 0.95`).
It's not a data defect.

Everything else is TRUE:
- every `CONFORMED` ZERO check is 0
- `CONFORMED.SHIPMENT` E01 0.80% and E08 0.10% are under their thresholds (excluded by rule,
  not repaired)
- SOURCE E01, E05, E09a and E09b are inside `[injected, 1.25 × injected + 5]`
- all 31 VOLUME/FRESHNESS associations have results
- the `HEALTH_*` rows: shape 9/9, `ALL` 2,436 bytes ≤ 16 KB, `ERROR` for an unknown entity,
  no FAIL check

### Finding for Claude Code: `ALL` reads FAIL because of master-data freshness

`SP_DATA_HEALTH('ALL')` → `status FAIL`, *"4 of 9 entities OK; suppliers FAIL, parts FAIL,
sourcing FAIL, plants FAIL, customers FAIL"*. **No check fails.** It's freshness only:

| Entity | latest_load_ts | freshness_hours |
|---|---|---|
| parts, plants | 2016-10-01 | ~87,600 |
| suppliers, sourcing | 2025-12-05 | ~7,180 |
| customers | 2026-08-30 | ~750 |
| inventory, orders, order_lines, shipments | 2026-09-30 05:00 | 5.4 → OK |

The 36/72 h rule suits transactional tables. Master data changes rarely by nature (C08 loads
it once), so it will always read FAIL, and the agent's `data_health` tool reports this to users.
Suggestion: apply freshness only to the transactional entities (or give master data a
separate, longer threshold), so `ALL` reads OK on current data. That's your call (C10); no
CR needed.

## Verdict

**DONE.** The file is Claude Code's again. Please adopt the `00_setup.sql` diff (already in
the file) and consider the two suggestions above.
