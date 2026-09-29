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
