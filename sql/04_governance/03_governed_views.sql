-- ============================================================
-- 03_governed_views.sql — Governed Layer: 9 Conformed Business Views
-- Task: B07
-- Owner: CoCo
-- Schema: SUPPLY_CHAIN_FORGE.GOVERNED
-- Run as: ACCOUNTADMIN (owns the source tables; FORGE_ADMIN has no
--         SELECT on source tables, so views must be owned here)
-- ============================================================
-- Masking policies and tags are attached INLINE, so each view is created
-- in one atomic statement: a view never exists unmasked, and re-running
-- CREATE OR REPLACE cannot silently drop a policy.
-- Column names are exactly docs/CONTRACT.md §7. Masking is exactly §6.
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SUPPLY_CHAIN_FORGE;
USE SCHEMA GOVERNED;

-- 1. V_SUPPLIER  <- SRM_SOURCE.LFA1
CREATE OR REPLACE VIEW V_SUPPLIER (
    supplier_id         COMMENT 'Supplier ID (LFA1.LIFNR)',
    supplier_name       COMMENT 'Supplier name (LFA1.NAME1)',
    country             COMMENT 'Country code, ISO 3-char (LFA1.LAND1)',
    region              COMMENT 'Region: APAC / EMEA / AMER (LFA1.REGIO)',
    supplier_tier       COMMENT 'Supplier tier 1-3 (LFA1.SUPP_TIER)',
    lead_time_days      COMMENT 'Average lead time in days (LFA1.LEAD_TM_DAYS)',
    reliability_score   COMMENT 'Reliability score 0.00-1.00 (LFA1.RELIAB_SCR)',
    payment_terms       WITH MASKING POLICY SUPPLY_CHAIN_FORGE.GOVERNED.MASK_PAYMENT_TERMS
                        WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'RESTRICTED')
                        COMMENT 'Commercial payment terms, masked for non-buyers (LFA1.ZTERM)',
    email               WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.PII = 'TRUE',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'CONFIDENTIAL')
                        COMMENT 'Supplier contact email (LFA1.EMAIL)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'SUPPLIER',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'SRM',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'CONFIDENTIAL')
COMMENT = 'Governed supplier entity, conformed from SRM LFA1'
AS
SELECT LIFNR, NAME1, LAND1, REGIO, SUPP_TIER, LEAD_TM_DAYS, RELIAB_SCR, ZTERM, EMAIL
FROM SUPPLY_CHAIN_FORGE.SRM_SOURCE.LFA1;

-- 2. V_PART  <- SRM_SOURCE.MARA
CREATE OR REPLACE VIEW V_PART (
    part_id             COMMENT 'Part ID (MARA.MATNR)',
    part_name           COMMENT 'Part description (MARA.MAKTX)',
    category            COMMENT 'Material category (MARA.MATKL)',
    subcategory         COMMENT 'Material subcategory (MARA.SUBCAT)',
    unit_cost           WITH MASKING POLICY SUPPLY_CHAIN_FORGE.GOVERNED.MASK_SUPPLIER_COST
                        WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'RESTRICTED',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.METRIC_FAMILY = 'COST')
                        COMMENT 'Standard unit cost USD, masked for non-buyers (MARA.STPRS)',
    weight_kg           COMMENT 'Gross weight in kg (MARA.BRGEW)',
    is_critical         COMMENT 'Critical component flag (MARA.CRIT_FLG)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'PART',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'SRM',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'INTERNAL')
COMMENT = 'Governed part entity, conformed from SRM MARA'
AS
SELECT MATNR, MAKTX, MATKL, SUBCAT, STPRS, BRGEW, CRIT_FLG
FROM SUPPLY_CHAIN_FORGE.SRM_SOURCE.MARA;

-- 3. V_SOURCING  <- SRM_SOURCE.SOURCING
CREATE OR REPLACE VIEW V_SOURCING (
    source_id           COMMENT 'Sourcing record ID (SOURCING.SOURCE_ID)',
    supplier_id         COMMENT 'Supplier ID -> V_SUPPLIER (SOURCING.LIFNR)',
    part_id             COMMENT 'Part ID -> V_PART (SOURCING.MATNR)',
    is_primary          COMMENT 'Primary sourcing flag (SOURCING.IS_PRIMARY)',
    contract_price      WITH MASKING POLICY SUPPLY_CHAIN_FORGE.GOVERNED.MASK_SUPPLIER_COST
                        WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'RESTRICTED',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.METRIC_FAMILY = 'COST')
                        COMMENT 'Contracted unit price USD, masked for non-buyers (SOURCING.CONTRACT_PRICE)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'SOURCING',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'SRM',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'RESTRICTED')
COMMENT = 'Governed supplier-to-part sourcing contracts, conformed from SRM SOURCING'
AS
SELECT SOURCE_ID, LIFNR, MATNR, IS_PRIMARY, CONTRACT_PRICE
FROM SUPPLY_CHAIN_FORGE.SRM_SOURCE.SOURCING;

