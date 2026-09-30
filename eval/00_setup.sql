-- ============================================================================
-- eval/00_setup.sql — grants for the evaluation set (C11)
-- Card:       C11 (.agents/tasks/claude/C11_eval_set.md)
-- Spec:       docs/DATA_SPEC.md §7.3, §8 (eval/ runs as FORGE_ADMIN)
-- Role:       ACCOUNTADMIN        Warehouse: FORGE_WH
-- Run order:  1 of 5 (00 → 10 → 20 → 30 → 99). Re-runnable: IF NOT EXISTS and idempotent
--             grants.
-- Expected:   every statement succeeds. FORGE_ADMIN can then create the evaluation tables
--             and procedures in OPS (files 10–30) and call the agent.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS
  COMMENT = 'Private operations schema: data generator, data quality, evaluation, scale harness (FORGE_ADMIN only)';

-- Files 10–30 run as FORGE_ADMIN and create their objects in OPS.
GRANT USAGE ON SCHEMA SUPPLY_CHAIN_FORGE.OPS TO ROLE FORGE_ADMIN;
GRANT CREATE TABLE ON SCHEMA SUPPLY_CHAIN_FORGE.OPS TO ROLE FORGE_ADMIN;
GRANT CREATE PROCEDURE ON SCHEMA SUPPLY_CHAIN_FORGE.OPS TO ROLE FORGE_ADMIN;

-- DATA_AGENT_RUN needs Cortex access (the app already calls the agent as FORGE_ADMIN).
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE FORGE_ADMIN;

-- Optional, only for Snowflake's native agent evaluation (99_run.sql, step 5
-- docs/references/agent_evaluations.md §8). Run these only if CoCo takes that step:
-- GRANT CREATE DATASET ON SCHEMA SUPPLY_CHAIN_FORGE.OPS TO ROLE FORGE_ADMIN
-- GRANT CREATE STAGE ON SCHEMA SUPPLY_CHAIN_FORGE.OPS TO ROLE FORGE_ADMIN
-- GRANT CREATE FILE FORMAT ON SCHEMA SUPPLY_CHAIN_FORGE.OPS TO ROLE FORGE_ADMIN
-- GRANT CREATE TASK ON SCHEMA SUPPLY_CHAIN_FORGE.OPS TO ROLE FORGE_ADMIN
-- GRANT EXECUTE TASK ON ACCOUNT TO ROLE FORGE_ADMIN
