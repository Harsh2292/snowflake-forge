-- ============================================================
-- 01_database.sql — Database, schemas, and warehouse setup
-- Task: B01
-- Owner: CoCo
-- Run: First
-- ============================================================

-- 1. Database
CREATE DATABASE IF NOT EXISTS SUPPLY_CHAIN_FORGE
    COMMENT = 'Supply Chain Forge governed ontology and conversational analytics database';

-- 2. Schemas (Four disparate source systems + Governed + Semantic + App)
CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_FORGE.ERP_SOURCE
    COMMENT = 'Enterprise Resource Planning source tables (customers, sales orders, order lines)';

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_FORGE.WMS_SOURCE
    COMMENT = 'Warehouse Management System source tables (plants, inventory snapshots)';

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_FORGE.TMS_SOURCE
    COMMENT = 'Transport Management System source tables (shipments, carriers)';

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_FORGE.SRM_SOURCE
    COMMENT = 'Supplier Relationship Management source tables (suppliers, parts, sourcing contracts)';

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_FORGE.GOVERNED
    COMMENT = 'Conformed business views, column masking policies, and persona stored procedures';

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_FORGE.SEMANTIC
    COMMENT = 'Semantic view ontology, Cortex Agent, and MCP server endpoints';

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_FORGE.APP
    COMMENT = 'Streamlit in Snowflake application schema';

-- Drop default PUBLIC schema if created
DROP SCHEMA IF EXISTS SUPPLY_CHAIN_FORGE.PUBLIC;

-- 3. Dedicated Warehouse
CREATE WAREHOUSE IF NOT EXISTS FORGE_WH
    WITH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Dedicated X-Small warehouse for Supply Chain Forge demo workload';
