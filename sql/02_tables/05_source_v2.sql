-- ============================================================
-- 05_source_v2.sql — Source DDL v2 (all 10 source tables)
-- Task: B08c · Spec: docs/DATA_SPEC.md §1 (supersedes 01–04 for a replay)
-- Owner: CoCo
-- Run as: ACCOUNTADMIN, warehouse FORGE_WH. Run after 01_setup/03_schemas_v2.sql,
--         before data_gen/ (C08 writes into these tables; it doesn't create them).
-- ============================================================
-- DESTRUCTIVE: drops the v1 tables and their data. Afterwards re-run
-- 04_governance/01_tags.sql (a drop removes the tags) and the governed views.
-- Rules (§1): only keys NOT NULL; PK/FK declared but not enforced (that's what
-- lets duplicates and orphans land); LOAD_TS last on every table;
-- CHANGE_TRACKING = TRUE so the CONFORMED dynamic tables refresh incrementally.
-- ============================================================

-- Children first, so no drop is blocked by a declared FK.
DROP TABLE IF EXISTS SUPPLY_CHAIN_FORGE.TMS_SOURCE.VTTK;
DROP TABLE IF EXISTS SUPPLY_CHAIN_FORGE.ERP_SOURCE.VBAP;
DROP TABLE IF EXISTS SUPPLY_CHAIN_FORGE.ERP_SOURCE.VBAK;
DROP TABLE IF EXISTS SUPPLY_CHAIN_FORGE.ERP_SOURCE.KNA1;
DROP TABLE IF EXISTS SUPPLY_CHAIN_FORGE.ERP_SOURCE.TCURR;
DROP TABLE IF EXISTS SUPPLY_CHAIN_FORGE.WMS_SOURCE.MARD;
DROP TABLE IF EXISTS SUPPLY_CHAIN_FORGE.WMS_SOURCE.T001W;
DROP TABLE IF EXISTS SUPPLY_CHAIN_FORGE.SRM_SOURCE.SOURCING;
DROP TABLE IF EXISTS SUPPLY_CHAIN_FORGE.SRM_SOURCE.MARA;
DROP TABLE IF EXISTS SUPPLY_CHAIN_FORGE.SRM_SOURCE.LFA1;

-- ── SRM_SOURCE ──────────────────────────────────────────────
CREATE TABLE SUPPLY_CHAIN_FORGE.SRM_SOURCE.LFA1 (
    LIFNR           VARCHAR(10)     NOT NULL COMMENT 'Supplier ID (PK)',
    NAME1           VARCHAR(100)             COMMENT 'Supplier name',
    LAND1           VARCHAR(3)               COMMENT 'Country code (ISO 3-char)',
    REGIO           VARCHAR(20)              COMMENT 'Region APAC / EMEA / AMER (messy: DATA_SPEC §4 M03)',
    SUPP_TIER       NUMBER(1,0)              COMMENT 'Supplier tier 1-3',
    LEAD_TM_DAYS    NUMBER(3,0)              COMMENT 'Average lead time in days',
    RELIAB_SCR      NUMBER(3,2)              COMMENT 'Reliability score 0.00-1.00',
    ZTERM           VARCHAR(20)              COMMENT 'Payment terms (commercial, sensitive)',
    EMAIL           VARCHAR(100)             COMMENT 'Supplier contact email (PII)',
    ERDAT           DATE                     COMMENT 'Created on (onboarding date)',
    LOAD_TS         TIMESTAMP_NTZ            COMMENT 'When the row landed (nightly batch)',
    CONSTRAINT PK_LFA1 PRIMARY KEY (LIFNR)
) CHANGE_TRACKING = TRUE
  COMMENT = 'Supplier Relationship Management: supplier master (SAP LFA1)';

CREATE TABLE SUPPLY_CHAIN_FORGE.SRM_SOURCE.MARA (
    MATNR           VARCHAR(18)     NOT NULL COMMENT 'Part ID (PK)',
    MAKTX           VARCHAR(100)             COMMENT 'Part description',
    MATKL           VARCHAR(30)              COMMENT 'Material category (messy: §4 M03)',
    SUBCAT          VARCHAR(30)              COMMENT 'Material subcategory',
    STPRS           NUMBER(12,2)             COMMENT 'Standard unit cost USD (sensitive)',
    BRGEW           NUMBER(10,3)             COMMENT 'Gross weight in kg',
    CRIT_FLG        BOOLEAN                  COMMENT 'Critical component flag',
    LOAD_TS         TIMESTAMP_NTZ            COMMENT 'When the row landed',
    CONSTRAINT PK_MARA PRIMARY KEY (MATNR)
) CHANGE_TRACKING = TRUE
  COMMENT = 'Supplier Relationship Management: material master (SAP MARA)';

CREATE TABLE SUPPLY_CHAIN_FORGE.SRM_SOURCE.SOURCING (
    SOURCE_ID       VARCHAR(20)     NOT NULL COMMENT 'Sourcing record ID (PK)',
    LIFNR           VARCHAR(10)              COMMENT 'Supplier ID (FK -> LFA1)',
    MATNR           VARCHAR(18)              COMMENT 'Part ID (FK -> MARA)',
    IS_PRIMARY      BOOLEAN                  COMMENT 'Primary sourcing flag',
    CONTRACT_PRICE  NUMBER(12,2)             COMMENT 'Contracted unit price in WAERS (sensitive)',
    WAERS           VARCHAR(3)               COMMENT 'Contract currency',
    VDATU           DATE                     COMMENT 'Valid from',
    BDATU           DATE                     COMMENT 'Valid to; NULL = open-ended',
    LOAD_TS         TIMESTAMP_NTZ            COMMENT 'When the row landed',
    CONSTRAINT PK_SOURCING PRIMARY KEY (SOURCE_ID),
    CONSTRAINT FK_SOURCING_LFA1 FOREIGN KEY (LIFNR) REFERENCES SUPPLY_CHAIN_FORGE.SRM_SOURCE.LFA1 (LIFNR),
    CONSTRAINT FK_SOURCING_MARA FOREIGN KEY (MATNR) REFERENCES SUPPLY_CHAIN_FORGE.SRM_SOURCE.MARA (MATNR)
) CHANGE_TRACKING = TRUE
  COMMENT = 'Supplier Relationship Management: supplier-to-part source list with validity (SAP EORD semantics)';

-- ── WMS_SOURCE ──────────────────────────────────────────────
CREATE TABLE SUPPLY_CHAIN_FORGE.WMS_SOURCE.T001W (
    WERKS           VARCHAR(4)      NOT NULL COMMENT 'Plant ID (PK)',
    NAME1           VARCHAR(100)             COMMENT 'Plant / facility name',
    LAND1           VARCHAR(3)               COMMENT 'Country code (ISO 3-char)',
    REGION_CD       VARCHAR(20)              COMMENT 'Region code APAC / EMEA / AMER (messy: §4 M03)',
    PLANT_TYPE      VARCHAR(20)              COMMENT 'Facility type MFG / DC / HUB',
    CAPACITY_UNITS  NUMBER(10,0)             COMMENT 'Maximum capacity units',
    LOAD_TS         TIMESTAMP_NTZ            COMMENT 'When the row landed',
    CONSTRAINT PK_T001W PRIMARY KEY (WERKS)
) CHANGE_TRACKING = TRUE
  COMMENT = 'Warehouse Management System: plant master (SAP T001W)';

CREATE TABLE SUPPLY_CHAIN_FORGE.WMS_SOURCE.MARD (
    INV_KEY         VARCHAR(40)     NOT NULL COMMENT 'Snapshot key WERKS-MATNR-YYYYMMDD (PK)',
    WERKS           VARCHAR(4)               COMMENT 'Plant ID (FK -> T001W)',
    MATNR           VARCHAR(18)              COMMENT 'Part ID (FK -> SRM_SOURCE.MARA)',
    LABST           NUMBER(12,3)             COMMENT 'Valuated stock on hand',
    INSME           NUMBER(12,3)             COMMENT 'Quantity in inspection / reserved',
    REORD_PT        NUMBER(12,3)             COMMENT 'Reorder point',
    DAILY_USG       NUMBER(12,3)             COMMENT 'Average daily usage',
    SNAP_DT         DATE                     COMMENT 'Snapshot date',
    LOAD_TS         TIMESTAMP_NTZ            COMMENT 'When the row landed',
    CONSTRAINT PK_MARD PRIMARY KEY (INV_KEY),
    CONSTRAINT FK_MARD_T001W FOREIGN KEY (WERKS) REFERENCES SUPPLY_CHAIN_FORGE.WMS_SOURCE.T001W (WERKS)
) CHANGE_TRACKING = TRUE
  COMMENT = 'Warehouse Management System: inventory snapshots, weekly + daily for the last 90 days (SAP MARD)';

-- ── ERP_SOURCE ──────────────────────────────────────────────
CREATE TABLE SUPPLY_CHAIN_FORGE.ERP_SOURCE.KNA1 (
    KUNNR           VARCHAR(10)     NOT NULL COMMENT 'Customer ID (PK)',
    NAME1           VARCHAR(100)             COMMENT 'Customer / company name (PII)',
    EMAIL           VARCHAR(100)             COMMENT 'Customer contact email (PII)',
    LAND1           VARCHAR(3)               COMMENT 'Country code (ISO 3-char)',
    REGIO           VARCHAR(20)              COMMENT 'Region APAC / EMEA / AMER (messy: §4 M03)',
    KTOKD           VARCHAR(20)              COMMENT 'Segment ENTERPRISE / MIDMARKET / SMB (messy: §4 M03)',
    KLIMK           NUMBER(15,2)             COMMENT 'Credit limit USD (sensitive)',
    ERDAT           DATE                     COMMENT 'Created on',
    LOAD_TS         TIMESTAMP_NTZ            COMMENT 'When the row landed',
    CONSTRAINT PK_KNA1 PRIMARY KEY (KUNNR)
) CHANGE_TRACKING = TRUE
  COMMENT = 'Enterprise Resource Planning: customer master (SAP KNA1)';

CREATE TABLE SUPPLY_CHAIN_FORGE.ERP_SOURCE.VBAK (
    VBELN           VARCHAR(12)     NOT NULL COMMENT 'Sales order ID (PK)',
    KUNNR           VARCHAR(10)              COMMENT 'Customer ID (FK -> KNA1)',
    AUDAT           DATE                     COMMENT 'Order document date',
    ERDAT           DATE                     COMMENT 'ERP promised date: conflicts with TMS, never exposed downstream (§4 E10)',
    GBSTK           VARCHAR(20)              COMMENT 'Status OPEN / SHIPPED / DELIVERED / CANCELLED (messy: §4 M03)',
    PRIO            VARCHAR(10)              COMMENT 'Priority HIGH / NORMAL / LOW (messy: §4 M03)',
    AUART           VARCHAR(4)               COMMENT 'Order type: OR standard, RE return (§4 E03)',
    WAERK           VARCHAR(3)               COMMENT 'Document currency of all line prices',
    LOAD_TS         TIMESTAMP_NTZ            COMMENT 'When the row landed',
    CONSTRAINT PK_VBAK PRIMARY KEY (VBELN),
    CONSTRAINT FK_VBAK_KNA1 FOREIGN KEY (KUNNR) REFERENCES SUPPLY_CHAIN_FORGE.ERP_SOURCE.KNA1 (KUNNR)
) CHANGE_TRACKING = TRUE
  COMMENT = 'Enterprise Resource Planning: sales order header (SAP VBAK)';

CREATE TABLE SUPPLY_CHAIN_FORGE.ERP_SOURCE.VBAP (
    LINE_ID         VARCHAR(20)     NOT NULL COMMENT 'Order line ID (PK)',
    VBELN           VARCHAR(12)              COMMENT 'Order ID (FK -> VBAK)',
    MATNR           VARCHAR(18)              COMMENT 'Part ID (FK -> SRM_SOURCE.MARA)',
    WERKS           VARCHAR(4)               COMMENT 'Fulfilling plant ID (FK -> WMS_SOURCE.T001W)',
    KWMENG          NUMBER(12,3)             COMMENT 'Order quantity',
    QTY_SHIPPED     NUMBER(12,3)             COMMENT 'Quantity shipped',
    NETPR           NUMBER(14,2)             COMMENT 'Net price per unit in VBAK.WAERK',
    LOAD_TS         TIMESTAMP_NTZ            COMMENT 'When the row landed',
    CONSTRAINT PK_VBAP PRIMARY KEY (LINE_ID),
    CONSTRAINT FK_VBAP_VBAK FOREIGN KEY (VBELN) REFERENCES SUPPLY_CHAIN_FORGE.ERP_SOURCE.VBAK (VBELN)
) CHANGE_TRACKING = TRUE
  COMMENT = 'Enterprise Resource Planning: sales order line (SAP VBAP)';

CREATE TABLE SUPPLY_CHAIN_FORGE.ERP_SOURCE.TCURR (
    KURST           VARCHAR(4)      NOT NULL COMMENT 'Rate type (always M, average)',
    FCURR           VARCHAR(3)      NOT NULL COMMENT 'From currency',
    TCURR           VARCHAR(3)      NOT NULL COMMENT 'To currency (always USD)',
    GDATU           DATE            NOT NULL COMMENT 'Valid-from date',
    UKURS           NUMBER(18,9)             COMMENT 'USD per 1 unit of FCURR',
    LOAD_TS         TIMESTAMP_NTZ            COMMENT 'When the row landed',
    CONSTRAINT PK_TCURR PRIMARY KEY (KURST, FCURR, TCURR, GDATU)
) CHANGE_TRACKING = TRUE
  COMMENT = 'Enterprise Resource Planning: daily FX rates to USD (SAP TCURR)';

-- ── TMS_SOURCE ──────────────────────────────────────────────
CREATE TABLE SUPPLY_CHAIN_FORGE.TMS_SOURCE.VTTK (
    TKNUM           VARCHAR(12)     NOT NULL COMMENT 'Shipment ID (PK)',
    VBELN           VARCHAR(12)              COMMENT 'Order ID (FK -> ERP_SOURCE.VBAK)',
    WERKS           VARCHAR(4)               COMMENT 'Origin plant ID (FK -> WMS_SOURCE.T001W)',
    CARRIER_CD      VARCHAR(30)              COMMENT 'Carrier code (messy: §4 M03)',
    DPTBG           DATE                     COMMENT 'Ship (departure) date',
    PROM_DLV_DT     DATE                     COMMENT 'TMS promised delivery date (authoritative)',
    ACT_DLV_DT      DATE                     COMMENT 'Actual delivery date; NULL while in transit',
    FREIGHT_AMT     NUMBER(14,2)             COMMENT 'Freight cost in WAERS',
    DUTY_AMT        NUMBER(14,2)             COMMENT 'Customs duty in WAERS',
    HANDLING_AMT    NUMBER(14,2)             COMMENT 'Handling cost in WAERS',
    SHP_STATUS      VARCHAR(20)              COMMENT 'Status IN_TRANSIT / DELIVERED / DELAYED (messy: §4 M03)',
    WAERS           VARCHAR(3)               COMMENT 'Currency of the three amounts',
    LOAD_TS         TIMESTAMP_NTZ            COMMENT 'When the row landed',
    CONSTRAINT PK_VTTK PRIMARY KEY (TKNUM)
) CHANGE_TRACKING = TRUE
  COMMENT = 'Transport Management System: shipment header and carrier execution (SAP VTTK)';
