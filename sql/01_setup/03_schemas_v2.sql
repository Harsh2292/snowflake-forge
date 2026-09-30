-- ============================================================
-- 03_schemas_v2.sql — CONFORMED and OPS schemas (CR-006 layers)
-- Task: B08c
-- Owner: CoCo
-- Run as: ACCOUNTADMIN, warehouse FORGE_WH. Run before data_gen/00_setup.sql.
-- ============================================================
-- CONFORMED: dynamic tables that clean SOURCE (owned by ACCOUNTADMIN, like
--   the source tables). FORGE_ADMIN reads it (SP_DATA_HEALTH counts rows
--   there; it already sees unmasked data). Persona roles get nothing: their
--   only data path is the GOVERNED views.
-- OPS: generator, eval and logs. FORGE_ADMIN and ACCOUNTADMIN only
--   (data_gen/00_setup.sql adds its own grants).
-- ============================================================

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_FORGE.CONFORMED
    COMMENT = 'Clean, in-scope, deduplicated, USD layer between SOURCE and GOVERNED (DATA_SPEC §5.1)';

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS
    COMMENT = 'Private: data generator, evaluation, scale harness and logs (FORGE_ADMIN only)';

GRANT USAGE ON SCHEMA SUPPLY_CHAIN_FORGE.CONFORMED TO ROLE FORGE_ADMIN;
GRANT SELECT ON ALL TABLES IN SCHEMA SUPPLY_CHAIN_FORGE.CONFORMED TO ROLE FORGE_ADMIN;
GRANT SELECT ON FUTURE TABLES IN SCHEMA SUPPLY_CHAIN_FORGE.CONFORMED TO ROLE FORGE_ADMIN;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA SUPPLY_CHAIN_FORGE.CONFORMED TO ROLE FORGE_ADMIN;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA SUPPLY_CHAIN_FORGE.CONFORMED TO ROLE FORGE_ADMIN;
