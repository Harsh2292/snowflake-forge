-- ============================================================
-- 06_conformed_layer.sql — CONFORMED: the cleansing layer (CR-006)
-- Task: B08c · Spec: docs/DATA_SPEC.md §4 (mess catalogue) and §5.1 (CONFORMED contract)
-- Owner: CoCo
-- Run as: ACCOUNTADMIN (owns the source tables), warehouse FORGE_WH.
-- Run after: 01_setup/03_schemas_v2.sql, 02_tables/05_source_v2.sql, the C08 load.
-- Run before: 03_governed_views.sql (the views read these tables).
-- ============================================================
-- A CONFORMED row is in scope, unique, standardized and in USD (§5.1):
--   M01/M02  one row per normalized key, the latest LOAD_TS wins (deduped
--            BEFORE any filter, so an older version is never judged on its own)
--   M03      every coded column through CODE_MAP (keyed on UPPER(TRIM(raw)))
--   M04      test masters dropped by rule, dependents drop via the inner joins
--   M05      amounts to USD at the business date via FX_RATE (equality join)
--   M07      UPPER(TRIM()) on every ID before any join
--   E03 returns, E09 orphans, E12 future-dated orders: dropped
--   E01, E02, E04–E08, E11: rule applied, row kept, flag in dq_flags
--   VBAK.ERDAT (the ERP promised date, E10) is never carried.
-- Every dynamic table is REFRESH_MODE = INCREMENTAL: creation fails if a
-- query can't refresh incrementally, so "incremental" is proven at build time.
-- Only incremental-safe constructs are used: QUALIFY ROW_NUMBER() = 1,
-- window functions with PARTITION BY, inner joins, equality outer joins.
-- TARGET_LAG = '1 day': the demo data is static, C12 measures refresh at scale.
-- dq_flags values: ID_NORMALIZED, CODE_STANDARDIZED, UNMAPPED_CODE (a bug if
-- ever non-zero), MISSING_PROMISED_DATE (E01), ORDER_CANCELLED_AFTER_SHIPPING
-- (E02), OVERSHIP_CAPPED (E04), NEG_ON_HAND_ZEROED (E05), ZERO_USAGE (E06),
-- DUTY_DEFAULTED (E07a), HANDLING_DEFAULTED (E07b), COST_UNKNOWN (E07c),
-- COST_OUTLIER (E08), PRIMARY_SUPERSEDED (E11), FX_MISSING (no USD rate for
-- the currency on the business date; the USD amount is NULL).
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE FORGE_WH;

-- ── 1. CODE_MAP (static): §4.3 variants -> contract values ──────────────────
-- Canonical values map to themselves. VARIANT is UPPER(TRIM(raw)).
CREATE OR REPLACE TABLE SUPPLY_CHAIN_FORGE.CONFORMED.CODE_MAP (
    DOMAIN      VARCHAR(20) NOT NULL COMMENT 'Code domain (DATA_SPEC §4.3)',
    VARIANT     VARCHAR(40) NOT NULL COMMENT 'UPPER(TRIM(raw value)) as it appears in SOURCE',
    CANONICAL   VARCHAR(30) NOT NULL COMMENT 'Contract (§4) value',
    CONSTRAINT PK_CODE_MAP PRIMARY KEY (DOMAIN, VARIANT)
) CHANGE_TRACKING = TRUE
  COMMENT = 'M03 code map: every raw code variant and its contract value (DATA_SPEC §4.3)'
AS
WITH src (DOMAIN, CANONICAL, VARIANTS) AS (
    SELECT * FROM VALUES
        ('REGION',          'APAC',             'Apac|apac |ASIA-PAC|Asia Pacific'),
        ('REGION',          'EMEA',             'emea| EMEA|Europe|EU'),
        ('REGION',          'AMER',             'Amer|NA|North America|Americas'),
        ('ORDER_STATUS',    'OPEN',             'Open|OPN'),
        ('ORDER_STATUS',    'SHIPPED',          'Shipped|SHP'),
        ('ORDER_STATUS',    'DELIVERED',        'Delivered|DLV|delivered '),
        ('ORDER_STATUS',    'CANCELLED',        'Cancelled|CANCELED|CNL'),
        ('PRIORITY',        'HIGH',             'High|H|URGENT'),
        ('PRIORITY',        'NORMAL',           'Normal|MED|MEDIUM'),
        ('PRIORITY',        'LOW',              'Low|L'),
        ('SHIPMENT_STATUS', 'IN_TRANSIT',       'In Transit|IN-TRANSIT|INTRANSIT'),
        ('SHIPMENT_STATUS', 'DELIVERED',        'Delivered|DLV'),
        ('SHIPMENT_STATUS', 'DELAYED',          'Delayed|LATE'),
        ('CARRIER',         'DHL_EXPRESS',      'DHL|DHL Express|dhl_express'),
        ('CARRIER',         'FEDEX_FREIGHT',    'FedEx|FEDEX FREIGHT'),
        ('CARRIER',         'MAERSK_LOGISTICS', 'Maersk|MAERSK'),
        ('CARRIER',         'KUEHNE_NAGEL',     'K+N|Kuehne+Nagel|KUEHNE + NAGEL'),
        ('CARRIER',         'DB_SCHENKER',      'DB Schenker|SCHENKER'),
        ('CARRIER',         'UPS_SUPPLY_CHAIN', 'UPS|UPS SCS'),
        ('CARRIER',         'XPO_LOGISTICS',    'XPO'),
        ('CARRIER',         'CEVA_LOGISTICS',   'CEVA'),
        ('CARRIER',         'FLEXPORT',         'Flexport'),
        ('CATEGORY',        'ELECTRONICS',      'Electronics|ELECTRONIC'),
        ('CATEGORY',        'MECHANICAL',       'Mechanical|MECH'),
        ('CATEGORY',        'RAW_MATERIAL',     'RAW MATERIAL|Raw-Material|RAW_MATERIALS'),
        ('CATEGORY',        'PACKAGING',        'Packaging|PKG'),
        ('CATEGORY',        'CHEMICAL',         'Chemical|CHEMICALS'),
        ('CATEGORY',        'FASTENERS',        'Fasteners |FASTENER'),
        ('SEGMENT',         'ENTERPRISE',       'Enterprise|ENT'),
        ('SEGMENT',         'MIDMARKET',        'MID-MARKET|Mid Market|MM'),
        ('SEGMENT',         'SMB',              'Small Business|smb'))
