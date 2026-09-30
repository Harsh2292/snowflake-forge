-- ============================================================
-- 03_governed_views.sql — Governed Layer: 9 Business Views on CONFORMED
-- Task: B07, re-pointed at B08c (CR-006)
-- Owner: CoCo
-- Schema: SUPPLY_CHAIN_FORGE.GOVERNED
-- Run as: ACCOUNTADMIN (owns CONFORMED, persona roles have no SELECT on
--         CONFORMED or SOURCE, so views must be owned here)
-- Run after: 04_governance/06_conformed_layer.sql
-- ============================================================
-- Masking policies and tags are attached INLINE, so each view is created
-- in one atomic statement: a view never exists unmasked, and re-running
-- CREATE OR REPLACE cannot silently drop a policy.
-- Column names and order are exactly docs/CONTRACT.md §7. Masking is exactly §6.
-- Since B08c the views read CONFORMED (deduplicated, standardized, in-scope,
-- USD: DATA_SPEC §5.1), not SOURCE. The column comments keep the source
-- lineage. SEMANTIC_ROLE says how the semantic view may use each column
-- (masked and PII columns are EXCLUDE).
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SUPPLY_CHAIN_FORGE;
USE SCHEMA GOVERNED;

-- 1. V_SUPPLIER  <- CONFORMED.SUPPLIER (SRM LFA1)
CREATE OR REPLACE VIEW V_SUPPLIER (
    supplier_id         WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                        COMMENT 'Supplier ID (LFA1.LIFNR)',
    supplier_name       WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Supplier name (LFA1.NAME1)',
    country             WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Country code, ISO 3-char (LFA1.LAND1)',
    region              WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Region: APAC / EMEA / AMER (LFA1.REGIO, standardized)',
    supplier_tier       WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Supplier tier 1-3 (LFA1.SUPP_TIER)',
    lead_time_days      WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'FACT')
                        COMMENT 'Average lead time in days (LFA1.LEAD_TM_DAYS)',
    reliability_score   WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'FACT')
                        COMMENT 'Reliability score 0.00-1.00 (LFA1.RELIAB_SCR)',
    payment_terms       WITH MASKING POLICY SUPPLY_CHAIN_FORGE.GOVERNED.MASK_PAYMENT_TERMS
                        WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'RESTRICTED',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'EXCLUDE')
                        COMMENT 'Commercial payment terms, masked for non-buyers (LFA1.ZTERM)',
    email               WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.PII = 'TRUE',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'CONFIDENTIAL',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'EXCLUDE')
                        COMMENT 'Supplier contact email (LFA1.EMAIL)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'SUPPLIER',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'SRM',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'CONFIDENTIAL')
COMMENT = 'Governed supplier entity, from CONFORMED.SUPPLIER (SRM LFA1: deduplicated, standardized, test vendors removed)'
AS
SELECT supplier_id, supplier_name, country, region, supplier_tier, lead_time_days,
       reliability_score, payment_terms, email
FROM SUPPLY_CHAIN_FORGE.CONFORMED.SUPPLIER;

-- 2. V_PART  <- CONFORMED.PART (SRM MARA)
CREATE OR REPLACE VIEW V_PART (
    part_id             WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                        COMMENT 'Part ID (MARA.MATNR)',
    part_name           WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Part description (MARA.MAKTX)',
    category            WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Material category (MARA.MATKL, standardized)',
    subcategory         WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Material subcategory (MARA.SUBCAT)',
    unit_cost           WITH MASKING POLICY SUPPLY_CHAIN_FORGE.GOVERNED.MASK_SUPPLIER_COST
                        WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'RESTRICTED',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.METRIC_FAMILY = 'COST',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'EXCLUDE')
                        COMMENT 'Standard unit cost USD, masked for non-buyers (MARA.STPRS)',
    weight_kg           WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'FACT')
                        COMMENT 'Gross weight in kg (MARA.BRGEW)',
    is_critical         WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Critical component flag (MARA.CRIT_FLG)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'PART',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'SRM',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'INTERNAL')
COMMENT = 'Governed part entity, from CONFORMED.PART (SRM MARA: deduplicated, standardized, test parts removed)'
AS
SELECT part_id, part_name, category, subcategory, unit_cost, weight_kg, is_critical
FROM SUPPLY_CHAIN_FORGE.CONFORMED.PART;

