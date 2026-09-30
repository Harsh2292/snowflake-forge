-- ============================================================================
-- tests/scale/99_run.sql — the calls CoCo runs at B13, and the art 12 queries
-- Card:       C12 (.agents/tasks/claude/C12_scale_harness.md)
-- Role:       FORGE_ADMIN for every step (00_setup.sql runs first, as ACCOUNTADMIN)
-- Warehouse:  per step: FORGE_WH (XS), then B13's temporary larger warehouse
-- Run order:  4 of 4, after 00 (ACCOUNTADMIN), 10 and 20 (FORGE_ADMIN), after B09, and for
--             steps 2–3 after B13 has built the clone SUPPLY_CHAIN_FORGE_SCALE (C08 at a large
--             scale factor, its CONFORMED refreshed, its semantic view, governed views and
--             SP_METRICS_AS_* regenerated inside the clone). Use B13's clone name if different.
-- Expected:   see each step. Gate: every query runs on the clone, SQL_HASH identical across
--             the three runs, persona fingerprints identical within each run, XS and larger
--             warehouse answers identical, timings, pruning and credits recorded.
-- Budget:     each CALL must stay under 15 minutes. If the clone on XS is slower, split with
--             the 4th argument, e.g. 'SV_ON_TIME%', 'SV_FILL%', 'SV_DAYS%', 'SV_AVG%', 'PROC%', 'NAIVE%'.
-- ============================================================================

-- ── Step 1. Baseline: the original database at SF 1, on XS (USE WAREHOUSE FORGE_WH) ──
-- Expected: {"queries": 70, "failed": 0} (1 until B15 grants the naive query's source tables).
CALL SUPPLY_CHAIN_FORGE.OPS.SP_SCALE_RUN('SUPPLY_CHAIN_FORGE', 'sf1-xs', 'SUPPLY_CHAIN_FORGE.OPS.SCALE_RESULTS');

-- ── Step 2. The clone, on XS (USE WAREHOUSE FORGE_WH) ─────────────────────────────
CALL SUPPLY_CHAIN_FORGE.OPS.SP_SCALE_RUN('SUPPLY_CHAIN_FORGE_SCALE', 'clone-xs', 'SUPPLY_CHAIN_FORGE.OPS.SCALE_RESULTS');

-- ── Step 3. The clone, on the larger warehouse (USE WAREHOUSE <B13 warehouse>) ────
CALL SUPPLY_CHAIN_FORGE.OPS.SP_SCALE_RUN('SUPPLY_CHAIN_FORGE_SCALE', 'clone-large', 'SUPPLY_CHAIN_FORGE.OPS.SCALE_RESULTS');

-- ── Art 12, claim 1: the same SQL at every scale ─────────────────────────────────
-- Expected: 0 rows (every query has one SQL_HASH across the three runs).
WITH latest AS (
    SELECT * FROM SUPPLY_CHAIN_FORGE.OPS.SCALE_RESULTS
    WHERE RUN_LABEL IN ('sf1-xs', 'clone-xs', 'clone-large')
    QUALIFY RUN_TS = MAX(RUN_TS) OVER (PARTITION BY RUN_LABEL))
SELECT QUERY_NAME, COUNT(DISTINCT SQL_HASH) AS SQL_SHAPES, COUNT(DISTINCT RUN_LABEL) AS RUNS
FROM latest
GROUP BY QUERY_NAME
HAVING COUNT(DISTINCT SQL_HASH) > 1 OR COUNT(DISTINCT RUN_LABEL) < 3;

-- ── Art 12, claim 2: the same numbers for every persona, at every scale ───────────
-- Expected: 3 rows, each PERSONA_FINGERPRINTS = 1 and PROCEDURES = 3.
WITH latest AS (
    SELECT * FROM SUPPLY_CHAIN_FORGE.OPS.SCALE_RESULTS
    WHERE RUN_LABEL IN ('sf1-xs', 'clone-xs', 'clone-large')
    QUALIFY RUN_TS = MAX(RUN_TS) OVER (PARTITION BY RUN_LABEL))
SELECT RUN_LABEL, COUNT(DISTINCT RESULT_HASH) AS PERSONA_FINGERPRINTS, COUNT(*) AS PROCEDURES
FROM latest
WHERE PATH = 'PROCEDURE'
GROUP BY RUN_LABEL
ORDER BY RUN_LABEL;

-- ── Art 12, claim 3: the warehouse size changes speed, never answers ─────────────
-- Expected: 0 rows (every fingerprinted query gives the same answer on XS and larger).
WITH latest AS (
    SELECT * FROM SUPPLY_CHAIN_FORGE.OPS.SCALE_RESULTS
    WHERE RUN_LABEL IN ('clone-xs', 'clone-large')
    QUALIFY RUN_TS = MAX(RUN_TS) OVER (PARTITION BY RUN_LABEL))
SELECT x.QUERY_NAME, x.RESULT_HASH AS XS_HASH, l.RESULT_HASH AS LARGE_HASH
FROM latest x JOIN latest l ON l.QUERY_NAME = x.QUERY_NAME AND l.RUN_LABEL = 'clone-large'
WHERE x.RUN_LABEL = 'clone-xs' AND x.RESULT_HASH IS DISTINCT FROM l.RESULT_HASH;

-- ── Art 12, timings and pruning by run and path ─────────────────────────────────
WITH latest AS (
    SELECT * FROM SUPPLY_CHAIN_FORGE.OPS.SCALE_RESULTS
    WHERE RUN_LABEL IN ('sf1-xs', 'clone-xs', 'clone-large')
    QUALIFY RUN_TS = MAX(RUN_TS) OVER (PARTITION BY RUN_LABEL))
SELECT RUN_LABEL, MAX(WAREHOUSE_SIZE) AS WAREHOUSE_SIZE, PATH, COUNT(*) AS QUERIES,
       COUNT_IF(ERROR IS NOT NULL) AS FAILED,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ELAPSED_MS)) AS P50_MS,
       MAX(ELAPSED_MS) AS MAX_MS,
       ROUND(SUM(BYTES_SCANNED) / POWER(1024, 3), 2) AS GB_SCANNED,
       SUM(PARTITIONS_SCANNED) AS PARTITIONS_SCANNED, SUM(PARTITIONS_TOTAL) AS PARTITIONS_TOTAL,
       ROUND(1 - SUM(PARTITIONS_SCANNED) / NULLIFZERO(SUM(PARTITIONS_TOTAL)), 3) AS PRUNED_SHARE