SELECT DISTINCT DOMAIN, UPPER(TRIM(v.value::VARCHAR)), CANONICAL
FROM src, LATERAL FLATTEN(input => SPLIT(VARIANTS, '|')) v
UNION
SELECT DISTINCT DOMAIN, CANONICAL, CANONICAL FROM src;

-- ── 2. CALENDAR (static): one row per day, for the FX carry-forward ─────────
CREATE OR REPLACE TABLE SUPPLY_CHAIN_FORGE.CONFORMED.CALENDAR (
    CAL_DATE DATE NOT NULL COMMENT 'Calendar day',
    CONSTRAINT PK_CALENDAR PRIMARY KEY (CAL_DATE)
) CHANGE_TRACKING = TRUE
  COMMENT = 'Every day 2016-01-01 to 2030-12-31 (covers the 10-year history plus headroom)'
AS
SELECT DATEADD(day, ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2016-01-01'::DATE)
FROM TABLE(GENERATOR(ROWCOUNT => 5479));

-- ── 3. FX_RATE: USD per unit, per currency, per day (M05) ───────────────────
-- The latest TCURR rate on or before each day (LAST_VALUE ... IGNORE NULLS,
-- carried forward over weekends and holidays). USD = 1. Facts join it on
-- (currency, date) equality, which stays incremental and never fans out.
CREATE OR REPLACE DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.FX_RATE
    TARGET_LAG = '1 day' WAREHOUSE = FORGE_WH REFRESH_MODE = INCREMENTAL
    COMMENT = 'Daily USD rate per currency: latest ERP_SOURCE.TCURR rate on or before the day, USD = 1'
AS
WITH t AS (
    SELECT UPPER(TRIM(FCURR)) AS currency, GDATU AS rate_date, UKURS
    FROM SUPPLY_CHAIN_FORGE.ERP_SOURCE.TCURR
    WHERE UPPER(TRIM(KURST)) = 'M' AND UPPER(TRIM(TCURR)) = 'USD'
      AND UPPER(TRIM(FCURR)) <> 'USD'   -- USD comes only from the UNION ALL row below
    QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(FCURR)), GDATU ORDER BY LOAD_TS DESC) = 1),
c AS (SELECT DISTINCT currency FROM t),
g AS (
    SELECT c.currency, cal.CAL_DATE, t.UKURS
    FROM c
    CROSS JOIN SUPPLY_CHAIN_FORGE.CONFORMED.CALENDAR cal
    LEFT JOIN t ON t.currency = c.currency AND t.rate_date = cal.CAL_DATE)
SELECT currency::VARCHAR(3) AS currency,
       CAL_DATE AS rate_date,
       LAST_VALUE(UKURS IGNORE NULLS) OVER (PARTITION BY currency ORDER BY CAL_DATE
                                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)::NUMBER(18,9) AS usd_rate
FROM g
UNION ALL
SELECT 'USD'::VARCHAR(3), CAL_DATE, 1::NUMBER(18,9) FROM SUPPLY_CHAIN_FORGE.CONFORMED.CALENDAR;

-- ── 4. Masters ──────────────────────────────────────────────────────────────
-- Test-master rule (M04): the ID starts TEST (or MAT9999 for parts), or the
-- name is TEST/DUMMY as a word at the start, or contains DO NOT USE.
-- (Snowflake regex has no \b, '([^A-Z0-9_].*)?' is the word boundary.)

