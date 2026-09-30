-- ============================================================================
-- quality/99_run.sql — the calls CoCo runs at B12 (one statement per call)
-- Card:       C10 (.agents/tasks/claude/C10_data_quality.md)
-- Role:       as noted per step (ACCOUNTADMIN attaches, FORGE_ADMIN owns and checks)
-- Warehouse:  FORGE_WH
-- Run order:  6 of 6, after 00_setup.sql (ACCOUNTADMIN), 10_custom_dmfs.sql (ACCOUNTADMIN),
--             20_sp_attach_dmfs.sql (ACCOUNTADMIN), 30_sp_data_health.sql (FORGE_ADMIN),
--             40_sp_dq_self_checks.sql (ACCOUNTADMIN). All of them after B08c: the v2
--             source tables loaded by C08 (with the mess injected) and the CONFORMED tables.
-- Parameters: TARGET_DB 'SUPPLY_CHAIN_FORGE'. Warm-up schedule '5 MINUTE', then the steady
--             schedule 'TRIGGER_ON_CHANGES' (CRON fallback where refused).
-- Expected:   see each step. Gate: every SP_DQ_SELF_CHECKS row PASSED = TRUE.
-- Cost:       ~77 associations, serverless. The warm-up runs them every 5 minutes, so step 4
--             should follow soon after step 3 passes. After that they run only when a
--             table changes (TRIGGER_ON_CHANGES) or daily at 06:00 UTC (the fallback).
-- ============================================================================

-- ── Step 1 (ACCOUNTADMIN). Attach everything with the warm-up schedule ──────────
-- The data is already loaded, so TRIGGER_ON_CHANGES would not produce a first result.
-- Expected: 98 rows, 21 SET SCHEDULE rows OK (dynamic tables may show the ALTER DYNAMIC TABLE
-- path in DETAIL), 77 ADD DMF rows ADDED. No ERROR rows. Re-running shows EXISTS instead.
CALL SUPPLY_CHAIN_FORGE.OPS.SP_ATTACH_DMFS('SUPPLY_CHAIN_FORGE', '5 MINUTE');

-- ── Step 2 (FORGE_ADMIN). The tool answers straight away, before any DMF result ──
-- Expected: the full §7.2 shape, checks UNKNOWN until the first results land, freshness
-- from the CONFORMED tables already.
CALL SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH('shipments');

-- ── Step 3 (FORGE_ADMIN). The gate, about 10–15 minutes after step 1 ─────────────
-- Expected: every row PASSED = TRUE. Rows with "no DMF result yet" mean the first scheduled
-- run hasn't finished: wait 5 minutes and call again.
CALL SUPPLY_CHAIN_FORGE.OPS.SP_DQ_SELF_CHECKS('SUPPLY_CHAIN_FORGE');

-- ── Step 4 (ACCOUNTADMIN). The steady schedule ──────────────────────────────────
-- Expected: 21 SET SCHEDULE rows OK or FALLBACK (FALLBACK = TRIGGER_ON_CHANGES refused, so
-- USING CRON 0 6 * * * UTC), 77 ADD DMF rows EXISTS. Takes effect within ~10 minutes.
CALL SUPPLY_CHAIN_FORGE.OPS.SP_ATTACH_DMFS('SUPPLY_CHAIN_FORGE', 'TRIGGER_ON_CHANGES');

-- ── Step 5. The artifact for the app and the agent (art 10) ─────────────────────
-- As FORGE_ADMIN, then once each as PLANNER_ROLE, BUYER_ROLE and LOGISTICS_ROLE: the same
-- answer apart from generated_at (owner's rights).
CALL SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH('ALL');

-- The raw DMF results, as the app's Data health screen reads them (forge_data.QUALITY_SQL):
-- SELECT table_schema, table_name, metric_name, argument_names, value, measurement_time
-- FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
-- WHERE table_database = 'SUPPLY_CHAIN_FORGE'
-- QUALIFY ROW_NUMBER() OVER (PARTITION BY reference_id ORDER BY measurement_time DESC) = 1
-- ORDER BY table_name, metric_name

-- ── For B13 (a clone) ─────────────────────────────────────────────────────────
-- If the clone keeps the DMF associations (to verify), suspend them before generating data
-- there, so the generator's chunked inserts don't trigger ~77 DMF runs each:
-- CALL SUPPLY_CHAIN_FORGE.OPS.SP_ATTACH_DMFS('<CLONE_DB>', '')
