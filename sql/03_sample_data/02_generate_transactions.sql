-- ============================================================
-- 02_generate_transactions.sql — Transactional Data Generator (Orders, Lines, Shipments, Inventory)
-- Task: B04
-- Owner: CoCo
-- Database: SUPPLY_CHAIN_FORGE
-- ============================================================

USE DATABASE SUPPLY_CHAIN_FORGE;
USE WAREHOUSE FORGE_WH;

-- Clean existing transaction data if rerun
TRUNCATE TABLE IF EXISTS TMS_SOURCE.VTTK;
TRUNCATE TABLE IF EXISTS ERP_SOURCE.VBAP;
TRUNCATE TABLE IF EXISTS ERP_SOURCE.VBAK;
TRUNCATE TABLE IF EXISTS WMS_SOURCE.MARD;

-- ------------------------------------------------------------
-- 1. ERP_SOURCE.VBAK (800 Sales Order Headers)
-- ------------------------------------------------------------
INSERT INTO ERP_SOURCE.VBAK (
    VBELN, KUNNR, AUDAT, ERDAT, GBSTK, PRIO
)
WITH gen AS (
    SELECT ROW_NUMBER() OVER (ORDER BY NULL) AS seq FROM TABLE(GENERATOR(ROWCOUNT => 800))
),
orders_calc AS (
    SELECT 
        seq,
        'ORD' || LPAD(seq::VARCHAR, 6, '0') AS order_id,
        'CUST' || LPAD((MOD(seq - 1, 120) + 1)::VARCHAR, 5, '0') AS customer_id,
        -- Order Date: spread across past 12 months with Q4 seasonal volume surge
        CASE 
            WHEN seq <= 280 THEN DATE '2025-10-01' + MOD(seq * 3, 91)           -- Q4 2025 (Oct-Dec) 35%
            WHEN seq <= 460 THEN DATE '2026-01-01' + MOD(seq * 3, 90)           -- Q1 2026 (Jan-Mar) 22.5%
            WHEN seq <= 640 THEN DATE '2026-04-01' + MOD(seq * 3, 91)           -- Q2 2026 (Apr-Jun) 22.5%
            ELSE DATE '2026-07-01' + MOD(seq * 3, 80)                           -- Q3 2026 (Jul-Sep) 20%
        END AS order_date,
        -- Base Promised Date: 7 to 20 days after order date
        CASE 
            WHEN seq <= 280 THEN DATE '2025-10-01' + MOD(seq * 3, 91) + 7 + MOD(seq * 13, 14)
            WHEN seq <= 460 THEN DATE '2026-01-01' + MOD(seq * 3, 90) + 7 + MOD(seq * 13, 14)
            WHEN seq <= 640 THEN DATE '2026-04-01' + MOD(seq * 3, 91) + 7 + MOD(seq * 13, 14)
            ELSE DATE '2026-07-01' + MOD(seq * 3, 80) + 7 + MOD(seq * 13, 14)
        END AS base_promised_date,
        -- Status distribution: CANCELLED (5%), OPEN (10%), SHIPPED (15%), DELIVERED (70%)
        CASE 
            WHEN seq <= 40 THEN 'CANCELLED'
            WHEN seq <= 120 THEN 'OPEN'
            WHEN seq <= 240 THEN 'SHIPPED'
            ELSE 'DELIVERED'
        END AS status,
        -- Priority: HIGH (20%), NORMAL (65%), LOW (15%)
        CASE 
            WHEN MOD(seq, 5) = 0 THEN 'HIGH'
            WHEN MOD(seq, 7) = 0 THEN 'LOW'
            ELSE 'NORMAL'
        END AS priority
    FROM gen
),
orders_with_conflict AS (
    SELECT 
        order_id,
        customer_id,
        order_date,
        -- Deliberate ERP promised date: On exactly 20% of orders (MOD(seq,5)=0), ERP date differs from true TMS date!
        CASE 
            WHEN MOD(seq, 5) = 0 THEN base_promised_date + DECODE(MOD(seq, 4), 0, -3, 1, 3, 2, -5, 4)
            ELSE base_promised_date
        END AS erp_promised_date,
        status,
        priority
    FROM orders_calc
)
SELECT 
    order_id,
    customer_id,
    order_date,
    erp_promised_date,
    status,
    priority
FROM orders_with_conflict;

