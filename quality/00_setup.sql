-- ============================================================================
-- quality/00_setup.sql — the check catalogue, valid-code tables, facts view and grants
-- Card:       C10 (.agents/tasks/claude/C10_data_quality.md)
-- Spec:       docs/DATA_SPEC.md §7.2 (DMF minimum set, status rules), §4 (codes, rates),
--             §5.1 (CONFORMED tables), docs/CONTRACT.md §4 (valid values)
-- Role:       ACCOUNTADMIN        Warehouse: FORGE_WH
-- Run order:  1 of 6 (00 → 10 → 20 → 30 → 40 → 99), after B08c (CONFORMED exists) and
--             after C08 has loaded the source tables. Re-runnable: IF NOT EXISTS, CREATE OR
--             REPLACE (catalogue, view), insert-if-missing (valid codes), idempotent grants.
-- Expected:   every statement succeeds. OPS.DQ_CHECKS has 77 rows (46 checks, 21 ROW_COUNT,
--             10 FRESHNESS), the 7 OPS.DQ_VALID_* tables hold 3, 4, 3, 3, 9, 6, 3 codes
--             SELECT * FROM SUPPLY_CHAIN_FORGE.OPS.V_CONFORMED_FACTS returns 9 rows.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS
  COMMENT = 'Private operations schema: data generator, data quality, evaluation, scale harness (FORGE_ADMIN only)';

-- ── Valid codes per domain (the M03 check) ────────────────────────────────────
-- The contract §4 values (carriers: DATA_SPEC §3.4). DMF_NONCONTRACT_CODE_COUNT counts the
-- values outside the table it is attached with. These tables are never replaced: DMF
-- associations point at them. New values are inserted if missing.

CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_REGION (CODE VARCHAR NOT NULL)
  COMMENT = 'C10: contract §4 region values';
INSERT INTO SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_REGION (CODE)
  SELECT v.column1 FROM (VALUES ('APAC'), ('EMEA'), ('AMER')) AS v
  WHERE v.column1 NOT IN (SELECT CODE FROM SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_REGION);

CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_ORDER_STATUS (CODE VARCHAR NOT NULL)
  COMMENT = 'C10: contract §4 order status values';
INSERT INTO SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_ORDER_STATUS (CODE)
  SELECT v.column1 FROM (VALUES ('OPEN'), ('SHIPPED'), ('DELIVERED'), ('CANCELLED')) AS v
  WHERE v.column1 NOT IN (SELECT CODE FROM SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_ORDER_STATUS);

CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_PRIORITY (CODE VARCHAR NOT NULL)
  COMMENT = 'C10: contract §4 order priority values';
INSERT INTO SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_PRIORITY (CODE)
  SELECT v.column1 FROM (VALUES ('HIGH'), ('NORMAL'), ('LOW')) AS v
  WHERE v.column1 NOT IN (SELECT CODE FROM SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_PRIORITY);

CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_SHIPMENT_STATUS (CODE VARCHAR NOT NULL)
  COMMENT = 'C10: contract §4 shipment status values';
INSERT INTO SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_SHIPMENT_STATUS (CODE)
  SELECT v.column1 FROM (VALUES ('IN_TRANSIT'), ('DELIVERED'), ('DELAYED')) AS v
  WHERE v.column1 NOT IN (SELECT CODE FROM SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_SHIPMENT_STATUS);

CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_CARRIER (CODE VARCHAR NOT NULL)
  COMMENT = 'C10: canonical carrier codes (DATA_SPEC §3.4)';
INSERT INTO SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_CARRIER (CODE)
  SELECT v.column1 FROM (VALUES ('DHL_EXPRESS'), ('FEDEX_FREIGHT'), ('MAERSK_LOGISTICS'), ('KUEHNE_NAGEL'),
                             ('DB_SCHENKER'), ('UPS_SUPPLY_CHAIN'), ('XPO_LOGISTICS'), ('CEVA_LOGISTICS'),
                             ('FLEXPORT')) AS v
  WHERE v.column1 NOT IN (SELECT CODE FROM SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_CARRIER);

CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_CATEGORY (CODE VARCHAR NOT NULL)
  COMMENT = 'C10: contract §4 part category values';
INSERT INTO SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_CATEGORY (CODE)
  SELECT v.column1 FROM (VALUES ('ELECTRONICS'), ('MECHANICAL'), ('RAW_MATERIAL'), ('PACKAGING'),
                             ('CHEMICAL'), ('FASTENERS')) AS v
  WHERE v.column1 NOT IN (SELECT CODE FROM SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_CATEGORY);

CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_SEGMENT (CODE VARCHAR NOT NULL)
  COMMENT = 'C10: contract §4 customer segment values';