-- 3. V_SOURCING  <- CONFORMED.SOURCING (SRM SOURCING)
-- Only the source-list rows valid today (DATA_SPEC §5.1), so each part has
-- exactly one current primary supplier. The validity history stays in CONFORMED.
CREATE OR REPLACE VIEW V_SOURCING (
    source_id           WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                        COMMENT 'Sourcing record ID (SOURCING.SOURCE_ID)',
    supplier_id         WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                        COMMENT 'Supplier ID -> V_SUPPLIER (SOURCING.LIFNR)',
    part_id             WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                        COMMENT 'Part ID -> V_PART (SOURCING.MATNR)',
    is_primary          WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Primary sourcing flag, one primary per part (SOURCING.IS_PRIMARY)',
    contract_price      WITH MASKING POLICY SUPPLY_CHAIN_FORGE.GOVERNED.MASK_SUPPLIER_COST
                        WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'RESTRICTED',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.METRIC_FAMILY = 'COST',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'EXCLUDE')
                        COMMENT 'Contracted unit price USD, masked for non-buyers (SOURCING.CONTRACT_PRICE in WAERS, converted)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'SOURCING',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'SRM',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'RESTRICTED')
COMMENT = 'Governed supplier-to-part sourcing contracts valid today, from CONFORMED.SOURCING (SRM SOURCING)'
AS
SELECT source_id, supplier_id, part_id, is_primary, contract_price
FROM SUPPLY_CHAIN_FORGE.CONFORMED.SOURCING
WHERE valid_from <= CURRENT_DATE()
  AND (valid_to IS NULL OR valid_to >= CURRENT_DATE());

-- 4. V_PLANT  <- CONFORMED.PLANT (WMS T001W)
CREATE OR REPLACE VIEW V_PLANT (
    plant_id            WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                        COMMENT 'Plant ID (T001W.WERKS)',
    plant_name          WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Plant / facility name (T001W.NAME1)',
    country             WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Country code, ISO 3-char (T001W.LAND1)',
    region              WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Region: APAC / EMEA / AMER (T001W.REGION_CD, standardized)',
    plant_type          WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Facility type: MFG / DC / HUB (T001W.PLANT_TYPE)',
    capacity_units      WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'FACT')
                        COMMENT 'Maximum capacity units (T001W.CAPACITY_UNITS)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'PLANT',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'WMS',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'INTERNAL')
COMMENT = 'Governed plant entity, from CONFORMED.PLANT (WMS T001W: standardized)'
AS
SELECT plant_id, plant_name, country, region, plant_type, capacity_units
FROM SUPPLY_CHAIN_FORGE.CONFORMED.PLANT;

-- 5. V_INVENTORY  <- CONFORMED.INVENTORY (WMS MARD)
CREATE OR REPLACE VIEW V_INVENTORY (
    inventory_key       WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                        COMMENT 'Snapshot key WERKS-MATNR-YYYYMMDD (MARD.INV_KEY)',
    plant_id            WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                        COMMENT 'Plant ID -> V_PLANT (MARD.WERKS)',
    part_id             WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                        COMMENT 'Part ID -> V_PART (MARD.MATNR)',
    quantity_on_hand    WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.METRIC_FAMILY = 'INVENTORY',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'FACT')
                        COMMENT 'Gross stock on hand, negative source values floored at 0 (MARD.LABST)',
    quantity_reserved   WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'FACT')
                        COMMENT 'Quantity reserved / in inspection (MARD.INSME)',
    reorder_point       WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'FACT')
                        COMMENT 'Safety stock reorder point (MARD.REORD_PT)',
    daily_usage         WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'FACT')
                        COMMENT 'Average daily usage (MARD.DAILY_USG)',
    snapshot_date       WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Snapshot date: weekly, daily for the last 90 days (MARD.SNAP_DT)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'INVENTORY',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'WMS',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'INTERNAL')
COMMENT = 'Governed inventory snapshots, from CONFORMED.INVENTORY (WMS MARD: deduplicated, test parts removed)'
AS
SELECT inventory_key, plant_id, part_id, quantity_on_hand, quantity_reserved,
       reorder_point, daily_usage, snapshot_date