CREATE OR REPLACE DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.SUPPLIER
    TARGET_LAG = '1 day' WAREHOUSE = FORGE_WH REFRESH_MODE = INCREMENTAL
    COMMENT = 'Clean suppliers (from SRM_SOURCE.LFA1): deduped, region standardized, test vendors removed'
AS
WITH s AS (
    SELECT LIFNR, NAME1, LAND1, REGIO, SUPP_TIER, LEAD_TM_DAYS, RELIAB_SCR, ZTERM, EMAIL, LOAD_TS
    FROM SUPPLY_CHAIN_FORGE.SRM_SOURCE.LFA1
    QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(LIFNR)) ORDER BY LOAD_TS DESC, LIFNR) = 1),
r AS (SELECT VARIANT, CANONICAL FROM SUPPLY_CHAIN_FORGE.CONFORMED.CODE_MAP WHERE DOMAIN = 'REGION')
SELECT UPPER(TRIM(s.LIFNR))::VARCHAR(10)                     AS supplier_id,
       s.NAME1::VARCHAR(100)                                 AS supplier_name,
       UPPER(TRIM(s.LAND1))::VARCHAR(3)                      AS country,
       COALESCE(r.CANONICAL, UPPER(TRIM(s.REGIO)))::VARCHAR(20) AS region,
       s.SUPP_TIER                                           AS supplier_tier,
       s.LEAD_TM_DAYS                                        AS lead_time_days,
       s.RELIAB_SCR                                          AS reliability_score,
       s.ZTERM::VARCHAR(20)                                  AS payment_terms,
       s.EMAIL::VARCHAR(100)                                 AS email,
       ARRAY_COMPACT(ARRAY_CONSTRUCT(
           IFF(s.LIFNR <> UPPER(TRIM(s.LIFNR)), 'ID_NORMALIZED', NULL),
           IFF(r.CANONICAL IS NOT NULL AND s.REGIO <> r.CANONICAL, 'CODE_STANDARDIZED', NULL),
           IFF(r.CANONICAL IS NULL AND s.REGIO IS NOT NULL, 'UNMAPPED_CODE', NULL))) AS dq_flags,
       s.LOAD_TS                                             AS load_ts
FROM s
LEFT JOIN r ON r.VARIANT = UPPER(TRIM(s.REGIO))
WHERE NOT (UPPER(TRIM(s.LIFNR)) LIKE 'TEST%'
           OR REGEXP_LIKE(UPPER(TRIM(COALESCE(s.NAME1, ''))), '^(TEST|DUMMY)([^A-Z0-9_].*)?$')
           OR UPPER(COALESCE(s.NAME1, '')) LIKE '%DO NOT USE%');

CREATE OR REPLACE DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.PART
    TARGET_LAG = '1 day' WAREHOUSE = FORGE_WH REFRESH_MODE = INCREMENTAL
    COMMENT = 'Clean parts (from SRM_SOURCE.MARA): deduped, category standardized, test parts removed'
AS
WITH m AS (
    SELECT MATNR, MAKTX, MATKL, SUBCAT, STPRS, BRGEW, CRIT_FLG, LOAD_TS
    FROM SUPPLY_CHAIN_FORGE.SRM_SOURCE.MARA
    QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(MATNR)) ORDER BY LOAD_TS DESC, MATNR) = 1),
k AS (SELECT VARIANT, CANONICAL FROM SUPPLY_CHAIN_FORGE.CONFORMED.CODE_MAP WHERE DOMAIN = 'CATEGORY')
SELECT UPPER(TRIM(m.MATNR))::VARCHAR(18)                     AS part_id,
       m.MAKTX::VARCHAR(100)                                 AS part_name,
       COALESCE(k.CANONICAL, UPPER(TRIM(m.MATKL)))::VARCHAR(30) AS category,
       UPPER(TRIM(m.SUBCAT))::VARCHAR(30)                    AS subcategory,
       m.STPRS::NUMBER(12,2)                                 AS unit_cost,
       m.BRGEW                                               AS weight_kg,
       m.CRIT_FLG                                            AS is_critical,
       ARRAY_COMPACT(ARRAY_CONSTRUCT(
           IFF(m.MATNR <> UPPER(TRIM(m.MATNR)), 'ID_NORMALIZED', NULL),
           IFF(k.CANONICAL IS NOT NULL AND m.MATKL <> k.CANONICAL, 'CODE_STANDARDIZED', NULL),
           IFF(k.CANONICAL IS NULL AND m.MATKL IS NOT NULL, 'UNMAPPED_CODE', NULL))) AS dq_flags,
       m.LOAD_TS                                             AS load_ts
FROM m
LEFT JOIN k ON k.VARIANT = UPPER(TRIM(m.MATKL))
WHERE NOT (UPPER(TRIM(m.MATNR)) LIKE 'TEST%' OR UPPER(TRIM(m.MATNR)) LIKE 'MAT9999%'
           OR REGEXP_LIKE(UPPER(TRIM(COALESCE(m.MAKTX, ''))), '^(TEST|DUMMY)([^A-Z0-9_].*)?$')
           OR UPPER(COALESCE(m.MAKTX, '')) LIKE '%DO NOT USE%');