-- 4. V_PLANT  <- WMS_SOURCE.T001W
CREATE OR REPLACE VIEW V_PLANT (
    plant_id            COMMENT 'Plant ID (T001W.WERKS)',
    plant_name          COMMENT 'Plant / facility name (T001W.NAME1)',
    country             COMMENT 'Country code, ISO 3-char (T001W.LAND1)',
    region              COMMENT 'Region: APAC / EMEA / AMER (T001W.REGION_CD)',
    plant_type          COMMENT 'Facility type: MFG / DC / HUB (T001W.PLANT_TYPE)',
    capacity_units      COMMENT 'Maximum capacity units (T001W.CAPACITY_UNITS)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'PLANT',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'WMS',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'INTERNAL')
COMMENT = 'Governed plant entity, conformed from WMS T001W'
AS
SELECT WERKS, NAME1, LAND1, REGION_CD, PLANT_TYPE, CAPACITY_UNITS
FROM SUPPLY_CHAIN_FORGE.WMS_SOURCE.T001W;

-- 5. V_INVENTORY  <- WMS_SOURCE.MARD
CREATE OR REPLACE VIEW V_INVENTORY (
    inventory_key       COMMENT 'Snapshot key WERKS||MATNR||SNAP_DT (MARD.INV_KEY)',
    plant_id            COMMENT 'Plant ID -> V_PLANT (MARD.WERKS)',
    part_id             COMMENT 'Part ID -> V_PART (MARD.MATNR)',
    quantity_on_hand    WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.METRIC_FAMILY = 'INVENTORY')
                        COMMENT 'Gross stock on hand (MARD.LABST)',
    quantity_reserved   COMMENT 'Quantity reserved / in inspection (MARD.INSME)',
    reorder_point       COMMENT 'Safety stock reorder point (MARD.REORD_PT)',
    daily_usage         COMMENT 'Average daily usage (MARD.DAILY_USG)',
    snapshot_date       COMMENT 'Snapshot date (MARD.SNAP_DT)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'INVENTORY',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'WMS',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'INTERNAL')
COMMENT = 'Governed daily inventory snapshots, conformed from WMS MARD'
AS
SELECT INV_KEY, WERKS, MATNR, LABST, INSME, REORD_PT, DAILY_USG, SNAP_DT
FROM SUPPLY_CHAIN_FORGE.WMS_SOURCE.MARD;

-- 6. V_CUSTOMER  <- ERP_SOURCE.KNA1
CREATE OR REPLACE VIEW V_CUSTOMER (
    customer_id         COMMENT 'Customer ID (KNA1.KUNNR)',
    customer_name       WITH MASKING POLICY SUPPLY_CHAIN_FORGE.GOVERNED.MASK_CUSTOMER_PII
                        WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.PII = 'TRUE',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'CONFIDENTIAL')
                        COMMENT 'Customer company name, masked for buyers (KNA1.NAME1)',
    email               WITH MASKING POLICY SUPPLY_CHAIN_FORGE.GOVERNED.MASK_CUSTOMER_PII
                        WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.PII = 'TRUE',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'CONFIDENTIAL')
                        COMMENT 'Customer contact email, masked for buyers (KNA1.EMAIL)',
    country             COMMENT 'Country code, ISO 3-char (KNA1.LAND1)',
    region              COMMENT 'Region: APAC / EMEA / AMER (KNA1.REGIO)',
    customer_segment    COMMENT 'Segment: ENTERPRISE / MIDMARKET / SMB (KNA1.KTOKD)',
    credit_limit        WITH MASKING POLICY SUPPLY_CHAIN_FORGE.GOVERNED.MASK_CREDIT_LIMIT
                        WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'RESTRICTED')
                        COMMENT 'Credit limit USD, admin only (KNA1.KLIMK)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'CUSTOMER',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'ERP',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'CONFIDENTIAL')
COMMENT = 'Governed customer entity, conformed from ERP KNA1'
AS
SELECT KUNNR, NAME1, EMAIL, LAND1, REGIO, KTOKD, KLIMK
FROM SUPPLY_CHAIN_FORGE.ERP_SOURCE.KNA1;