-- ------------------------------------------------------------
-- 2. ERP_SOURCE.VBAP (2,400 Sales Order Lines: 3 lines per order)
-- ------------------------------------------------------------
INSERT INTO ERP_SOURCE.VBAP (
    LINE_ID, VBELN, MATNR, WERKS, KWMENG, QTY_SHIPPED, NETPR
)
WITH order_lines_gen AS (
    SELECT 
        o.VBELN AS order_id,
        o.GBSTK AS order_status,
        c.REGIO AS customer_region,
        l.seq AS line_no,
        ROW_NUMBER() OVER (ORDER BY o.VBELN, l.seq) AS line_seq
    FROM ERP_SOURCE.VBAK o
    JOIN ERP_SOURCE.KNA1 c ON o.KUNNR = c.KUNNR
    CROSS JOIN (SELECT 1 AS seq UNION ALL SELECT 2 UNION ALL SELECT 3) l
),
lines_calc AS (
    SELECT 
        order_id || '-' || LPAD(line_no::VARCHAR, 2, '0') AS line_id,
        order_id,
        'MAT' || LPAD((MOD(line_seq * 17, 250) + 1)::VARCHAR, 6, '0') AS part_id,
        CASE customer_region
            WHEN 'APAC' THEN DECODE(MOD(line_seq, 4), 0, 'PL01', 1, 'PL02', 2, 'PL03', 'PL04')
            WHEN 'EMEA' THEN DECODE(MOD(line_seq, 4), 0, 'PL05', 1, 'PL06', 2, 'PL07', 'PL08')
            ELSE DECODE(MOD(line_seq, 4), 0, 'PL09', 1, 'PL10', 2, 'PL11', 'PL12')
        END AS plant_id,
        ROUND(20.0 + MOD(line_seq * 37, 180), 0) AS qty_ordered,
        order_status,
        line_seq
    FROM order_lines_gen
),
lines_fulfillment AS (
    SELECT 
        lc.line_id,
        lc.order_id,
        lc.part_id,
        lc.plant_id,
        lc.qty_ordered,
        -- Fill rate calibration:
        -- If cancelled or open: 0
        -- On 75% of lines: 100% full fill. On 25% of lines: 60%-85% partial fill.
        -- Results in overall Fill Rate ≈ 92.8% (Target: 0.90 - 0.95)
        CASE 
            WHEN lc.order_status IN ('CANCELLED', 'OPEN') THEN 0.0
            WHEN MOD(lc.line_seq, 4) = 0 THEN ROUND(lc.qty_ordered * (0.60 + MOD(lc.line_seq, 5) * 0.05), 0)
            ELSE lc.qty_ordered
        END AS qty_shipped,
        ROUND(m.STPRS * 1.30, 2) AS unit_price
    FROM lines_calc lc
    JOIN SRM_SOURCE.MARA m ON lc.part_id = m.MATNR
)
SELECT 
    line_id,
    order_id,
    part_id,
    plant_id,
    qty_ordered,
    qty_shipped,
    unit_price
FROM lines_fulfillment;