CREATE OR REPLACE DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.PLANT
    TARGET_LAG = '1 day' WAREHOUSE = FORGE_WH REFRESH_MODE = INCREMENTAL
    COMMENT = 'Clean plants (from WMS_SOURCE.T001W): deduped, region standardized'
AS
WITH w AS (
    SELECT WERKS, NAME1, LAND1, REGION_CD, PLANT_TYPE, CAPACITY_UNITS, LOAD_TS
    FROM SUPPLY_CHAIN_FORGE.WMS_SOURCE.T001W
    QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(WERKS)) ORDER BY LOAD_TS DESC, WERKS) = 1),
r AS (SELECT VARIANT, CANONICAL FROM SUPPLY_CHAIN_FORGE.CONFORMED.CODE_MAP WHERE DOMAIN = 'REGION')
SELECT UPPER(TRIM(w.WERKS))::VARCHAR(4)                      AS plant_id,
       w.NAME1::VARCHAR(100)                                 AS plant_name,
       UPPER(TRIM(w.LAND1))::VARCHAR(3)                      AS country,
       COALESCE(r.CANONICAL, UPPER(TRIM(w.REGION_CD)))::VARCHAR(20) AS region,
       UPPER(TRIM(w.PLANT_TYPE))::VARCHAR(20)                AS plant_type,
       w.CAPACITY_UNITS                                      AS capacity_units,
       ARRAY_COMPACT(ARRAY_CONSTRUCT(
           IFF(w.WERKS <> UPPER(TRIM(w.WERKS)), 'ID_NORMALIZED', NULL),
           IFF(r.CANONICAL IS NOT NULL AND w.REGION_CD <> r.CANONICAL, 'CODE_STANDARDIZED', NULL),
           IFF(r.CANONICAL IS NULL AND w.REGION_CD IS NOT NULL, 'UNMAPPED_CODE', NULL))) AS dq_flags,
       w.LOAD_TS                                             AS load_ts
FROM w
LEFT JOIN r ON r.VARIANT = UPPER(TRIM(w.REGION_CD));

CREATE OR REPLACE DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.CUSTOMER
    TARGET_LAG = '1 day' WAREHOUSE = FORGE_WH REFRESH_MODE = INCREMENTAL
    COMMENT = 'Clean customers (from ERP_SOURCE.KNA1): deduped, region and segment standardized, test accounts removed'
AS
WITH k AS (
    SELECT KUNNR, NAME1, EMAIL, LAND1, REGIO, KTOKD, KLIMK, LOAD_TS
    FROM SUPPLY_CHAIN_FORGE.ERP_SOURCE.KNA1
    QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(KUNNR)) ORDER BY LOAD_TS DESC, KUNNR) = 1),
r AS (SELECT VARIANT, CANONICAL FROM SUPPLY_CHAIN_FORGE.CONFORMED.CODE_MAP WHERE DOMAIN = 'REGION'),
g AS (SELECT VARIANT, CANONICAL FROM SUPPLY_CHAIN_FORGE.CONFORMED.CODE_MAP WHERE DOMAIN = 'SEGMENT')
SELECT UPPER(TRIM(k.KUNNR))::VARCHAR(10)                     AS customer_id,
       k.NAME1::VARCHAR(100)                                 AS customer_name,
       k.EMAIL::VARCHAR(100)                                 AS email,
       UPPER(TRIM(k.LAND1))::VARCHAR(3)                      AS country,
       COALESCE(r.CANONICAL, UPPER(TRIM(k.REGIO)))::VARCHAR(20) AS region,
       COALESCE(g.CANONICAL, UPPER(TRIM(k.KTOKD)))::VARCHAR(20) AS customer_segment,
       k.KLIMK::NUMBER(15,2)                                 AS credit_limit,
       ARRAY_COMPACT(ARRAY_CONSTRUCT(
           IFF(k.KUNNR <> UPPER(TRIM(k.KUNNR)), 'ID_NORMALIZED', NULL),
           IFF((r.CANONICAL IS NOT NULL AND k.REGIO <> r.CANONICAL)
               OR (g.CANONICAL IS NOT NULL AND k.KTOKD <> g.CANONICAL), 'CODE_STANDARDIZED', NULL),
           IFF((r.CANONICAL IS NULL AND k.REGIO IS NOT NULL)
               OR (g.CANONICAL IS NULL AND k.KTOKD IS NOT NULL), 'UNMAPPED_CODE', NULL))) AS dq_flags,
       k.LOAD_TS                                             AS load_ts
FROM k
LEFT JOIN r ON r.VARIANT = UPPER(TRIM(k.REGIO))
LEFT JOIN g ON g.VARIANT = UPPER(TRIM(k.KTOKD))
WHERE NOT (UPPER(TRIM(k.KUNNR)) LIKE 'TEST%'
           OR REGEXP_LIKE(UPPER(TRIM(COALESCE(k.NAME1, ''))), '^(TEST|DUMMY)([^A-Z0-9_].*)?$')
           OR UPPER(COALESCE(k.NAME1, '')) LIKE '%DO NOT USE%');

