-- ============================================================================
-- data_gen/99_run.sql — the calls CoCo runs (one statement per call)
-- Card:       C08 (.agents/tasks/claude/C08_data_generator.md)
-- Role:       ACCOUNTADMIN        Warehouse: FORGE_WH (XS). B13 uses a larger warehouse and
--             TARGET_DB = the clone.
-- Run order:  5 of 5, after 00_setup.sql, 10_sp_generate_data.sql, 20_sp_inject_mess.sql,
--             30_sp_gen_self_checks.sql, and after CoCo's v2 source DDL (B08c).
-- Parameters: TARGET_DB 'SUPPLY_CHAIN_FORGE' · SEED 20260929 · END_DATE '2026-09-30'
--             · SCALE_FACTOR 0.01 (dry run), then 1 (main).
--             END_DATE is a fixed date, not CURRENT_DATE(): the new event account must load
--             byte-identical data (account switch, 1 Oct), so use the SAME END_DATE there.
-- Expected:   see each step. Every SP_GEN_SELF_CHECKS row PASSED = TRUE or NULL.
-- NOTE:       step 1 truncates and reloads the 10 source tables of TARGET_DB.
-- ============================================================================

-- ── Step 1. Dry run at SF 0.01, twice (determinism + errors inside procedure bodies) ──
-- Expected each: {"status": "OK", "rows": {"VBAK": 6500, ...}}, well under a minute.
CALL SUPPLY_CHAIN_FORGE.OPS.SP_GENERATE_DATA('SUPPLY_CHAIN_FORGE', 0.01, 20260929, '2026-09-30'::DATE);
CALL SUPPLY_CHAIN_FORGE.OPS.SP_GENERATE_DATA('SUPPLY_CHAIN_FORGE', 0.01, 20260929, '2026-09-30'::DATE);

-- Expected: {"status": "OK", "injected": {"M01": {...}, ..., "E12": {...}}}
CALL SUPPLY_CHAIN_FORGE.OPS.SP_INJECT_MESS('SUPPLY_CHAIN_FORGE', 20260929, '2026-09-30'::DATE);

-- Expected: CHECKSUM_REPEAT rows PASSED = TRUE (same data twice); ROWS_CLEAN within tolerance.
-- At SF 0.01 the CLEAN_*_YEAR_* metric rows can miss (few orders per year); judge those at SF 1.
CALL SUPPLY_CHAIN_FORGE.OPS.SP_GEN_SELF_CHECKS('SUPPLY_CHAIN_FORGE');

-- ── Step 2. Main load at SF 1 ────────────────────────────────────────────────
-- Expected: {"status": "OK", "rows": {"T001W": 12, "LFA1": 150, "MARA": 1200, "KNA1": 2000,
--   "TCURR": ~23300, "SOURCING": ~2400, "VBAK": 650000 (±1%), "VBAP": ~2.0M, "VTTK": ~0.72M,
--   "MARD": ~2.2M}}, in under ~20 min on XS (budget: ≤ 15 min per call).
CALL SUPPLY_CHAIN_FORGE.OPS.SP_GENERATE_DATA('SUPPLY_CHAIN_FORGE', 1, 20260929, '2026-09-30'::DATE);

-- Expected: {"status": "OK", "injected": {...}}, a few minutes.
CALL SUPPLY_CHAIN_FORGE.OPS.SP_INJECT_MESS('SUPPLY_CHAIN_FORGE', 20260929, '2026-09-30'::DATE);

-- Expected: every row PASSED = TRUE or NULL (NULL = report-only, or no earlier SF 1 run to
-- compare checksums with).
CALL SUPPLY_CHAIN_FORGE.OPS.SP_GEN_SELF_CHECKS('SUPPLY_CHAIN_FORGE');

-- ── While a call runs: follow it from another session ──────────────────────────
-- SELECT STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT, PARAMS
-- FROM SUPPLY_CHAIN_FORGE.OPS.GEN_LOG ORDER BY STARTED_AT DESC LIMIT 30;

-- ============================================================================
-- Step 3 (C17 part B): the nightly day-append, OPS.SP_APPEND_DAY (40_sp_append_day.sql)
-- Role ACCOUNTADMIN, FORGE_WH. Create the procedure first: run 40_sp_append_day.sql.
-- First on a scratch clone (CoCo's rule: a cloned CONFORMED still reads the original, so
-- judge the clone on its SOURCE tables only), then on SUPPLY_CHAIN_FORGE, then the task.
-- ============================================================================

-- 3a. Clone: one day. Expected: {"status": "OK", "from_end_date": "2026-09-30",
--     "new_end_date": "2026-10-01", "days_added": 1, "rows": {"VBAK new": ~330, "VBAK versions":
--     ~300-700, "VBAP new": ~950, "VBAP versions": ~900, "VTTK new": ~300-350, "VTTK versions":
--     ~300-450, "MARD": 3600, "TCURR": 9}, "max_load_ts": "2026-10-01 0x:xx"}, seconds.
-- CREATE DATABASE SUPPLY_CHAIN_FORGE_C17B CLONE SUPPLY_CHAIN_FORGE;
CALL SUPPLY_CHAIN_FORGE.OPS.SP_APPEND_DAY('SUPPLY_CHAIN_FORGE_C17B', 1, 20260929, '2026-10-01'::DATE);