FROM SUPPLY_CHAIN_FORGE.CONFORMED.INVENTORY;

-- 6. V_CUSTOMER  <- CONFORMED.CUSTOMER (ERP KNA1)
CREATE OR REPLACE VIEW V_CUSTOMER (
    customer_id         WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                        COMMENT 'Customer ID (KNA1.KUNNR)',
    customer_name       WITH MASKING POLICY SUPPLY_CHAIN_FORGE.GOVERNED.MASK_CUSTOMER_PII
                        WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.PII = 'TRUE',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'CONFIDENTIAL',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'EXCLUDE')
                        COMMENT 'Customer company name, masked for buyers (KNA1.NAME1)',
    email               WITH MASKING POLICY SUPPLY_CHAIN_FORGE.GOVERNED.MASK_CUSTOMER_PII
                        WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.PII = 'TRUE',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'CONFIDENTIAL',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'EXCLUDE')
                        COMMENT 'Customer contact email, masked for buyers (KNA1.EMAIL)',
    country             WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Country code, ISO 3-char (KNA1.LAND1)',
    region              WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Region: APAC / EMEA / AMER (KNA1.REGIO, standardized)',
    customer_segment    WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Segment: ENTERPRISE / MIDMARKET / SMB (KNA1.KTOKD, standardized)',
    credit_limit        WITH MASKING POLICY SUPPLY_CHAIN_FORGE.GOVERNED.MASK_CREDIT_LIMIT
                        WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'RESTRICTED',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'EXCLUDE')
                        COMMENT 'Credit limit USD, admin only (KNA1.KLIMK)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'CUSTOMER',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'ERP',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'CONFIDENTIAL')
COMMENT = 'Governed customer entity, from CONFORMED.CUSTOMER (ERP KNA1: deduplicated, standardized, test accounts removed)'
AS
SELECT customer_id, customer_name, email, country, region, customer_segment, credit_limit
FROM SUPPLY_CHAIN_FORGE.CONFORMED.CUSTOMER;

-- 7. V_ORDER  <- CONFORMED.SALES_ORDER (ERP VBAK)
-- ERP ERDAT (ERP "promised" date) is deliberately NOT exposed (it never
-- reaches CONFORMED): the only authoritative promised date is
-- V_SHIPMENT.promised_delivery_date (TMS). Derived time dimensions
-- (order_year/quarter/month/week, GAP-2) live in the semantic view.
CREATE OR REPLACE VIEW V_ORDER (
    order_id            WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                        COMMENT 'Sales order ID (VBAK.VBELN)',
    customer_id         WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                        COMMENT 'Customer ID -> V_CUSTOMER (VBAK.KUNNR)',
    order_date          WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Order document date (VBAK.AUDAT)',
    order_status        WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Status: OPEN / SHIPPED / DELIVERED / CANCELLED, latest version (VBAK.GBSTK, standardized)',
    order_priority      WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                        COMMENT 'Priority: HIGH / NORMAL / LOW (VBAK.PRIO, standardized)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'ORDER',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'ERP',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'INTERNAL')
COMMENT = 'Governed sales order header, from CONFORMED.SALES_ORDER (ERP VBAK: standard orders only, no returns or test orders). ERP promised date (ERDAT) intentionally excluded.'
AS
SELECT order_id, customer_id, order_date, order_status, order_priority
FROM SUPPLY_CHAIN_FORGE.CONFORMED.SALES_ORDER;

-- 8. V_ORDER_LINE  <- CONFORMED.ORDER_LINE (ERP VBAP)
CREATE OR REPLACE VIEW V_ORDER_LINE (
    line_id             WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                        COMMENT 'Order line ID (VBAP.LINE_ID)',
    order_id            WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                        COMMENT 'Order ID -> V_ORDER (VBAP.VBELN)',
    part_id             WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                        COMMENT 'Part ID -> V_PART (VBAP.MATNR)',
    plant_id            WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                        COMMENT 'Fulfilling plant ID -> V_PLANT (VBAP.WERKS)',
    quantity_ordered    WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'FACT')
                        COMMENT 'Quantity ordered (VBAP.KWMENG)',
    quantity_shipped    WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.METRIC_FAMILY = 'FULFILLMENT',
                                  SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'FACT')
                        COMMENT 'Quantity shipped, capped at quantity_ordered (VBAP.QTY_SHIPPED)',
    unit_price          WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'FACT')
                        COMMENT 'Net selling price USD per unit (VBAP.NETPR in VBAK.WAERK, converted at the order date)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'ORDER_LINE',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'ERP',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'INTERNAL')