-- ── 5. SOURCING: validity kept, E11 overlapping primaries resolved ──────────
-- Test vendors and test parts drop via the inner joins BEFORE the E11 window,
-- so a test row can never supersede a real primary. E11: is_primary stays the
-- source flag, and a primary that a later-starting primary overlaps is flagged
-- PRIMARY_SUPERSEDED. Which primary wins depends on the date, so the rule
-- ("the latest VDATU wins, the other is secondary") is applied by
-- GOVERNED.V_SOURCING on the rows valid today: right for a replacement that
-- starts in the future, a nested one, or one that has already ended.
-- Contract price to USD at VDATU (§4 M05).
CREATE OR REPLACE DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.SOURCING
    TARGET_LAG = '1 day' WAREHOUSE = FORGE_WH REFRESH_MODE = INCREMENTAL
    COMMENT = 'Clean supplier-to-part source list with validity (from SRM_SOURCE.SOURCING): USD, overlapping primaries flagged (E11, resolved per date in GOVERNED.V_SOURCING)'
AS
WITH s AS (
    SELECT SOURCE_ID, LIFNR, MATNR, IS_PRIMARY, CONTRACT_PRICE, WAERS, VDATU, BDATU, LOAD_TS
    FROM SUPPLY_CHAIN_FORGE.SRM_SOURCE.SOURCING
    QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(SOURCE_ID)) ORDER BY LOAD_TS DESC, SOURCE_ID) = 1),
j AS (
    SELECT s.SOURCE_ID, s.LIFNR, s.MATNR, s.IS_PRIMARY, s.WAERS, s.VDATU, s.BDATU, s.LOAD_TS,
           sup.supplier_id, p.part_id, s.CONTRACT_PRICE * fx.usd_rate AS price_usd,
           fx.usd_rate
    FROM s
    JOIN SUPPLY_CHAIN_FORGE.CONFORMED.SUPPLIER sup ON sup.supplier_id = UPPER(TRIM(s.LIFNR))
    JOIN SUPPLY_CHAIN_FORGE.CONFORMED.PART p       ON p.part_id = UPPER(TRIM(s.MATNR))
    LEFT JOIN SUPPLY_CHAIN_FORGE.CONFORMED.FX_RATE fx
           ON fx.currency = UPPER(TRIM(s.WAERS)) AND fx.rate_date = s.VDATU),
w0 AS (
    SELECT j.*,
           IFF(j.IS_PRIMARY,
               LEAD(j.VDATU) OVER (PARTITION BY j.part_id, j.IS_PRIMARY ORDER BY j.VDATU, j.SOURCE_ID),
               NULL) AS next_primary_from
    FROM j),
w AS (
    SELECT w0.*,
           next_primary_from IS NOT NULL
               AND (BDATU IS NULL OR BDATU >= next_primary_from) AS superseded
    FROM w0)
SELECT UPPER(TRIM(w.SOURCE_ID))::VARCHAR(20)                 AS source_id,
       w.supplier_id                                         AS supplier_id,
       w.part_id                                             AS part_id,
       w.IS_PRIMARY                                          AS is_primary,
       ROUND(w.price_usd, 2)::NUMBER(12,2)                   AS contract_price,
       UPPER(TRIM(w.WAERS))::VARCHAR(3)                      AS source_currency,
       w.VDATU                                               AS valid_from,
       w.BDATU                                               AS valid_to,
       ARRAY_COMPACT(ARRAY_CONSTRUCT(
           IFF(w.SOURCE_ID <> UPPER(TRIM(w.SOURCE_ID)) OR w.LIFNR <> w.supplier_id OR w.MATNR <> w.part_id,
               'ID_NORMALIZED', NULL),
           IFF(w.superseded, 'PRIMARY_SUPERSEDED', NULL),
           IFF(w.usd_rate IS NULL, 'FX_MISSING', NULL)))     AS dq_flags,
       w.LOAD_TS                                             AS load_ts
FROM w;

-- ── 6. INVENTORY: snapshots of real parts at real plants ────────────────────
CREATE OR REPLACE DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.INVENTORY
    TARGET_LAG = '1 day' WAREHOUSE = FORGE_WH REFRESH_MODE = INCREMENTAL
    CLUSTER BY (snapshot_date)
    COMMENT = 'Clean inventory snapshots (from WMS_SOURCE.MARD): deduped, negative on-hand floored at 0, test parts removed'
AS
WITH m AS (
    SELECT INV_KEY, WERKS, MATNR, LABST, INSME, REORD_PT, DAILY_USG, SNAP_DT, LOAD_TS
    FROM SUPPLY_CHAIN_FORGE.WMS_SOURCE.MARD
    QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(INV_KEY)) ORDER BY LOAD_TS DESC, INV_KEY) = 1)