-- ------------------------------------------------------------
-- 3. TMS_SOURCE.VTTK (880 Shipments: 1 to 2 per shipped/delivered order)
-- ------------------------------------------------------------
INSERT INTO TMS_SOURCE.VTTK (
    TKNUM, VBELN, WERKS, CARRIER_CD, DPTBG, PROM_DLV_DT, ACT_DLV_DT, FREIGHT_AMT, DUTY_AMT, HANDLING_AMT, SHP_STATUS
)
WITH eligible_orders AS (
    SELECT 
        o.VBELN AS order_id,
        o.AUDAT AS order_date,
        SUBSTR(o.VBELN, 4)::INT AS ord_seq,
        MIN(vb.WERKS) AS origin_plant,
        ROW_NUMBER() OVER (ORDER BY o.VBELN) AS ord_num
    FROM ERP_SOURCE.VBAK o
    JOIN ERP_SOURCE.VBAP vb ON o.VBELN = vb.VBELN
    WHERE o.GBSTK IN ('SHIPPED', 'DELIVERED') -- 760 orders
    GROUP BY o.VBELN, o.AUDAT
),
orders_with_tms_date AS (
    SELECT 
        order_id,
        order_date,
        ord_seq,
        origin_plant,
        ord_num,
        -- Authoritative TMS promised date (7 to 20 days after AUDAT)
        DATEADD('day', 7 + MOD(ord_seq * 13, 14), order_date) AS tms_promised_date
    FROM eligible_orders
),
shipments_expansion AS (
    SELECT order_id, order_date, tms_promised_date, origin_plant, ord_num, 1 AS split_num FROM orders_with_tms_date
    UNION ALL
    SELECT order_id, order_date, tms_promised_date, origin_plant, ord_num, 2 AS split_num FROM orders_with_tms_date WHERE ord_num <= 120
),
shipments_seq AS (
    SELECT 
        order_id,
        order_date,
        tms_promised_date,
        origin_plant,
        ROW_NUMBER() OVER (ORDER BY order_date, order_id, split_num) AS shp_seq
    FROM shipments_expansion
),
shipments_calc AS (
    SELECT 
        'SHP' || LPAD(shp_seq::VARCHAR, 6, '0') AS shipment_id,
        order_id,
        origin_plant,
        DECODE(MOD(shp_seq, 6),
            0, 'DHL_EXPRESS',
            1, 'FEDEX_FREIGHT',
            2, 'MAERSK_LOGISTICS',
            3, 'KUEHNE_NAGEL',
            4, 'DB_SCHENKER',
            'UPS_SUPPLY_CHAIN'
        ) AS carrier,
        DATEADD('day', 1 + MOD(shp_seq, 4), order_date) AS ship_date,
        tms_promised_date,
        -- Delivery outcome:
        -- ~8% IN_TRANSIT (ACT_DLV_DT = NULL)
        -- Of delivered: ~87% On-Time, ~13% Delayed (OTD ≈ 87%)
        CASE 
            WHEN shp_seq <= 70 THEN NULL                                                          -- IN_TRANSIT (8%)
            WHEN MOD(shp_seq, 8) = 0 THEN DATEADD('day', 1 + MOD(shp_seq, 7), tms_promised_date) -- DELAYED (12.5%)
            ELSE DATEADD('day', -MOD(shp_seq, 3), tms_promised_date)                             -- ON_TIME (87.5% of delivered)
        END AS actual_delivery_date,
        ROUND(180.00 + MOD(shp_seq * 31, 320) + (MOD(shp_seq, 100) / 10.0), 2) AS freight_cost,
        ROUND(40.00 + MOD(shp_seq * 17, 130) + (MOD(shp_seq, 50) / 10.0), 2) AS duty_cost,
        ROUND(25.00 + MOD(shp_seq * 13, 85) + (MOD(shp_seq, 30) / 10.0), 2) AS handling_cost
    FROM shipments_seq
)
SELECT 
    shipment_id,
    order_id,
    origin_plant,
    carrier,
    ship_date,
    tms_promised_date,
    actual_delivery_date,
    freight_cost,
    duty_cost,
    handling_cost,
    CASE 
        WHEN actual_delivery_date IS NULL THEN 'IN_TRANSIT'
        WHEN actual_delivery_date <= tms_promised_date THEN 'DELIVERED'
        ELSE 'DELAYED'
    END AS shipment_status
FROM shipments_calc;

-- ------------------------------------------------------------
-- 4. WMS_SOURCE.MARD (9,000 Daily Inventory Snapshots: 12 Plants × 25 Parts × 30 Days)
-- ------------------------------------------------------------
INSERT INTO WMS_SOURCE.MARD (
    INV_KEY, WERKS, MATNR, LABST, INSME, REORD_PT, DAILY_USG, SNAP_DT
)
WITH sample_parts AS (
    SELECT MATNR, ROW_NUMBER() OVER (ORDER BY MATNR) AS part_idx
    FROM SRM_SOURCE.MARA
    WHERE MOD(SUBSTR(MATNR, 4)::INT, 10) = 0
    LIMIT 25
),
plants AS (
    SELECT WERKS, ROW_NUMBER() OVER (ORDER BY WERKS) AS plant_idx FROM WMS_SOURCE.T001W
),
days_gen AS (
    SELECT ROW_NUMBER() OVER (ORDER BY NULL) - 1 AS day_offset FROM TABLE(GENERATOR(ROWCOUNT => 30))
),
combos AS (
    SELECT 
        p.WERKS AS plant_id,
        sp.MATNR AS part_id,
        DATEADD('day', d.day_offset, DATE '2026-08-26') AS snapshot_date,
        p.plant_idx,
        sp.part_idx,
        d.day_offset
    FROM plants p
    CROSS JOIN sample_parts sp
    CROSS JOIN days_gen d
),
inventory_calc AS (
    SELECT 
        plant_id || '-' || part_id || '-' || TO_VARCHAR(snapshot_date, 'YYYYMMDD') AS inv_key,
        plant_id,
        part_id,
        ROUND(10.0 + MOD(part_idx * 7 + plant_idx * 3, 35), 3) AS daily_usage,
        ROUND((10.0 + MOD(part_idx * 7 + plant_idx * 3, 35)) * (18.0 + MOD(part_idx * 11 + plant_idx * 5 + day_offset, 22)), 3) AS stock_on_hand,
        ROUND((10.0 + MOD(part_idx * 7 + plant_idx * 3, 35)) * 1.5, 3) AS reserved_qty,
        ROUND((10.0 + MOD(part_idx * 7 + plant_idx * 3, 35)) * 10.0, 3) AS reorder_pt,
        snapshot_date
    FROM combos
)
SELECT 
    inv_key,
    plant_id,
    part_id,
    stock_on_hand,
    reserved_qty,
    reorder_pt,
    daily_usage,
    snapshot_date
FROM inventory_calc;
