-- ============================================================================
-- tests/scale/00_setup.sql — grants for the scale harness (C12)
-- Card:       C12 (.agents/tasks/claude/C12_scale_harness.md)
-- Spec:       docs/DATA_SPEC.md §7.4, §8 (tests/scale runs as FORGE_ADMIN)
-- Role:       ACCOUNTADMIN        Warehouse: FORGE_WH
-- Run order:  1 of 4 (00 → 10 → 20 → 99). Re-runnable: IF NOT EXISTS and idempotent grants.
-- Expected:   every statement succeeds. FORGE_ADMIN can then create the catalogue, the
--             results table and the procedure in OPS (files 10 and 20).
-- Not here:   the clone, its data and its warehouse are B13's (CoCo). Grants inside the
--             clone follow the clone (to verify at B13).
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS
  COMMENT = 'Private operations schema: data generator, data quality, evaluation, scale harness (FORGE_ADMIN only)';

GRANT USAGE ON SCHEMA SUPPLY_CHAIN_FORGE.OPS TO ROLE FORGE_ADMIN;
GRANT CREATE TABLE ON SCHEMA SUPPLY_CHAIN_FORGE.OPS TO ROLE FORGE_ADMIN;
GRANT CREATE PROCEDURE ON SCHEMA SUPPLY_CHAIN_FORGE.OPS TO ROLE FORGE_ADMIN;
