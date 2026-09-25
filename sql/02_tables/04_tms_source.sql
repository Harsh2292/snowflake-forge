-- ============================================================
-- 04_tms_source.sql — TMS Source System Tables (Shipments & Freight Tracking)
-- Task: B03
-- Owner: CoCo
-- Schema: SUPPLY_CHAIN_FORGE.TMS_SOURCE
-- ============================================================

USE SCHEMA SUPPLY_CHAIN_FORGE.TMS_SOURCE;

-- 1. VTTK: Shipment Header (SAP-style)
CREATE TABLE IF NOT EXISTS VTTK (
    TKNUM           VARCHAR(10)     NOT NULL COMMENT 'Shipment Number / ID (Primary Key)',
    VBELN           VARCHAR(10)     NOT NULL COMMENT 'Order ID (Foreign Key -> ERP_SOURCE.VBAK)',
    WERKS           VARCHAR(4)      NOT NULL COMMENT 'Origin Plant ID (Foreign Key -> WMS_SOURCE.T001W)',
    CARRIER_CD      VARCHAR(20)     NOT NULL COMMENT 'Freight Carrier Code / Name',
    DPTBG           DATE            NOT NULL COMMENT 'Actual Departure / Ship Date',
    PROM_DLV_DT     DATE            NOT NULL COMMENT 'TMS Promised Delivery Date (Authoritative SLA date)',
    ACT_DLV_DT     DATE                     COMMENT 'Actual Delivery Date (NULL if currently in transit)',
    FREIGHT_AMT     NUMBER(12,2)    NOT NULL COMMENT 'Freight Transportation Cost USD',
    DUTY_AMT        NUMBER(12,2)    NOT NULL COMMENT 'Customs / Tariff Duty Cost USD',
    HANDLING_AMT    NUMBER(12,2)    NOT NULL COMMENT 'Terminal Handling / Port Charge USD',
    SHP_STATUS      VARCHAR(20)     NOT NULL COMMENT 'Shipment Tracking Status (IN_TRANSIT / DELIVERED / DELAYED)',
    CONSTRAINT PK_VTTK PRIMARY KEY (TKNUM)
) COMMENT = 'Transport Management System: Shipment header and carrier execution tracking (SAP VTTK equivalent)';