-- 3b. The same day again: idempotent. Expected: "days_added": 0, nothing written.
CALL SUPPLY_CHAIN_FORGE.OPS.SP_APPEND_DAY('SUPPLY_CHAIN_FORGE_C17B', 1, 20260929, '2026-10-01'::DATE);

-- 3c. Three missed nights at once (catch-up). Expected: "from_end_date": "2026-10-01",
--     "days_added": 3 (business dates 1-3 Oct: Thu, Fri, Sat; Saturday's orders ~1/3 of a weekday).
CALL SUPPLY_CHAIN_FORGE.OPS.SP_APPEND_DAY('SUPPLY_CHAIN_FORGE_C17B', 1, 20260929, '2026-10-04'::DATE);

-- 3d. Checks on the clone's source tables (each: the expected result in the comment).
-- New orders per business date: one row per day 2026-09-30 .. 2026-10-03, counts as above;
-- every new order exactly once among its versions' first row.
SELECT AUDAT, COUNT(DISTINCT UPPER(TRIM(VBELN))) AS orders
FROM SUPPLY_CHAIN_FORGE_C17B.ERP_SOURCE.VBAK WHERE AUDAT >= '2026-09-28' GROUP BY AUDAT ORDER BY AUDAT;
-- Nothing loaded after the cap: max LOAD_TS of each table <= 2026-10-04 05:00:00.
SELECT 'VBAK' t, MAX(LOAD_TS) FROM SUPPLY_CHAIN_FORGE_C17B.ERP_SOURCE.VBAK UNION ALL
SELECT 'VBAP', MAX(LOAD_TS) FROM SUPPLY_CHAIN_FORGE_C17B.ERP_SOURCE.VBAP UNION ALL
SELECT 'VTTK', MAX(LOAD_TS) FROM SUPPLY_CHAIN_FORGE_C17B.TMS_SOURCE.VTTK UNION ALL
SELECT 'MARD', MAX(LOAD_TS) FROM SUPPLY_CHAIN_FORGE_C17B.WMS_SOURCE.MARD UNION ALL
SELECT 'TCURR', MAX(LOAD_TS) FROM SUPPLY_CHAIN_FORGE_C17B.ERP_SOURCE.TCURR;
-- The latest version of each order: no OPEN order whose ship date has passed (dptbg <= L means
-- it shipped). Expected: SHIPPED and DELIVERED both grow day by day; 0 rows of the second query.
SELECT LOAD_TS::DATE AS loaded, GBSTK, COUNT(*) FROM SUPPLY_CHAIN_FORGE_C17B.ERP_SOURCE.VBAK
WHERE LOAD_TS >= '2026-10-01' GROUP BY 1, 2 ORDER BY 1, 2;
SELECT VBELN FROM SUPPLY_CHAIN_FORGE_C17B.ERP_SOURCE.VBAK
QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(VBELN)) ORDER BY LOAD_TS DESC) = 1
   AND GBSTK = 'OPEN' AND AUDAT < '2026-09-25' AND AUART = 'OR' LIMIT 10;
-- Shipments: per day, new (DPTBG = the day) vs delivered (ACT_DLV_DT = the day). Expected:
-- both ~300-350 on weekdays, each TKNUM's latest version unique.
SELECT DPTBG AS day, COUNT(DISTINCT TKNUM) AS shipped FROM SUPPLY_CHAIN_FORGE_C17B.TMS_SOURCE.VTTK
WHERE DPTBG >= '2026-09-30' GROUP BY 1 ORDER BY 1;
SELECT ACT_DLV_DT AS day, COUNT(DISTINCT TKNUM) AS delivered FROM SUPPLY_CHAIN_FORGE_C17B.TMS_SOURCE.VTTK
WHERE ACT_DLV_DT >= '2026-09-30' GROUP BY 1 ORDER BY 1;
-- The generator's self-checks still pass (row counts stay within ±1% for a few weeks of days).
CALL SUPPLY_CHAIN_FORGE.OPS.SP_GEN_SELF_CHECKS('SUPPLY_CHAIN_FORGE_C17B');
-- DROP DATABASE SUPPLY_CHAIN_FORGE_C17B;

-- 3e. Production: catch up to today (UTC). Expected: days_added = days since 2026-09-30.
--     CONFORMED refreshes incrementally; DMFs run on change. The next morning
--     SP_DATA_HEALTH('ALL') reads OK for orders, order_lines, shipments, inventory.
CALL SUPPLY_CHAIN_FORGE.OPS.SP_APPEND_DAY('SUPPLY_CHAIN_FORGE', 1, 20260929,
     CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP())::DATE);

-- 3f. The nightly task is CoCo's (sql/, DATA_SPEC §7.1a): serverless, 05:30 UTC, calling the
--     line above (the UTC date passed in, never CURRENT_DATE() inside the procedure).