SELECT UPPER(TRIM(m.INV_KEY))::VARCHAR(40)                   AS inventory_key,
       pl.plant_id                                           AS plant_id,
       p.part_id                                             AS part_id,
       GREATEST(m.LABST, 0)::NUMBER(12,3)                    AS quantity_on_hand,
       m.INSME                                               AS quantity_reserved,
       m.REORD_PT                                            AS reorder_point,
       m.DAILY_USG                                           AS daily_usage,
       m.SNAP_DT                                             AS snapshot_date,
       ARRAY_COMPACT(ARRAY_CONSTRUCT(
           IFF(m.INV_KEY <> UPPER(TRIM(m.INV_KEY)) OR m.WERKS <> pl.plant_id OR m.MATNR <> p.part_id,
               'ID_NORMALIZED', NULL),
           IFF(m.LABST < 0, 'NEG_ON_HAND_ZEROED', NULL),
           IFF(m.DAILY_USG = 0, 'ZERO_USAGE', NULL)))        AS dq_flags,
       m.LOAD_TS                                             AS load_ts
FROM m
JOIN SUPPLY_CHAIN_FORGE.CONFORMED.PLANT pl ON pl.plant_id = UPPER(TRIM(m.WERKS))
JOIN SUPPLY_CHAIN_FORGE.CONFORMED.PART p   ON p.part_id = UPPER(TRIM(m.MATNR));

-- ── 7. SALES_ORDER: in-scope order headers ──────────────────────────────────
-- E12 compares AUDAT with the key's FIRST load, so a re-sent copy (M01, later
-- LOAD_TS) can't let a future-dated order back in. Returns (AUART = 'RE') out.
-- Test customers' orders drop via the inner join to CUSTOMER.
CREATE OR REPLACE DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.SALES_ORDER
    TARGET_LAG = '1 day' WAREHOUSE = FORGE_WH REFRESH_MODE = INCREMENTAL
    CLUSTER BY (order_date)
    COMMENT = 'Clean sales order headers (from ERP_SOURCE.VBAK): latest version, codes standardized, no returns, test or future-dated orders. ERDAT (ERP promised date) not carried.'
AS
WITH o AS (
    SELECT VBELN, KUNNR, AUDAT, GBSTK, PRIO, AUART, WAERK, LOAD_TS,
           MIN(LOAD_TS) OVER (PARTITION BY UPPER(TRIM(VBELN))) AS first_load_ts
    FROM SUPPLY_CHAIN_FORGE.ERP_SOURCE.VBAK
    QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(VBELN)) ORDER BY LOAD_TS DESC, VBELN) = 1),
st AS (SELECT VARIANT, CANONICAL FROM SUPPLY_CHAIN_FORGE.CONFORMED.CODE_MAP WHERE DOMAIN = 'ORDER_STATUS'),
pr AS (SELECT VARIANT, CANONICAL FROM SUPPLY_CHAIN_FORGE.CONFORMED.CODE_MAP WHERE DOMAIN = 'PRIORITY')
SELECT UPPER(TRIM(o.VBELN))::VARCHAR(12)                     AS order_id,
       c.customer_id                                         AS customer_id,
       o.AUDAT                                               AS order_date,
       COALESCE(st.CANONICAL, UPPER(TRIM(o.GBSTK)))::VARCHAR(20) AS order_status,
       COALESCE(pr.CANONICAL, UPPER(TRIM(o.PRIO)))::VARCHAR(10)  AS order_priority,
       UPPER(TRIM(o.WAERK))::VARCHAR(3)                      AS source_currency,
       ARRAY_COMPACT(ARRAY_CONSTRUCT(
           IFF(o.VBELN <> UPPER(TRIM(o.VBELN)) OR o.KUNNR <> c.customer_id, 'ID_NORMALIZED', NULL),
           IFF((st.CANONICAL IS NOT NULL AND o.GBSTK <> st.CANONICAL)
               OR (pr.CANONICAL IS NOT NULL AND o.PRIO <> pr.CANONICAL), 'CODE_STANDARDIZED', NULL),
           IFF((st.CANONICAL IS NULL AND o.GBSTK IS NOT NULL)
               OR (pr.CANONICAL IS NULL AND o.PRIO IS NOT NULL), 'UNMAPPED_CODE', NULL))) AS dq_flags,
       o.LOAD_TS                                             AS load_ts
FROM o
JOIN SUPPLY_CHAIN_FORGE.CONFORMED.CUSTOMER c ON c.customer_id = UPPER(TRIM(o.KUNNR))
LEFT JOIN st ON st.VARIANT = UPPER(TRIM(o.GBSTK))
LEFT JOIN pr ON pr.VARIANT = UPPER(TRIM(o.PRIO))
WHERE COALESCE(UPPER(TRIM(o.AUART)), 'OR') <> 'RE'
  AND o.AUDAT <= o.first_load_ts::DATE;

