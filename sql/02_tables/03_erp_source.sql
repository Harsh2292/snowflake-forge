-- ============================================================
-- 03_erp_source.sql — ERP Source System Tables (Customers, Orders, Order Lines)
-- Task: B03
-- Owner: CoCo
-- Schema: SUPPLY_CHAIN_FORGE.ERP_SOURCE
-- ============================================================

USE SCHEMA SUPPLY_CHAIN_FORGE.ERP_SOURCE;

-- 1. KNA1: Customer Master (SAP-style)
CREATE TABLE IF NOT EXISTS KNA1 (
    KUNNR           VARCHAR(10)     NOT NULL COMMENT 'Customer ID (Primary Key)',
    NAME1           VARCHAR(100)    NOT NULL COMMENT 'Customer / Company Name (PII)',
    EMAIL           VARCHAR(100)    NOT NULL COMMENT 'Customer Contact Email (PII)',
    LAND1           VARCHAR(3)      NOT NULL COMMENT 'Country Code (ISO 3-char)',
    REGIO           VARCHAR(20)     NOT NULL COMMENT 'Region (APAC / EMEA / AMER)',
    KTOKD           VARCHAR(20)     NOT NULL COMMENT 'Customer Account Group / Segment (ENTERPRISE / MIDMARKET / SMB)',
    KLIMK           NUMBER(15,2)    NOT NULL COMMENT 'Credit Limit USD (Sensitive Financial)',
    CONSTRAINT PK_KNA1 PRIMARY KEY (KUNNR)
) COMMENT = 'Enterprise Resource Planning: General customer master data (SAP KNA1 equivalent)';

-- 2. VBAK: Sales Document Header (SAP-style)
CREATE TABLE IF NOT EXISTS VBAK (
    VBELN           VARCHAR(10)     NOT NULL COMMENT 'Sales Document / Order ID (Primary Key)',
    KUNNR           VARCHAR(10)     NOT NULL COMMENT 'Customer ID (Foreign Key -> KNA1)',
    AUDAT           DATE            NOT NULL COMMENT 'Order Document Date',
    ERDAT           DATE            NOT NULL COMMENT 'ERP Promised Delivery Date (Deliberately differs from TMS!)',
    GBSTK           VARCHAR(20)     NOT NULL COMMENT 'Overall Processing Status (OPEN / SHIPPED / DELIVERED / CANCELLED)',
    PRIO            VARCHAR(10)     NOT NULL COMMENT 'Order Priority (HIGH / NORMAL / LOW)',
    CONSTRAINT PK_VBAK PRIMARY KEY (VBELN),
    CONSTRAINT FK_VBAK_KNA1 FOREIGN KEY (KUNNR) REFERENCES KNA1 (KUNNR)
) COMMENT = 'Enterprise Resource Planning: Sales document header (SAP VBAK equivalent)';

-- 3. VBAP: Sales Document Item / Line (SAP-style)
CREATE TABLE IF NOT EXISTS VBAP (
    LINE_ID         VARCHAR(20)     NOT NULL COMMENT 'Order Line ID (Primary Key)',
    VBELN           VARCHAR(10)     NOT NULL COMMENT 'Order ID (Foreign Key -> VBAK)',
    MATNR           VARCHAR(18)     NOT NULL COMMENT 'Material / Part ID (Foreign Key -> SRM_SOURCE.MARA)',
    WERKS           VARCHAR(4)      NOT NULL COMMENT 'Fulfilling Plant ID (Foreign Key -> WMS_SOURCE.T001W)',
    KWMENG          NUMBER(12,3)    NOT NULL COMMENT 'Cumulative Order Quantity',
    QTY_SHIPPED     NUMBER(12,3)    NOT NULL COMMENT 'Delivered Quantity Shipped (<= KWMENG)',
    NETPR           NUMBER(12,2)    NOT NULL COMMENT 'Net Selling Price USD per unit',
    CONSTRAINT PK_VBAP PRIMARY KEY (LINE_ID),
    CONSTRAINT FK_VBAP_VBAK FOREIGN KEY (VBELN) REFERENCES VBAK (VBELN)
) COMMENT = 'Enterprise Resource Planning: Sales document line item (SAP VBAP equivalent)';
