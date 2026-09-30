-- ============================================================
-- 02_cost_controls.sql — hard caps for the public link
-- Task: B15a / B15 (ADR-009; deploy/RUNBOOK.md step 2 and step 6). Limits chosen by the
-- user on 2026-09-30.
-- Owner: CoCo
-- Run as: ACCOUNTADMIN (FORGE_ADMIN creates the stop procedure), after 01_app_service_user.sql
-- Re-runnable: CREATE OR REPLACE / IF NOT EXISTS; the budget methods overwrite their settings.
-- ============================================================
-- Three layers, cheapest first:
--   1. The app: Ask capped at 10 questions per visitor and 200 a day (C15).
--   2. FORGE_WH resource monitor: 5 credits a day. The app's queries AND the agent's SQL run on
--      FORGE_WH (the agent's tool_resources name it). Our busiest build day used 1.3.
--      Resource monitors cover warehouses only, not AI services (Snowflake docs).
--   3. Cortex budget: 25 credits a month of agent use by FORGE_APP_SVC only (a user tag, so our
--      own build and evaluation work isn't counted). At 100% (actual), Snowflake calls
--      OPS.SP_STOP_PUBLIC_ASK, which revokes the app role's USAGE on the agent: Ask stops,
--      every other screen keeps working. Measured at B10: ~0.04 credits per agent question,
--      so 25 credits is ~600 questions (~3 days at the app's 200/day cap).
--      Budget figures lag by up to ~6.5 hours (default refresh tier).
-- To restore Ask after a stop: re-run 01_app_service_user.sql (it re-grants USAGE on the agent).
-- ============================================================

USE ROLE ACCOUNTADMIN;

-- ── 2. Warehouse cap ─────────────────────────────────────────
CREATE OR REPLACE RESOURCE MONITOR FORGE_WH_MONITOR WITH
  CREDIT_QUOTA = 5
  FREQUENCY = DAILY
  START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 75 PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND
           ON 110 PERCENT DO SUSPEND_IMMEDIATE;
ALTER WAREHOUSE FORGE_WH SET RESOURCE_MONITOR = FORGE_WH_MONITOR;

-- ── 3. Cortex budget ─────────────────────────────────────────
-- The user tag that scopes the budget to the app's service user.
CREATE TAG IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS.COST_SCOPE
  ALLOWED_VALUES 'public_app'
  COMMENT = 'B15a: scopes the Cortex budget to the public app user';
ALTER USER FORGE_APP_SVC SET TAG SUPPLY_CHAIN_FORGE.OPS.COST_SCOPE = 'public_app';

-- The stop procedure. FORGE_ADMIN owns the agent, so an owner's-rights procedure owned by
-- FORGE_ADMIN can revoke the grant, and nothing more.
GRANT CREATE PROCEDURE ON SCHEMA SUPPLY_CHAIN_FORGE.OPS TO ROLE FORGE_ADMIN;
USE ROLE FORGE_ADMIN;
CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_FORGE.OPS.SP_STOP_PUBLIC_ASK()
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'B15a: Cortex budget action. Revokes FORGE_APP_ROLE USAGE on the agent (Ask stops).'
EXECUTE AS OWNER
AS
$$
BEGIN
    REVOKE USAGE ON AGENT SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT FROM ROLE FORGE_APP_ROLE;
    RETURN 'Ask stopped: FORGE_APP_ROLE no longer has USAGE on SUPPLY_CHAIN_AGENT';
END;
$$;

USE ROLE ACCOUNTADMIN;
-- The budget calls the procedure through the SNOWFLAKE application.
GRANT USAGE ON DATABASE SUPPLY_CHAIN_FORGE TO APPLICATION SNOWFLAKE;
GRANT USAGE ON SCHEMA SUPPLY_CHAIN_FORGE.OPS TO APPLICATION SNOWFLAKE;
USE ROLE FORGE_ADMIN;
GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.OPS.SP_STOP_PUBLIC_ASK() TO APPLICATION SNOWFLAKE;

USE ROLE ACCOUNTADMIN;
CREATE SNOWFLAKE.CORE.BUDGET IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS.FORGE_APP_CORTEX_BUDGET();
CALL SUPPLY_CHAIN_FORGE.OPS.FORGE_APP_CORTEX_BUDGET!SET_SPENDING_LIMIT(25);
GRANT APPLYBUDGET ON TAG SUPPLY_CHAIN_FORGE.OPS.COST_SCOPE TO ROLE ACCOUNTADMIN;
CALL SUPPLY_CHAIN_FORGE.OPS.FORGE_APP_CORTEX_BUDGET!SET_USER_TAGS(
  [[(SELECT SYSTEM$REFERENCE('TAG', 'SUPPLY_CHAIN_FORGE.OPS.COST_SCOPE', 'SESSION', 'APPLYBUDGET')), 'public_app']],
  'UNION');
CALL SUPPLY_CHAIN_FORGE.OPS.FORGE_APP_CORTEX_BUDGET!ADD_SHARED_RESOURCE('CORTEX AGENT');
-- Re-runnable: clear the old action before adding it again.
CALL SUPPLY_CHAIN_FORGE.OPS.FORGE_APP_CORTEX_BUDGET!REMOVE_CUSTOM_ACTIONS();
CALL SUPPLY_CHAIN_FORGE.OPS.FORGE_APP_CORTEX_BUDGET!ADD_CUSTOM_ACTION(
  SYSTEM$REFERENCE('PROCEDURE', 'SUPPLY_CHAIN_FORGE.OPS.SP_STOP_PUBLIC_ASK()', 'SESSION', 'USAGE'),
  ARRAY_CONSTRUCT(),
  'ACTUAL',
  100);
CALL SUPPLY_CHAIN_FORGE.OPS.FORGE_APP_CORTEX_BUDGET!REFRESH_USAGE();

-- Checks:
-- SHOW RESOURCE MONITORS LIKE 'FORGE_WH_MONITOR';
-- CALL SUPPLY_CHAIN_FORGE.OPS.FORGE_APP_CORTEX_BUDGET!GET_SPENDING_LIMIT();
-- CALL SUPPLY_CHAIN_FORGE.OPS.FORGE_APP_CORTEX_BUDGET!GET_USER_TAGS();
-- CALL SUPPLY_CHAIN_FORGE.OPS.FORGE_APP_CORTEX_BUDGET!GET_SHARED_RESOURCES();
-- CALL SUPPLY_CHAIN_FORGE.OPS.FORGE_APP_CORTEX_BUDGET!GET_CUSTOM_ACTIONS();