-- ── 8. ORDER_LINE: lines of in-scope orders, real parts, real plants ────────
-- Orphans (E09a), returns (E03), test orders and test-part lines (M04) and
-- future-dated orders (E12) drop via the inner joins. Price to USD at the
-- order date (M05). Over-shipment capped at the ordered quantity (E04).
CREATE OR REPLACE DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.ORDER_LINE
    TARGET_LAG = '1 day' WAREHOUSE = FORGE_WH REFRESH_MODE = INCREMENTAL
    CLUSTER BY (order_id)
    COMMENT = 'Clean order lines (from ERP_SOURCE.VBAP): in-scope orders only, IDs normalized, USD, over-shipment capped'
AS
WITH l AS (
    SELECT LINE_ID, VBELN, MATNR, WERKS, KWMENG, QTY_SHIPPED, NETPR, LOAD_TS
    FROM SUPPLY_CHAIN_FORGE.ERP_SOURCE.VBAP
    QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(LINE_ID)) ORDER BY LOAD_TS DESC, LINE_ID) = 1)
SELECT UPPER(TRIM(l.LINE_ID))::VARCHAR(20)                   AS line_id,
       o.order_id                                            AS order_id,
       p.part_id                                             AS part_id,
       pl.plant_id                                           AS plant_id,
       l.KWMENG                                              AS quantity_ordered,
       LEAST(l.QTY_SHIPPED, l.KWMENG)::NUMBER(12,3)          AS quantity_shipped,
       ROUND(l.NETPR * fx.usd_rate, 2)::NUMBER(12,2)         AS unit_price,
       o.source_currency                                     AS source_currency,
       ARRAY_COMPACT(ARRAY_CONSTRUCT(
           IFF(l.LINE_ID <> UPPER(TRIM(l.LINE_ID)) OR l.VBELN <> o.order_id
               OR l.MATNR <> p.part_id OR l.WERKS <> pl.plant_id, 'ID_NORMALIZED', NULL),
           IFF(l.QTY_SHIPPED > l.KWMENG, 'OVERSHIP_CAPPED', NULL),
           IFF(fx.usd_rate IS NULL, 'FX_MISSING', NULL)))     AS dq_flags,
       l.LOAD_TS                                             AS load_ts
FROM l
JOIN SUPPLY_CHAIN_FORGE.CONFORMED.SALES_ORDER o ON o.order_id = UPPER(TRIM(l.VBELN))
JOIN SUPPLY_CHAIN_FORGE.CONFORMED.PART p        ON p.part_id = UPPER(TRIM(l.MATNR))
JOIN SUPPLY_CHAIN_FORGE.CONFORMED.PLANT pl      ON pl.plant_id = UPPER(TRIM(l.WERKS))
LEFT JOIN SUPPLY_CHAIN_FORGE.CONFORMED.FX_RATE fx
       ON fx.currency = o.source_currency AND fx.rate_date = o.order_date;

-- ── 9. SHIPMENT: shipments of in-scope orders, costs in USD ─────────────────
-- Cost rules, in this order (§4 E07/E08): freight unknown -> all three costs
-- NULL (COST_UNKNOWN), else NULL duty/handling -> 0 (DUTY_/HANDLING_DEFAULTED),
-- then a USD total above 25,000 -> all three NULL (COST_OUTLIER). Shipments of
-- cancelled orders stay (E02: the movement happened). E01 stays visible.
CREATE OR REPLACE DYNAMIC TABLE SUPPLY_CHAIN_FORGE.CONFORMED.SHIPMENT
    TARGET_LAG = '1 day' WAREHOUSE = FORGE_WH REFRESH_MODE = INCREMENTAL
    CLUSTER BY (ship_date)
    COMMENT = 'Clean shipments (from TMS_SOURCE.VTTK): latest version, in-scope orders only, codes standardized, costs in USD with E07/E08 rules'
AS
WITH s AS (
    SELECT TKNUM, VBELN, WERKS, CARRIER_CD, DPTBG, PROM_DLV_DT, ACT_DLV_DT,
           FREIGHT_AMT, DUTY_AMT, HANDLING_AMT, SHP_STATUS, WAERS, LOAD_TS
    FROM SUPPLY_CHAIN_FORGE.TMS_SOURCE.VTTK
    QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(TKNUM)) ORDER BY LOAD_TS DESC, TKNUM) = 1),
