-- ============================================================
-- 01_app_service_user.sql — the public app's read-only role and service user
-- Task: B15a (ADR-009; deploy/RUNBOOK.md step 2)
-- Owner: CoCo
-- Run as: ACCOUNTADMIN (FORGE_ADMIN for the two grants on objects it owns), FORGE_WH
-- Re-runnable: IF NOT EXISTS, idempotent grants. Account-agnostic: names no account.
-- ============================================================
-- FORGE_APP_ROLE holds exactly what app/utils/forge_data.py touches, nothing that writes:
--   SEMANTIC.SUPPLY_CHAIN_SV (SELECT)       every metric query
--   GOVERNED: the 9 views (SELECT)          the DOI window subquery reads V_INVENTORY directly;
--                                           the agent's Analyst can also query the views (B10)
--   GOVERNED.SP_SAMPLE_AS_* / SP_METRICS_AS_* (USAGE)   persona proofs, owner's rights
--   SEMANTIC.SP_DATA_HEALTH (USAGE)         the as-of date and the Data health screen
--   SEMANTIC.SUPPLY_CHAIN_AGENT (USAGE)     the Ask screen (+ SNOWFLAKE.CORTEX_USER)
--   TMS_SOURCE.VTTK, ERP_SOURCE.VBAK (SELECT)   contract §8 only
--   SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER    get_quality_results()
--
-- Verified live at B15a (2026-09-30), as FORGE_APP_ROLE with USE SECONDARY ROLES NONE:
--   - SEMANTIC_VIEW(...) needs NO grant on the views under the semantic view (incl. the
--     primary_sourcing inline table): OTD ran with only the semantic-view grant.
--   - The DOI query's (SELECT MAX(snapshot_date) FROM GOVERNED.V_INVENTORY) subquery sits
--     outside the semantic view and needs SELECT on V_INVENTORY.
--   - DATA_QUALITY_MONITORING_RESULTS shows all 77 associations to this role, like FORGE_ADMIN.
--   - The governed views mask for this role (email '*** MASKED ***', credit limit NULL); row
--     counts and metric values equal FORGE_ADMIN's.
--   - The agent's tools run as the calling role (B10), so this role is what the agent's SQL uses.
-- ============================================================

USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS FORGE_APP_ROLE
  COMMENT = 'B15a: read-only role of the public app (FORGE_APP_SVC). Only what forge_data.py touches.';
GRANT ROLE FORGE_APP_ROLE TO ROLE SYSADMIN;

GRANT USAGE ON WAREHOUSE FORGE_WH TO ROLE FORGE_APP_ROLE;
GRANT USAGE ON DATABASE SUPPLY_CHAIN_FORGE TO ROLE FORGE_APP_ROLE;
GRANT USAGE ON SCHEMA SUPPLY_CHAIN_FORGE.SEMANTIC TO ROLE FORGE_APP_ROLE;
GRANT USAGE ON SCHEMA SUPPLY_CHAIN_FORGE.GOVERNED TO ROLE FORGE_APP_ROLE;
GRANT USAGE ON SCHEMA SUPPLY_CHAIN_FORGE.TMS_SOURCE TO ROLE FORGE_APP_ROLE;
GRANT USAGE ON SCHEMA SUPPLY_CHAIN_FORGE.ERP_SOURCE TO ROLE FORGE_APP_ROLE;

GRANT SELECT ON SEMANTIC VIEW SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV TO ROLE FORGE_APP_ROLE;

GRANT SELECT ON VIEW SUPPLY_CHAIN_FORGE.GOVERNED.V_SUPPLIER   TO ROLE FORGE_APP_ROLE;
GRANT SELECT ON VIEW SUPPLY_CHAIN_FORGE.GOVERNED.V_PART       TO ROLE FORGE_APP_ROLE;
GRANT SELECT ON VIEW SUPPLY_CHAIN_FORGE.GOVERNED.V_SOURCING   TO ROLE FORGE_APP_ROLE;
GRANT SELECT ON VIEW SUPPLY_CHAIN_FORGE.GOVERNED.V_PLANT      TO ROLE FORGE_APP_ROLE;
GRANT SELECT ON VIEW SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY  TO ROLE FORGE_APP_ROLE;
GRANT SELECT ON VIEW SUPPLY_CHAIN_FORGE.GOVERNED.V_CUSTOMER   TO ROLE FORGE_APP_ROLE;
GRANT SELECT ON VIEW SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER      TO ROLE FORGE_APP_ROLE;
GRANT SELECT ON VIEW SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER_LINE TO ROLE FORGE_APP_ROLE;
GRANT SELECT ON VIEW SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT   TO ROLE FORGE_APP_ROLE;

-- Contract §8: the one app query that reads source tables.
GRANT SELECT ON TABLE SUPPLY_CHAIN_FORGE.TMS_SOURCE.VTTK TO ROLE FORGE_APP_ROLE;
GRANT SELECT ON TABLE SUPPLY_CHAIN_FORGE.ERP_SOURCE.VBAK TO ROLE FORGE_APP_ROLE;

GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_PLANNER()    TO ROLE FORGE_APP_ROLE;
GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_BUYER()      TO ROLE FORGE_APP_ROLE;
GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_LOGISTICS()  TO ROLE FORGE_APP_ROLE;
GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_PLANNER()   TO ROLE FORGE_APP_ROLE;
GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_BUYER()     TO ROLE FORGE_APP_ROLE;
GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_LOGISTICS() TO ROLE FORGE_APP_ROLE;

GRANT APPLICATION ROLE SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER TO ROLE FORGE_APP_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE FORGE_APP_ROLE;

-- The service user: key-pair only (TYPE = SERVICE has no password and no MFA).
-- The public key is set in the step below, from the user's rsa_key.pub (RUNBOOK step 1).
CREATE USER IF NOT EXISTS FORGE_APP_SVC
  TYPE = SERVICE
  DEFAULT_ROLE = FORGE_APP_ROLE
  DEFAULT_WAREHOUSE = FORGE_WH
  DEFAULT_SECONDARY_ROLES = ()
  COMMENT = 'B15a: the public Streamlit Community Cloud app (read-only, key-pair JWT)';
GRANT ROLE FORGE_APP_ROLE TO USER FORGE_APP_SVC;

-- Objects FORGE_ADMIN owns: the data-health procedure and the agent.
USE ROLE FORGE_ADMIN;
GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH(VARCHAR) TO ROLE FORGE_APP_ROLE;
-- 02_cost_controls.sql revokes this grant automatically when the Cortex budget is used up;
-- re-running this file restores it.
GRANT USAGE ON AGENT SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT TO ROLE FORGE_APP_ROLE;

-- Step 2b (ACCOUNTADMIN, once per account, not re-run blindly): the public key body only,
-- the lines between BEGIN and END joined into one line. Never the private key.
-- ALTER USER FORGE_APP_SVC SET RSA_PUBLIC_KEY = '<public key body>';
-- Check: DESC USER FORGE_APP_SVC  ->  RSA_PUBLIC_KEY_FP = SHA256:...
