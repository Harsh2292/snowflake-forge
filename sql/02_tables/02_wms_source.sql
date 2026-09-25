-- ============================================================
-- 02_wms_source.sql — WMS Source System Tables (Plants, Inventory Snapshots)
-- Task: B03
-- Owner: CoCo
-- Schema: SUPPLY_CHAIN_FORGE.WMS_SOURCE
-- ============================================================

USE SCHEMA SUPPLY_CHAIN_FORGE.WMS_SOURCE;

-- 1. T001W: Plant / Warehouse Master (SAP-style)
CREATE TABLE IF NOT EXISTS T001W (
    WERKS           VARCHAR(4)      NOT NULL COMMENT 'Plant ID (Primary Key)',
    NAME1           VARCHAR(100)    NOT NULL COMMENT 'Plant / Facility Name',
    LAND1           VARCHAR(3)      NOT NULL COMMENT 'Country Code (ISO 3-char)',
    REGION_CD       VARCHAR(20)     NOT NULL COMMENT 'Region Code (APAC / EMEA / AMER)',
    PLANT_TYPE      VARCHAR(20)     NOT NULL COMMENT 'Facility Type (MFG / DC / HUB)',
    CAPACITY_UNITS  NUMBER(10,0)    NOT NULL COMMENT 'Maximum Production/Storage Capacity Units',
    CONSTRAINT PK_T001W PRIMARY KEY (WERKS)
) COMMENT = 'Warehouse Management System: Plant and warehouse facilities master (SAP T001W equivalent)';

-- 2. MARD: Storage Location Daily Inventory Snapshots (SAP-style)
CREATE TABLE IF NOT EXISTS MARD (
    INV_KEY         VARCHAR(40)     NOT NULL COMMENT 'Compound Snapshot Key (WERKS||MATNR||SNAP_DT)',
    WERKS           VARCHAR(4)      NOT NULL COMMENT 'Plant ID (Foreign Key -> T001W)',
    MATNR           VARCHAR(18)     NOT NULL COMMENT 'Part ID (Foreign Key -> SRM_SOURCE.MARA)',
    LABST           NUMBER(12,3)    NOT NULL COMMENT 'Valuated Stock on Hand (Gross Quantity)',
    INSME           NUMBER(12,3)    NOT NULL COMMENT 'Quantity in Quality Inspection / Reserved',
    REORD_PT        NUMBER(12,3)    NOT NULL COMMENT 'Safety Stock Reorder Point',
    DAILY_USG       NUMBER(12,3)    NOT NULL COMMENT 'Average Daily Usage Rate',
    SNAP_DT         DATE            NOT NULL COMMENT 'Snapshot Date',
    CONSTRAINT PK_MARD PRIMARY KEY (INV_KEY),
    CONSTRAINT FK_MARD_T001W FOREIGN KEY (WERKS) REFERENCES T001W (WERKS)
) COMMENT = 'Warehouse Management System: Daily storage location stock snapshot (SAP MARD equivalent)';