FROM latest
GROUP BY RUN_LABEL, PATH
ORDER BY RUN_LABEL, PATH;

-- ── Art 12, the slowest queries per run (where a knob would be turned) ───────────
WITH latest AS (
    SELECT * FROM SUPPLY_CHAIN_FORGE.OPS.SCALE_RESULTS
    WHERE RUN_LABEL IN ('sf1-xs', 'clone-xs', 'clone-large')
    QUALIFY RUN_TS = MAX(RUN_TS) OVER (PARTITION BY RUN_LABEL))
SELECT RUN_LABEL, QUERY_NAME, ELAPSED_MS, PARTITIONS_SCANNED, PARTITIONS_TOTAL, ERROR
FROM latest
QUALIFY ROW_NUMBER() OVER (PARTITION BY RUN_LABEL ORDER BY ELAPSED_MS DESC NULLS LAST) <= 5
ORDER BY RUN_LABEL, ELAPSED_MS DESC;

-- ── Art 12, data volume of the clone (rows per CONFORMED table) ──────────────────
SELECT TABLE_NAME, ROW_COUNT, ROUND(BYTES / POWER(1024, 3), 2) AS GB
FROM SUPPLY_CHAIN_FORGE_SCALE.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'CONFORMED'
ORDER BY ROW_COUNT DESC;

-- ── Art 12, dynamic-table refresh times in the clone ────────────────────────────
SELECT NAME, REFRESH_ACTION, STATE, DATEDIFF(second, REFRESH_START_TIME, REFRESH_END_TIME) AS SECONDS
FROM TABLE(SUPPLY_CHAIN_FORGE_SCALE.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY())
ORDER BY REFRESH_START_TIME DESC
LIMIT 50;

-- ── Art 12, credits per warehouse during the B13 window (fill in the window) ─────
SELECT WAREHOUSE_NAME, ROUND(SUM(CREDITS_USED), 3) AS CREDITS
FROM TABLE(SUPPLY_CHAIN_FORGE.INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
       DATE_RANGE_START => DATEADD(hour, -6, CURRENT_TIMESTAMP())))
GROUP BY WAREHOUSE_NAME
ORDER BY CREDITS DESC;