INSERT INTO SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_SEGMENT (CODE)
  SELECT v.column1 FROM (VALUES ('ENTERPRISE'), ('MIDMARKET'), ('SMB')) AS v
  WHERE v.column1 NOT IN (SELECT CODE FROM SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_SEGMENT);

-- ── The check catalogue ───────────────────────────────────────────────────────
-- One row per DMF association. SP_ATTACH_DMFS attaches from it, SP_DATA_HEALTH judges by
-- it, SP_DQ_SELF_CHECKS tests by it. EXPECT:
--   ZERO      must be 0 (a CONFORMED repair or removal)           → FAIL otherwise
--   MAX_RATE  value / ROW_COUNT ≤ THRESHOLD_RATE (2 × the §4 rate) → WARN otherwise
--   INFO      a defect expected in raw data, always OK (shows the repair is needed)
--   VOLUME, FRESHNESS  attached for the app's Data health screen, not listed as checks
-- COLUMNS: the DMF's column arguments, in order. REF_TABLE/REF_COLUMN: the second table of
-- a two-table DMF (relative to the target database). DMF: 'OPS.<name>' for custom DMFs
-- (in the target database), else the system DMF's full name.

CREATE OR REPLACE TABLE SUPPLY_CHAIN_FORGE.OPS.DQ_CHECKS (
    CHECK_ID        VARCHAR       NOT NULL COMMENT 'Unique id, e.g. S_VTTK_E01',
    SORT_ORDER      NUMBER(4,0)   NOT NULL COMMENT 'Order within the entity (SOURCE first, then CONFORMED)',
    ENTITY          VARCHAR                COMMENT 'Semantic-view table name; NULL for FX and code-map tables',
    CHECK_NAME      VARCHAR       NOT NULL COMMENT 'Unique per table, e.g. missing_promised_date',
    CODE            VARCHAR                COMMENT 'DATA_SPEC §4 code, e.g. E01, M01/M02',
    LAYER           VARCHAR       NOT NULL COMMENT 'SOURCE or CONFORMED',
    SCHEMA_NAME     VARCHAR       NOT NULL,
    TABLE_NAME      VARCHAR       NOT NULL,
    DMF             VARCHAR       NOT NULL COMMENT 'SNOWFLAKE.CORE.<name> or OPS.<name>',
    COLUMNS         VARCHAR                COMMENT 'Column arguments, comma-separated; NULL = ON ()',
    REF_TABLE       VARCHAR                COMMENT 'Second table of a two-table DMF, e.g. ERP_SOURCE.VBAK',
    REF_COLUMN      VARCHAR,
    EXPECT          VARCHAR       NOT NULL COMMENT 'ZERO, MAX_RATE, INFO, VOLUME, FRESHNESS',
    TARGET_RATE     FLOAT                  COMMENT 'The §4 rate, where one is defined',
    THRESHOLD_RATE  FLOAT                  COMMENT 'MAX_RATE only: 2 × TARGET_RATE',
    HANDLED_BY      VARCHAR                COMMENT 'The rule, in one line, for users and the agent'
)
COMMENT = 'C10: data-quality check catalogue (DATA_SPEC §7.2). Drives SP_ATTACH_DMFS, SP_DATA_HEALTH, SP_DQ_SELF_CHECKS.';

INSERT INTO SUPPLY_CHAIN_FORGE.OPS.DQ_CHECKS
    (CHECK_ID, SORT_ORDER, ENTITY, CHECK_NAME, CODE, LAYER, SCHEMA_NAME, TABLE_NAME, DMF, COLUMNS,
     REF_TABLE, REF_COLUMN, EXPECT, TARGET_RATE, THRESHOLD_RATE, HANDLED_BY)