COMMENT = 'Governed sales order lines, from CONFORMED.ORDER_LINE (ERP VBAP: in-scope orders only, USD)'
AS
SELECT line_id, order_id, part_id, plant_id, quantity_ordered, quantity_shipped, unit_price
FROM SUPPLY_CHAIN_FORGE.CONFORMED.ORDER_LINE;

-- 9. V_SHIPMENT  <- CONFORMED.SHIPMENT (TMS VTTK)
-- promised_delivery_date is the TMS SLA date: the single authoritative
-- promised date for on-time delivery (NULL on a few rows: excluded from OTD).
CREATE OR REPLACE VIEW V_SHIPMENT (
    shipment_id             WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                            COMMENT 'Shipment ID (VTTK.TKNUM)',
    order_id                WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                            COMMENT 'Order ID -> V_ORDER (VTTK.VBELN)',
    plant_id                WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'KEY')
                            COMMENT 'Origin plant ID -> V_PLANT (VTTK.WERKS)',
    carrier                 WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                            COMMENT 'Freight carrier (VTTK.CARRIER_CD, standardized)',
    ship_date               WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                            COMMENT 'Actual departure date (VTTK.DPTBG)',
    promised_delivery_date  WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.METRIC_FAMILY = 'DELIVERY',
                                      SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                            COMMENT 'AUTHORITATIVE TMS promised delivery date (VTTK.PROM_DLV_DT)',
    actual_delivery_date    WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                            COMMENT 'Actual delivery date, NULL while in transit (VTTK.ACT_DLV_DT)',
    freight_cost            WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.METRIC_FAMILY = 'COST',
                                      SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'FACT')
                            COMMENT 'Freight cost USD, NULL if unknown or an outlier (VTTK.FREIGHT_AMT in WAERS, converted)',
    duty_cost               WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'FACT')
                            COMMENT 'Customs duty cost USD, missing = 0 (VTTK.DUTY_AMT in WAERS, converted)',
    handling_cost           WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'FACT')
                            COMMENT 'Terminal handling cost USD, missing = 0 (VTTK.HANDLING_AMT in WAERS, converted)',
    shipment_status         WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE = 'DIMENSION')
                            COMMENT 'Status: IN_TRANSIT / DELIVERED / DELAYED, latest version (VTTK.SHP_STATUS, standardized)'
)
WITH TAG (SUPPLY_CHAIN_FORGE.GOVERNED.ENTITY_TYPE = 'SHIPMENT',
          SUPPLY_CHAIN_FORGE.GOVERNED.SOURCE_SYSTEM = 'TMS',
          SUPPLY_CHAIN_FORGE.GOVERNED.SENSITIVITY = 'INTERNAL')
COMMENT = 'Governed shipments, from CONFORMED.SHIPMENT (TMS VTTK: latest version, in-scope orders, USD). promised_delivery_date is the authoritative SLA date.'
AS
SELECT shipment_id, order_id, plant_id, carrier, ship_date, promised_delivery_date,
       actual_delivery_date, freight_cost, duty_cost, handling_cost, shipment_status
FROM SUPPLY_CHAIN_FORGE.CONFORMED.SHIPMENT;

-- 10. Grants: governed views are the only data path for persona roles
-- (they have no SELECT on CONFORMED or SOURCE, so masking cannot be bypassed).
GRANT SELECT ON ALL VIEWS IN SCHEMA SUPPLY_CHAIN_FORGE.GOVERNED TO ROLE FORGE_ADMIN;
GRANT SELECT ON ALL VIEWS IN SCHEMA SUPPLY_CHAIN_FORGE.GOVERNED TO ROLE PLANNER_ROLE;
GRANT SELECT ON ALL VIEWS IN SCHEMA SUPPLY_CHAIN_FORGE.GOVERNED TO ROLE BUYER_ROLE;
GRANT SELECT ON ALL VIEWS IN SCHEMA SUPPLY_CHAIN_FORGE.GOVERNED TO ROLE LOGISTICS_ROLE;