-- 7. V_ORDER  <- ERP_SOURCE.VBAK
-- ERP ERDAT (ERP "promised" date) is deliberately NOT exposed: the only
-- authoritative promised date is V_SHIPMENT.promised_delivery_date (TMS).
-- Derived time dimensions (order_year/quarter/month/week, GAP-2) are
-- defined as semantic-view dimension expressions in B08, keeping this
-- view exactly as contract §7.
CREATE OR REPLACE VIEW V_ORDER (
    order_id            COMMENT 'Sales order ID (VBAK.VBELN)',
    customer_id         COMMENT 'Customer ID -> V_CUSTOMER (VBAK.KUNNR)',
    order_date          COMMENT 'Order document date (VBAK.AUDAT)',
    order_status        COMMENT 'Status: OPEN / SHIPPED / DELIVERED / CANCELLED (VBAK.GBSTK)',
    order_priority      COMMENT 'Priority: HIGH / NORMAL / LOW (VBAK.PRIO)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'ORDER',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'ERP',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'INTERNAL')
COMMENT = 'Governed sales order header, conformed from ERP VBAK. ERP promised date (ERDAT) intentionally excluded.'
AS
SELECT VBELN, KUNNR, AUDAT, GBSTK, PRIO
FROM SUPPLY_CHAIN_FORGE.ERP_SOURCE.VBAK;

-- 8. V_ORDER_LINE  <- ERP_SOURCE.VBAP
CREATE OR REPLACE VIEW V_ORDER_LINE (
    line_id             COMMENT 'Order line ID (VBAP.LINE_ID)',
    order_id            COMMENT 'Order ID -> V_ORDER (VBAP.VBELN)',
    part_id             COMMENT 'Part ID -> V_PART (VBAP.MATNR)',
    plant_id            COMMENT 'Fulfilling plant ID -> V_PLANT (VBAP.WERKS)',
    quantity_ordered    COMMENT 'Quantity ordered (VBAP.KWMENG)',
    quantity_shipped    WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.METRIC_FAMILY = 'FULFILLMENT')
                        COMMENT 'Quantity shipped, <= quantity_ordered (VBAP.QTY_SHIPPED)',
    unit_price          COMMENT 'Net selling price USD per unit (VBAP.NETPR)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'ORDER_LINE',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'ERP',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'INTERNAL')
COMMENT = 'Governed sales order lines, conformed from ERP VBAP'
AS
SELECT LINE_ID, VBELN, MATNR, WERKS, KWMENG, QTY_SHIPPED, NETPR
FROM SUPPLY_CHAIN_FORGE.ERP_SOURCE.VBAP;

-- 9. V_SHIPMENT  <- TMS_SOURCE.VTTK
-- promised_delivery_date is the TMS SLA date: the single authoritative
-- promised date for on-time delivery.
CREATE OR REPLACE VIEW V_SHIPMENT (
    shipment_id             COMMENT 'Shipment ID (VTTK.TKNUM)',
    order_id                COMMENT 'Order ID -> V_ORDER (VTTK.VBELN)',
    plant_id                COMMENT 'Origin plant ID -> V_PLANT (VTTK.WERKS)',
    carrier                 COMMENT 'Freight carrier (VTTK.CARRIER_CD)',
    ship_date               COMMENT 'Actual departure date (VTTK.DPTBG)',
    promised_delivery_date  WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.METRIC_FAMILY = 'DELIVERY')
                            COMMENT 'AUTHORITATIVE TMS promised delivery date (VTTK.PROM_DLV_DT)',
    actual_delivery_date    COMMENT 'Actual delivery date, NULL while in transit (VTTK.ACT_DLV_DT)',
    freight_cost            WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.METRIC_FAMILY = 'COST')
                            COMMENT 'Freight cost USD (VTTK.FREIGHT_AMT)',
    duty_cost               COMMENT 'Customs duty cost USD (VTTK.DUTY_AMT)',
    handling_cost           COMMENT 'Terminal handling cost USD (VTTK.HANDLING_AMT)',
    shipment_status         COMMENT 'Status: IN_TRANSIT / DELIVERED / DELAYED (VTTK.SHP_STATUS)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'SHIPMENT',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'TMS',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'INTERNAL')
COMMENT = 'Governed shipments, conformed from TMS VTTK. promised_delivery_date is the authoritative SLA date.'
AS
SELECT TKNUM, VBELN, WERKS, CARRIER_CD, DPTBG, PROM_DLV_DT, ACT_DLV_DT,
       FREIGHT_AMT, DUTY_AMT, HANDLING_AMT, SHP_STATUS
FROM SUPPLY_CHAIN_FORGE.TMS_SOURCE.VTTK;

-- 10. Grants: governed views are the only data path for persona roles
-- (they have no SELECT on source tables, so masking cannot be bypassed).
GRANT SELECT ON ALL VIEWS IN SCHEMA SUPPLY_CHAIN_FORGE.GOVERNED TO ROLE FORGE_ADMIN;
GRANT SELECT ON ALL VIEWS IN SCHEMA SUPPLY_CHAIN_FORGE.GOVERNED TO ROLE PLANNER_ROLE;
GRANT SELECT ON ALL VIEWS IN SCHEMA SUPPLY_CHAIN_FORGE.GOVERNED TO ROLE BUYER_ROLE;
GRANT SELECT ON ALL VIEWS IN SCHEMA SUPPLY_CHAIN_FORGE.GOVERNED TO ROLE LOGISTICS_ROLE;