VALUES
    -- suppliers
    ('S_LFA1_M03_REGION',     10, 'suppliers', 'noncontract_region', 'M03', 'SOURCE', 'SRM_SOURCE', 'LFA1', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'REGIO', 'OPS.DQ_VALID_REGION', 'CODE', 'INFO', 0.08, NULL, 'Mapped to APAC, EMEA or AMER'),
    ('S_LFA1_M04',            11, 'suppliers', 'test_records', 'M04', 'SOURCE', 'SRM_SOURCE', 'LFA1', 'OPS.DMF_TEST_RECORD_COUNT', 'LIFNR, NAME1', NULL, NULL, 'INFO', NULL, NULL, 'Test suppliers and their sourcing removed'),
    ('C_SUPPLIER_M03_REGION', 20, 'suppliers', 'noncontract_region', 'M03', 'CONFORMED', 'CONFORMED', 'SUPPLIER', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'region', 'OPS.DQ_VALID_REGION', 'CODE', 'ZERO', NULL, NULL, 'Mapped to APAC, EMEA or AMER'),
    ('C_SUPPLIER_M04',        21, 'suppliers', 'test_records', 'M04', 'CONFORMED', 'CONFORMED', 'SUPPLIER', 'OPS.DMF_TEST_RECORD_COUNT', 'supplier_id, supplier_name', NULL, NULL, 'ZERO', NULL, NULL, 'Test suppliers and their sourcing removed'),
    -- parts
    ('S_MARA_M03_CATEGORY',   10, 'parts', 'noncontract_category', 'M03', 'SOURCE', 'SRM_SOURCE', 'MARA', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'MATKL', 'OPS.DQ_VALID_CATEGORY', 'CODE', 'INFO', 0.05, NULL, 'Mapped to the six contract categories'),
    ('S_MARA_M04',            11, 'parts', 'test_records', 'M04', 'SOURCE', 'SRM_SOURCE', 'MARA', 'OPS.DMF_TEST_RECORD_COUNT', 'MATNR, MAKTX', NULL, NULL, 'INFO', NULL, NULL, 'Test parts and their lines, sourcing and stock removed'),
    ('C_PART_M03_CATEGORY',   20, 'parts', 'noncontract_category', 'M03', 'CONFORMED', 'CONFORMED', 'PART', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'category', 'OPS.DQ_VALID_CATEGORY', 'CODE', 'ZERO', NULL, NULL, 'Mapped to the six contract categories'),
    ('C_PART_M04',            21, 'parts', 'test_records', 'M04', 'CONFORMED', 'CONFORMED', 'PART', 'OPS.DMF_TEST_RECORD_COUNT', 'part_id, part_name', NULL, NULL, 'ZERO', NULL, NULL, 'Test parts and their lines, sourcing and stock removed'),
    -- sourcing
    ('C_SOURCING_DUP',        20, 'sourcing', 'duplicate_keys', 'M01/M02', 'CONFORMED', 'CONFORMED', 'SOURCING', 'SNOWFLAKE.CORE.DUPLICATE_COUNT', 'source_id', NULL, NULL, 'ZERO', NULL, NULL, 'One row per key'),
    -- plants
    ('S_T001W_M03_REGION',    10, 'plants', 'noncontract_region', 'M03', 'SOURCE', 'WMS_SOURCE', 'T001W', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'REGION_CD', 'OPS.DQ_VALID_REGION', 'CODE', 'INFO', NULL, NULL, 'Mapped to APAC, EMEA or AMER'),
    ('C_PLANT_M03_REGION',    20, 'plants', 'noncontract_region', 'M03', 'CONFORMED', 'CONFORMED', 'PLANT', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'region', 'OPS.DQ_VALID_REGION', 'CODE', 'ZERO', NULL, NULL, 'Mapped to APAC, EMEA or AMER'),
    -- inventory
    ('S_MARD_DUP',            10, 'inventory', 'duplicate_keys', 'M01/M02', 'SOURCE', 'WMS_SOURCE', 'MARD', 'SNOWFLAKE.CORE.DUPLICATE_COUNT', 'INV_KEY', NULL, NULL, 'INFO', 0.005, NULL, 'One row per key: the latest load wins'),
    ('S_MARD_E05',            11, 'inventory', 'negative_on_hand', 'E05', 'SOURCE', 'WMS_SOURCE', 'MARD', 'OPS.DMF_NEGATIVE_ON_HAND_COUNT', 'LABST', NULL, NULL, 'MAX_RATE', 0.003, 0.006, 'Counted as 0 on hand'),
    ('C_INVENTORY_DUP',       20, 'inventory', 'duplicate_keys', 'M01/M02', 'CONFORMED', 'CONFORMED', 'INVENTORY', 'SNOWFLAKE.CORE.DUPLICATE_COUNT', 'inventory_key', NULL, NULL, 'ZERO', NULL, NULL, 'One row per key: the latest load wins'),
    ('C_INVENTORY_E05',       21, 'inventory', 'negative_on_hand', 'E05', 'CONFORMED', 'CONFORMED', 'INVENTORY', 'OPS.DMF_NEGATIVE_ON_HAND_COUNT', 'quantity_on_hand', NULL, NULL, 'ZERO', NULL, NULL, 'Counted as 0 on hand'),
    -- customers
    ('S_KNA1_DUP',            10, 'customers', 'duplicate_keys', 'M01/M02', 'SOURCE', 'ERP_SOURCE', 'KNA1', 'SNOWFLAKE.CORE.DUPLICATE_COUNT', 'KUNNR', NULL, NULL, 'INFO', 0.01, NULL, 'One row per key: the latest load wins'),
    ('S_KNA1_M03_REGION',     11, 'customers', 'noncontract_region', 'M03', 'SOURCE', 'ERP_SOURCE', 'KNA1', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'REGIO', 'OPS.DQ_VALID_REGION', 'CODE', 'INFO', 0.08, NULL, 'Mapped to APAC, EMEA or AMER'),
    ('S_KNA1_M03_SEGMENT',    12, 'customers', 'noncontract_segment', 'M03', 'SOURCE', 'ERP_SOURCE', 'KNA1', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'KTOKD', 'OPS.DQ_VALID_SEGMENT', 'CODE', 'INFO', 0.03, NULL, 'Mapped to ENTERPRISE, MIDMARKET or SMB'),
    ('S_KNA1_M04',            13, 'customers', 'test_records', 'M04', 'SOURCE', 'ERP_SOURCE', 'KNA1', 'OPS.DMF_TEST_RECORD_COUNT', 'KUNNR, NAME1', NULL, NULL, 'INFO', NULL, NULL, 'Test customers and their orders removed'),
    ('C_CUSTOMER_DUP',        20, 'customers', 'duplicate_keys', 'M01/M02', 'CONFORMED', 'CONFORMED', 'CUSTOMER', 'SNOWFLAKE.CORE.DUPLICATE_COUNT', 'customer_id', NULL, NULL, 'ZERO', NULL, NULL, 'One row per key: the latest load wins'),
    ('C_CUSTOMER_M03_REGION', 21, 'customers', 'noncontract_region', 'M03', 'CONFORMED', 'CONFORMED', 'CUSTOMER', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'region', 'OPS.DQ_VALID_REGION', 'CODE', 'ZERO', NULL, NULL, 'Mapped to APAC, EMEA or AMER'),
    ('C_CUSTOMER_M03_SEGMENT',22, 'customers', 'noncontract_segment', 'M03', 'CONFORMED', 'CONFORMED', 'CUSTOMER', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'customer_segment', 'OPS.DQ_VALID_SEGMENT', 'CODE', 'ZERO', NULL, NULL, 'Mapped to ENTERPRISE, MIDMARKET or SMB'),
    ('C_CUSTOMER_M04',        23, 'customers', 'test_records', 'M04', 'CONFORMED', 'CONFORMED', 'CUSTOMER', 'OPS.DMF_TEST_RECORD_COUNT', 'customer_id, customer_name', NULL, NULL, 'ZERO', NULL, NULL, 'Test customers and their orders removed'),
    -- orders
    ('S_VBAK_DUP',            10, 'orders', 'duplicate_keys', 'M01/M02', 'SOURCE', 'ERP_SOURCE', 'VBAK', 'SNOWFLAKE.CORE.DUPLICATE_COUNT', 'VBELN', NULL, NULL, 'INFO', 0.02, NULL, 'One row per key: the latest load wins'),
    ('S_VBAK_M03_STATUS',     11, 'orders', 'noncontract_order_status', 'M03', 'SOURCE', 'ERP_SOURCE', 'VBAK', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'GBSTK', 'OPS.DQ_VALID_ORDER_STATUS', 'CODE', 'INFO', 0.03, NULL, 'Mapped to OPEN, SHIPPED, DELIVERED or CANCELLED'),
    ('S_VBAK_M03_PRIORITY',   12, 'orders', 'noncontract_priority', 'M03', 'SOURCE', 'ERP_SOURCE', 'VBAK', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'PRIO', 'OPS.DQ_VALID_PRIORITY', 'CODE', 'INFO', 0.02, NULL, 'Mapped to HIGH, NORMAL or LOW'),
    ('C_SALES_ORDER_DUP',     20, 'orders', 'duplicate_keys', 'M01/M02', 'CONFORMED', 'CONFORMED', 'SALES_ORDER', 'SNOWFLAKE.CORE.DUPLICATE_COUNT', 'order_id', NULL, NULL, 'ZERO', NULL, NULL, 'One row per key: the latest load wins'),
    ('C_SALES_ORDER_M03_STATUS',   21, 'orders', 'noncontract_order_status', 'M03', 'CONFORMED', 'CONFORMED', 'SALES_ORDER', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'order_status', 'OPS.DQ_VALID_ORDER_STATUS', 'CODE', 'ZERO', NULL, NULL, 'Mapped to OPEN, SHIPPED, DELIVERED or CANCELLED'),
    ('C_SALES_ORDER_M03_PRIORITY', 22, 'orders', 'noncontract_priority', 'M03', 'CONFORMED', 'CONFORMED', 'SALES_ORDER', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'order_priority', 'OPS.DQ_VALID_PRIORITY', 'CODE', 'ZERO', NULL, NULL, 'Mapped to HIGH, NORMAL or LOW'),
    -- order_lines
    ('S_VBAP_DUP',            10, 'order_lines', 'duplicate_keys', 'M01/M02', 'SOURCE', 'ERP_SOURCE', 'VBAP', 'SNOWFLAKE.CORE.DUPLICATE_COUNT', 'LINE_ID', NULL, NULL, 'INFO', 0.015, NULL, 'One row per key: the latest load wins'),
    ('S_VBAP_E04',            11, 'order_lines', 'overshipment', 'E04', 'SOURCE', 'ERP_SOURCE', 'VBAP', 'OPS.DMF_OVERSHIP_COUNT', 'KWMENG, QTY_SHIPPED', NULL, NULL, 'MAX_RATE', 0.01, 0.02, 'Shipped quantity capped at the ordered quantity'),
    ('S_VBAP_E09A',           12, 'order_lines', 'orphan_order_lines', 'E09a', 'SOURCE', 'ERP_SOURCE', 'VBAP', 'OPS.DMF_ORPHAN_ORDER_LINES', 'VBELN', 'ERP_SOURCE.VBAK', 'VBELN', 'MAX_RATE', 0.002, 0.004, 'Dropped: no matching order'),
    ('C_ORDER_LINE_DUP',      20, 'order_lines', 'duplicate_keys', 'M01/M02', 'CONFORMED', 'CONFORMED', 'ORDER_LINE', 'SNOWFLAKE.CORE.DUPLICATE_COUNT', 'line_id', NULL, NULL, 'ZERO', NULL, NULL, 'One row per key: the latest load wins'),
    ('C_ORDER_LINE_E04',      21, 'order_lines', 'overshipment', 'E04', 'CONFORMED', 'CONFORMED', 'ORDER_LINE', 'OPS.DMF_OVERSHIP_COUNT', 'quantity_ordered, quantity_shipped', NULL, NULL, 'ZERO', NULL, NULL, 'Shipped quantity capped at the ordered quantity'),
    ('C_ORDER_LINE_E09A',     22, 'order_lines', 'orphan_order_lines', 'E09a', 'CONFORMED', 'CONFORMED', 'ORDER_LINE', 'OPS.DMF_ORPHAN_ORDER_LINES', 'order_id', 'CONFORMED.SALES_ORDER', 'order_id', 'ZERO', NULL, NULL, 'Dropped: no matching order'),
    -- shipments
    ('S_VTTK_DUP',            10, 'shipments', 'duplicate_keys', 'M01/M02', 'SOURCE', 'TMS_SOURCE', 'VTTK', 'SNOWFLAKE.CORE.DUPLICATE_COUNT', 'TKNUM', NULL, NULL, 'INFO', 0.03, NULL, 'One row per key: the latest load wins'),
    ('S_VTTK_M03_CARRIER',    11, 'shipments', 'noncontract_carrier', 'M03', 'SOURCE', 'TMS_SOURCE', 'VTTK', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'CARRIER_CD', 'OPS.DQ_VALID_CARRIER', 'CODE', 'INFO', 0.06, NULL, 'Mapped to the canonical carrier codes'),
    ('S_VTTK_M03_STATUS',     12, 'shipments', 'noncontract_shipment_status', 'M03', 'SOURCE', 'TMS_SOURCE', 'VTTK', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'SHP_STATUS', 'OPS.DQ_VALID_SHIPMENT_STATUS', 'CODE', 'INFO', 0.03, NULL, 'Mapped to IN_TRANSIT, DELIVERED or DELAYED'),
    ('S_VTTK_E01',            13, 'shipments', 'missing_promised_date', 'E01', 'SOURCE', 'TMS_SOURCE', 'VTTK', 'SNOWFLAKE.CORE.NULL_COUNT', 'PROM_DLV_DT', NULL, NULL, 'MAX_RATE', 0.008, 0.016, 'Excluded from on-time delivery'),
    ('S_VTTK_E09B',           14, 'shipments', 'orphan_shipments', 'E09b', 'SOURCE', 'TMS_SOURCE', 'VTTK', 'OPS.DMF_ORPHAN_SHIPMENTS', 'VBELN', 'ERP_SOURCE.VBAK', 'VBELN', 'MAX_RATE', 0.002, 0.004, 'Dropped: no matching order'),
    ('C_SHIPMENT_DUP',        20, 'shipments', 'duplicate_keys', 'M01/M02', 'CONFORMED', 'CONFORMED', 'SHIPMENT', 'SNOWFLAKE.CORE.DUPLICATE_COUNT', 'shipment_id', NULL, NULL, 'ZERO', NULL, NULL, 'One row per key: the latest load wins'),
    ('C_SHIPMENT_M03_CARRIER',21, 'shipments', 'noncontract_carrier', 'M03', 'CONFORMED', 'CONFORMED', 'SHIPMENT', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'carrier', 'OPS.DQ_VALID_CARRIER', 'CODE', 'ZERO', NULL, NULL, 'Mapped to the canonical carrier codes'),
    ('C_SHIPMENT_M03_STATUS', 22, 'shipments', 'noncontract_shipment_status', 'M03', 'CONFORMED', 'CONFORMED', 'SHIPMENT', 'OPS.DMF_NONCONTRACT_CODE_COUNT', 'shipment_status', 'OPS.DQ_VALID_SHIPMENT_STATUS', 'CODE', 'ZERO', NULL, NULL, 'Mapped to IN_TRANSIT, DELIVERED or DELAYED'),
    ('C_SHIPMENT_E01',        23, 'shipments', 'missing_promised_date', 'E01', 'CONFORMED', 'CONFORMED', 'SHIPMENT', 'SNOWFLAKE.CORE.NULL_COUNT', 'promised_delivery_date', NULL, NULL, 'MAX_RATE', 0.008, 0.016, 'Excluded from on-time delivery'),
    ('C_SHIPMENT_E09B',       24, 'shipments', 'orphan_shipments', 'E09b', 'CONFORMED', 'CONFORMED', 'SHIPMENT', 'OPS.DMF_ORPHAN_SHIPMENTS', 'order_id', 'CONFORMED.SALES_ORDER', 'order_id', 'ZERO', NULL, NULL, 'Dropped: no matching order'),
    ('C_SHIPMENT_E08',        25, 'shipments', 'cost_outliers', 'E08', 'CONFORMED', 'CONFORMED', 'SHIPMENT', 'OPS.DMF_COST_OUTLIER_COUNT', 'dq_flags', NULL, NULL, 'MAX_RATE', 0.001, 0.002, 'Costs set to unknown: excluded from average landed cost'),
    -- ROW_COUNT on every table (the denominator of each rate, the app's volume column)
    ('S_T001W_ROWS',    90, 'plants',      'row_count', NULL, 'SOURCE', 'WMS_SOURCE', 'T001W',    'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('S_LFA1_ROWS',     90, 'suppliers',   'row_count', NULL, 'SOURCE', 'SRM_SOURCE', 'LFA1',     'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('S_MARA_ROWS',     90, 'parts',       'row_count', NULL, 'SOURCE', 'SRM_SOURCE', 'MARA',     'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('S_SOURCING_ROWS', 90, 'sourcing',    'row_count', NULL, 'SOURCE', 'SRM_SOURCE', 'SOURCING', 'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('S_MARD_ROWS',     90, 'inventory',   'row_count', NULL, 'SOURCE', 'WMS_SOURCE', 'MARD',     'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('S_KNA1_ROWS',     90, 'customers',   'row_count', NULL, 'SOURCE', 'ERP_SOURCE', 'KNA1',     'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('S_VBAK_ROWS',     90, 'orders',      'row_count', NULL, 'SOURCE', 'ERP_SOURCE', 'VBAK',     'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('S_VBAP_ROWS',     90, 'order_lines', 'row_count', NULL, 'SOURCE', 'ERP_SOURCE', 'VBAP',     'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('S_TCURR_ROWS',    90, NULL,          'row_count', NULL, 'SOURCE', 'ERP_SOURCE', 'TCURR',    'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('S_VTTK_ROWS',     90, 'shipments',   'row_count', NULL, 'SOURCE', 'TMS_SOURCE', 'VTTK',     'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('C_SUPPLIER_ROWS',    91, 'suppliers',   'row_count', NULL, 'CONFORMED', 'CONFORMED', 'SUPPLIER',    'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('C_PART_ROWS',        91, 'parts',       'row_count', NULL, 'CONFORMED', 'CONFORMED', 'PART',        'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('C_SOURCING_ROWS',    91, 'sourcing',    'row_count', NULL, 'CONFORMED', 'CONFORMED', 'SOURCING',    'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('C_PLANT_ROWS',       91, 'plants',      'row_count', NULL, 'CONFORMED', 'CONFORMED', 'PLANT',       'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('C_INVENTORY_ROWS',   91, 'inventory',   'row_count', NULL, 'CONFORMED', 'CONFORMED', 'INVENTORY',   'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('C_CUSTOMER_ROWS',    91, 'customers',   'row_count', NULL, 'CONFORMED', 'CONFORMED', 'CUSTOMER',    'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('C_SALES_ORDER_ROWS', 91, 'orders',      'row_count', NULL, 'CONFORMED', 'CONFORMED', 'SALES_ORDER', 'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('C_ORDER_LINE_ROWS',  91, 'order_lines', 'row_count', NULL, 'CONFORMED', 'CONFORMED', 'ORDER_LINE',  'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('C_SHIPMENT_ROWS',    91, 'shipments',   'row_count', NULL, 'CONFORMED', 'CONFORMED', 'SHIPMENT',    'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('C_FX_RATE_ROWS',     91, NULL,          'row_count', NULL, 'CONFORMED', 'CONFORMED', 'FX_RATE',     'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    ('C_CODE_MAP_ROWS',    91, NULL,          'row_count', NULL, 'CONFORMED', 'CONFORMED', 'CODE_MAP',    'SNOWFLAKE.CORE.ROW_COUNT', NULL, NULL, NULL, 'VOLUME', NULL, NULL, NULL),
    -- FRESHNESS of the transactional tables: ON () = seconds since the table last changed
    -- (FRESHNESS has no TIMESTAMP_NTZ signature, and LOAD_TS is NTZ: B12 run fix)
    ('S_VBAK_FRESH',  95, 'orders',      'freshness', NULL, 'SOURCE', 'ERP_SOURCE', 'VBAK',  'SNOWFLAKE.CORE.FRESHNESS', NULL, NULL, NULL, 'FRESHNESS', NULL, NULL, NULL),
    ('S_VBAP_FRESH',  95, 'order_lines', 'freshness', NULL, 'SOURCE', 'ERP_SOURCE', 'VBAP',  'SNOWFLAKE.CORE.FRESHNESS', NULL, NULL, NULL, 'FRESHNESS', NULL, NULL, NULL),
    ('S_VTTK_FRESH',  95, 'shipments',   'freshness', NULL, 'SOURCE', 'TMS_SOURCE', 'VTTK',  'SNOWFLAKE.CORE.FRESHNESS', NULL, NULL, NULL, 'FRESHNESS', NULL, NULL, NULL),
    ('S_MARD_FRESH',  95, 'inventory',   'freshness', NULL, 'SOURCE', 'WMS_SOURCE', 'MARD',  'SNOWFLAKE.CORE.FRESHNESS', NULL, NULL, NULL, 'FRESHNESS', NULL, NULL, NULL),
    ('S_TCURR_FRESH', 95, NULL,          'freshness', NULL, 'SOURCE', 'ERP_SOURCE', 'TCURR', 'SNOWFLAKE.CORE.FRESHNESS', NULL, NULL, NULL, 'FRESHNESS', NULL, NULL, NULL),
    ('C_SALES_ORDER_FRESH', 96, 'orders',      'freshness', NULL, 'CONFORMED', 'CONFORMED', 'SALES_ORDER', 'SNOWFLAKE.CORE.FRESHNESS', NULL, NULL, NULL, 'FRESHNESS', NULL, NULL, NULL),
    ('C_ORDER_LINE_FRESH',  96, 'order_lines', 'freshness', NULL, 'CONFORMED', 'CONFORMED', 'ORDER_LINE',  'SNOWFLAKE.CORE.FRESHNESS', NULL, NULL, NULL, 'FRESHNESS', NULL, NULL, NULL),
    ('C_SHIPMENT_FRESH',    96, 'shipments',   'freshness', NULL, 'CONFORMED', 'CONFORMED', 'SHIPMENT',    'SNOWFLAKE.CORE.FRESHNESS', NULL, NULL, NULL, 'FRESHNESS', NULL, NULL, NULL),
    ('C_INVENTORY_FRESH',   96, 'inventory',   'freshness', NULL, 'CONFORMED', 'CONFORMED', 'INVENTORY',   'SNOWFLAKE.CORE.FRESHNESS', NULL, NULL, NULL, 'FRESHNESS', NULL, NULL, NULL),
    ('C_FX_RATE_FRESH',     96, NULL,          'freshness', NULL, 'CONFORMED', 'CONFORMED', 'FX_RATE',     'SNOWFLAKE.CORE.FRESHNESS', NULL, NULL, NULL, 'FRESHNESS', NULL, NULL, NULL);

-- ── Facts per CONFORMED table, aggregates only ────────────────────────────────
-- SP_DATA_HEALTH (owned by FORGE_ADMIN) reads this view, never the rows: FORGE_ADMIN gets
-- no SELECT on CONFORMED (unmasked) or on the source tables. COUNT(*) and MAX() on a
-- table are answered from micro-partition metadata, so the cost doesn't grow with the data.
-- Business date per table (DATA_SPEC §5.2, the as-of date is MAX(ship_date) of shipments).
CREATE OR REPLACE VIEW SUPPLY_CHAIN_FORGE.OPS.V_CONFORMED_FACTS
  COMMENT = 'C10: row count, latest load and latest business date per CONFORMED table (aggregates only)'
AS
SELECT 'suppliers' AS ENTITY, 'SUPPLIER' AS TABLE_NAME, COUNT(*) AS ROW_COUNT, MAX(load_ts) AS LATEST_LOAD_TS,
       NULL::DATE AS LATEST_BUSINESS_DATE FROM SUPPLY_CHAIN_FORGE.CONFORMED.SUPPLIER
UNION ALL
SELECT 'parts', 'PART', COUNT(*), MAX(load_ts), NULL::DATE FROM SUPPLY_CHAIN_FORGE.CONFORMED.PART
UNION ALL
SELECT 'sourcing', 'SOURCING', COUNT(*), MAX(load_ts), MAX(valid_from) FROM SUPPLY_CHAIN_FORGE.CONFORMED.SOURCING
UNION ALL
SELECT 'plants', 'PLANT', COUNT(*), MAX(load_ts), NULL::DATE FROM SUPPLY_CHAIN_FORGE.CONFORMED.PLANT
UNION ALL
SELECT 'inventory', 'INVENTORY', COUNT(*), MAX(load_ts), MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.CONFORMED.INVENTORY
UNION ALL
SELECT 'customers', 'CUSTOMER', COUNT(*), MAX(load_ts), NULL::DATE FROM SUPPLY_CHAIN_FORGE.CONFORMED.CUSTOMER
UNION ALL
SELECT 'orders', 'SALES_ORDER', COUNT(*), MAX(load_ts), MAX(order_date) FROM SUPPLY_CHAIN_FORGE.CONFORMED.SALES_ORDER
UNION ALL
SELECT 'order_lines', 'ORDER_LINE', COUNT(*), MAX(load_ts), NULL::DATE FROM SUPPLY_CHAIN_FORGE.CONFORMED.ORDER_LINE
UNION ALL
SELECT 'shipments', 'SHIPMENT', COUNT(*), MAX(load_ts), MAX(ship_date) FROM SUPPLY_CHAIN_FORGE.CONFORMED.SHIPMENT;

-- ── Grants ────────────────────────────────────────────────────────────────────
-- FORGE_ADMIN owns SP_DATA_HEALTH (owner's rights) and runs SP_DQ_SELF_CHECKS.
GRANT USAGE ON SCHEMA SUPPLY_CHAIN_FORGE.OPS TO ROLE FORGE_ADMIN;
GRANT SELECT ON TABLE SUPPLY_CHAIN_FORGE.OPS.DQ_CHECKS TO ROLE FORGE_ADMIN;
GRANT SELECT ON VIEW SUPPLY_CHAIN_FORGE.OPS.V_CONFORMED_FACTS TO ROLE FORGE_ADMIN;
-- The valid-code tables, in case the CONFORMED tables' owner is FORGE_ADMIN (a scheduled
-- two-table DMF reads its reference table as the monitored table's owner).
GRANT SELECT ON TABLE SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_REGION TO ROLE FORGE_ADMIN;
GRANT SELECT ON TABLE SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_ORDER_STATUS TO ROLE FORGE_ADMIN;
GRANT SELECT ON TABLE SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_PRIORITY TO ROLE FORGE_ADMIN;
GRANT SELECT ON TABLE SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_SHIPMENT_STATUS TO ROLE FORGE_ADMIN;
GRANT SELECT ON TABLE SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_CARRIER TO ROLE FORGE_ADMIN;
GRANT SELECT ON TABLE SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_CATEGORY TO ROLE FORGE_ADMIN;
GRANT SELECT ON TABLE SUPPLY_CHAIN_FORGE.OPS.DQ_VALID_SEGMENT TO ROLE FORGE_ADMIN;
-- Read SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS (also what the app's Data health screen reads).
GRANT APPLICATION ROLE SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER TO ROLE FORGE_ADMIN;
-- Scheduled DMFs run as the table owner, which needs these (DMF reference §10). The source
-- tables are ACCOUNTADMIN's, the CONFORMED dynamic tables may be FORGE_ADMIN's (B08c).
GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE ACCOUNTADMIN;
GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE FORGE_ADMIN;
GRANT DATABASE ROLE SNOWFLAKE.DATA_METRIC_USER TO ROLE ACCOUNTADMIN;
GRANT DATABASE ROLE SNOWFLAKE.DATA_METRIC_USER TO ROLE FORGE_ADMIN;
