-- ============================================================
-- 01_srm_source.sql — SRM Source System Tables (Suppliers, Parts, Sourcing)
-- Task: B03
-- Owner: CoCo
-- Schema: SUPPLY_CHAIN_FORGE.SRM_SOURCE
-- ============================================================

USE SCHEMA SUPPLY_CHAIN_FORGE.SRM_SOURCE;

-- 1. LFA1: Supplier Master (SAP-style)
CREATE TABLE IF NOT EXISTS LFA1 (
    LIFNR           VARCHAR(10)     NOT NULL COMMENT 'Supplier ID (Primary Key)',
    NAME1           VARCHAR(100)    NOT NULL COMMENT 'Supplier Name',
    LAND1           VARCHAR(3)      NOT NULL COMMENT 'Country Code (ISO 3-char)',
    REGIO           VARCHAR(20)     NOT NULL COMMENT 'Region (APAC / EMEA / AMER)',
    SUPP_TIER       NUMBER(1,0)     NOT NULL COMMENT 'Supplier Tier (1, 2, or 3)',
    LEAD_TM_DAYS    NUMBER(3,0)     NOT NULL COMMENT 'Average Lead Time in Days',
    RELIAB_SCR      NUMBER(3,2)     NOT NULL COMMENT 'Reliability Score (0.00 to 1.00)',
    ZTERM           VARCHAR(20)     NOT NULL COMMENT 'Payment Terms (Commercial/Sensitive)',
    EMAIL           VARCHAR(100)    NOT NULL COMMENT 'Supplier Contact Email (PII)',
    CONSTRAINT PK_LFA1 PRIMARY KEY (LIFNR)
) COMMENT = 'Supplier Relationship Management: Supplier master records (SAP LFA1 equivalent)';

-- 2. MARA: Material / Part Master (SAP-style)
CREATE TABLE IF NOT EXISTS MARA (
    MATNR           VARCHAR(18)     NOT NULL COMMENT 'Part ID (Primary Key)',
    MAKTX           VARCHAR(100)    NOT NULL COMMENT 'Part Description / Name',
    MATKL           VARCHAR(30)     NOT NULL COMMENT 'Material Category',
    SUBCAT          VARCHAR(30)     NOT NULL COMMENT 'Material Subcategory',
    STPRS           NUMBER(12,2)    NOT NULL COMMENT 'Standard Unit Cost USD (Sensitive)',
    BRGEW           NUMBER(10,3)    NOT NULL COMMENT 'Gross Weight in kg',
    CRIT_FLG        BOOLEAN         NOT NULL COMMENT 'Critical Component Flag',
    CONSTRAINT PK_MARA PRIMARY KEY (MATNR)
) COMMENT = 'Supplier Relationship Management: General material master data (SAP MARA equivalent)';

-- 3. SOURCING: Sourcing Contracts (Supplier <-> Part M:N relationship)
CREATE TABLE IF NOT EXISTS SOURCING (
    SOURCE_ID       VARCHAR(20)     NOT NULL COMMENT 'Sourcing Record ID (Primary Key)',
    LIFNR           VARCHAR(10)     NOT NULL COMMENT 'Supplier ID (Foreign Key -> LFA1)',
    MATNR           VARCHAR(18)     NOT NULL COMMENT 'Part ID (Foreign Key -> MARA)',
    IS_PRIMARY      BOOLEAN         NOT NULL COMMENT 'Primary Sourcing Flag',
    CONTRACT_PRICE  NUMBER(12,2)    NOT NULL COMMENT 'Contracted Unit Price USD (Sensitive)',
    CONSTRAINT PK_SOURCING PRIMARY KEY (SOURCE_ID),
    CONSTRAINT FK_SOURCING_LFA1 FOREIGN KEY (LIFNR) REFERENCES LFA1 (LIFNR),
    CONSTRAINT FK_SOURCING_MARA FOREIGN KEY (MATNR) REFERENCES MARA (MATNR)
) COMMENT = 'Supplier Relationship Management: Supplier-to-part sourcing contracts';