cr AS (SELECT VARIANT, CANONICAL FROM SUPPLY_CHAIN_FORGE.CONFORMED.CODE_MAP WHERE DOMAIN = 'CARRIER'),
ss AS (SELECT VARIANT, CANONICAL FROM SUPPLY_CHAIN_FORGE.CONFORMED.CODE_MAP WHERE DOMAIN = 'SHIPMENT_STATUS'),
u AS (
    SELECT s.TKNUM, s.VBELN, s.WERKS, s.CARRIER_CD, s.DPTBG, s.PROM_DLV_DT, s.ACT_DLV_DT,
           s.DUTY_AMT, s.HANDLING_AMT, s.SHP_STATUS, s.WAERS, s.LOAD_TS,
           o.order_id, o.order_status, pl.plant_id,
           cr.CANONICAL AS carrier_c, ss.CANONICAL AS status_c,
           s.FREIGHT_AMT * fx.usd_rate  AS f_usd,
           s.DUTY_AMT * fx.usd_rate     AS d_usd,
           s.HANDLING_AMT * fx.usd_rate AS h_usd,
           fx.usd_rate
    FROM s
    JOIN SUPPLY_CHAIN_FORGE.CONFORMED.SALES_ORDER o ON o.order_id = UPPER(TRIM(s.VBELN))
    JOIN SUPPLY_CHAIN_FORGE.CONFORMED.PLANT pl      ON pl.plant_id = UPPER(TRIM(s.WERKS))
    LEFT JOIN SUPPLY_CHAIN_FORGE.CONFORMED.FX_RATE fx
           ON fx.currency = UPPER(TRIM(s.WAERS)) AND fx.rate_date = s.DPTBG
    LEFT JOIN cr ON cr.VARIANT = UPPER(TRIM(s.CARRIER_CD))
    LEFT JOIN ss ON ss.VARIANT = UPPER(TRIM(s.SHP_STATUS))),
k AS (
    SELECT u.*,
           u.f_usd IS NULL AS cost_unknown,
           u.f_usd IS NOT NULL AND u.f_usd + COALESCE(u.d_usd, 0) + COALESCE(u.h_usd, 0) > 25000 AS cost_outlier
    FROM u)
SELECT UPPER(TRIM(k.TKNUM))::VARCHAR(12)                     AS shipment_id,
       k.order_id                                            AS order_id,
       k.plant_id                                            AS plant_id,
       COALESCE(k.carrier_c, UPPER(TRIM(k.CARRIER_CD)))::VARCHAR(30) AS carrier,
       k.DPTBG                                               AS ship_date,
       k.PROM_DLV_DT                                         AS promised_delivery_date,
       k.ACT_DLV_DT                                          AS actual_delivery_date,
       IFF(k.cost_unknown OR k.cost_outlier, NULL, ROUND(k.f_usd, 2))::NUMBER(12,2)              AS freight_cost,
       IFF(k.cost_unknown OR k.cost_outlier, NULL, ROUND(COALESCE(k.d_usd, 0), 2))::NUMBER(12,2) AS duty_cost,
       IFF(k.cost_unknown OR k.cost_outlier, NULL, ROUND(COALESCE(k.h_usd, 0), 2))::NUMBER(12,2) AS handling_cost,
       COALESCE(k.status_c, UPPER(TRIM(k.SHP_STATUS)))::VARCHAR(20) AS shipment_status,
       UPPER(TRIM(k.WAERS))::VARCHAR(3)                      AS source_currency,
       ARRAY_COMPACT(ARRAY_CONSTRUCT(
           IFF(k.TKNUM <> UPPER(TRIM(k.TKNUM)) OR k.VBELN <> k.order_id OR k.WERKS <> k.plant_id,
               'ID_NORMALIZED', NULL),
           IFF((k.carrier_c IS NOT NULL AND k.CARRIER_CD <> k.carrier_c)
               OR (k.status_c IS NOT NULL AND k.SHP_STATUS <> k.status_c), 'CODE_STANDARDIZED', NULL),
           IFF((k.carrier_c IS NULL AND k.CARRIER_CD IS NOT NULL)
               OR (k.status_c IS NULL AND k.SHP_STATUS IS NOT NULL), 'UNMAPPED_CODE', NULL),
           IFF(k.PROM_DLV_DT IS NULL, 'MISSING_PROMISED_DATE', NULL),
           IFF(k.order_status = 'CANCELLED', 'ORDER_CANCELLED_AFTER_SHIPPING', NULL),
           IFF(k.DUTY_AMT IS NULL AND NOT (k.cost_unknown OR k.cost_outlier), 'DUTY_DEFAULTED', NULL),
           IFF(k.HANDLING_AMT IS NULL AND NOT (k.cost_unknown OR k.cost_outlier), 'HANDLING_DEFAULTED', NULL),
           IFF(k.cost_unknown, 'COST_UNKNOWN', NULL),
           IFF(k.cost_outlier, 'COST_OUTLIER', NULL),
           IFF(k.usd_rate IS NULL, 'FX_MISSING', NULL)))     AS dq_flags,
       k.LOAD_TS                                             AS load_ts
FROM k;

-- ── 10. Grants: FORGE_ADMIN reads CONFORMED (SP_DATA_HEALTH counts rows) ────
-- The future grants in 01_setup/03_schemas_v2.sql cover new objects, these
-- cover a re-run. Persona roles get nothing here.
GRANT SELECT ON ALL TABLES IN SCHEMA SUPPLY_CHAIN_FORGE.CONFORMED TO ROLE FORGE_ADMIN;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA SUPPLY_CHAIN_FORGE.CONFORMED TO ROLE FORGE_ADMIN;
