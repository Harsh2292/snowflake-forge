-- ============================================================
-- 03_verify_distributions.sql — Statistical Distribution & Metric Verification
-- Task: B05
-- Owner: CoCo
-- Database: SUPPLY_CHAIN_FORGE
-- ============================================================

USE DATABASE SUPPLY_CHAIN_FORGE;
USE WAREHOUSE FORGE_WH;

-- ------------------------------------------------------------
-- 1. Table Row Counts vs Targets
-- ------------------------------------------------------------
SELECT 'SRM_SOURCE.LFA1' AS object_name, COUNT(*) AS row_count, 60 AS target_count FROM SRM_SOURCE.LFA1
UNION ALL SELECT 'SRM_SOURCE.MARA', COUNT(*), 250 FROM SRM_SOURCE.MARA
UNION ALL SELECT 'SRM_SOURCE.SOURCING', COUNT(*), 400 FROM SRM_SOURCE.SOURCING
UNION ALL SELECT 'WMS_SOURCE.T001W', COUNT(*), 12 FROM WMS_SOURCE.T001W
UNION ALL SELECT 'ERP_SOURCE.KNA1', COUNT(*), 120 FROM ERP_SOURCE.KNA1
UNION ALL SELECT 'ERP_SOURCE.VBAK', COUNT(*), 800 FROM ERP_SOURCE.VBAK
UNION ALL SELECT 'ERP_SOURCE.VBAP', COUNT(*), 2400 FROM ERP_SOURCE.VBAP
UNION ALL SELECT 'TMS_SOURCE.VTTK', COUNT(*), 800 FROM TMS_SOURCE.VTTK
UNION ALL SELECT 'WMS_SOURCE.MARD', COUNT(*), 9000 FROM WMS_SOURCE.MARD;

-- ------------------------------------------------------------
-- 2. Canonical Metric 1: On-Time Delivery (OTD) — Target: 0.84 to 0.90
-- ------------------------------------------------------------
-- Overall OTD
SELECT 
    COUNT_IF(ACT_DLV_DT <= PROM_DLV_DT) AS on_time_shipments,
    COUNT_IF(ACT_DLV_DT > PROM_DLV_DT) AS delayed_shipments,
    COUNT_IF(ACT_DLV_DT IS NULL) AS in_transit_shipments,
    COUNT(*) AS total_shipments,
    ROUND(COUNT_IF(ACT_DLV_DT <= PROM_DLV_DT) / NULLIFZERO(COUNT_IF(ACT_DLV_DT IS NOT NULL)), 4) AS authoritative_otd_rate
FROM TMS_SOURCE.VTTK;

-- OTD by Region
SELECT 
    p.REGION_CD AS region,
    COUNT(*) AS total_shipments,
    COUNT_IF(s.ACT_DLV_DT IS NOT NULL) AS delivered_shipments,
    ROUND(COUNT_IF(s.ACT_DLV_DT <= s.PROM_DLV_DT) / NULLIFZERO(COUNT_IF(s.ACT_DLV_DT IS NOT NULL)), 4) AS regional_otd_rate
FROM TMS_SOURCE.VTTK s
JOIN WMS_SOURCE.T001W p ON s.WERKS = p.WERKS
GROUP BY p.REGION_CD
ORDER BY p.REGION_CD;

-- ------------------------------------------------------------
-- 3. Canonical Metric 2: Order Fill Rate — Target: 0.90 to 0.95
-- ------------------------------------------------------------
-- Overall Fill Rate
SELECT 
    SUM(QTY_SHIPPED) AS total_units_shipped,
    SUM(KWMENG) AS total_units_ordered,
    ROUND(SUM(QTY_SHIPPED) / SUM(KWMENG), 4) AS overall_fill_rate
FROM ERP_SOURCE.VBAP
WHERE QTY_SHIPPED > 0;

-- Fill Rate by Product Category
SELECT 
    m.MATKL AS product_category,
    SUM(vb.KWMENG) AS units_ordered,
    SUM(vb.QTY_SHIPPED) AS units_shipped,
    ROUND(SUM(vb.QTY_SHIPPED) / SUM(vb.KWMENG), 4) AS category_fill_rate
FROM ERP_SOURCE.VBAP vb
JOIN SRM_SOURCE.MARA m ON vb.MATNR = m.MATNR
WHERE vb.QTY_SHIPPED > 0
GROUP BY m.MATKL
ORDER BY category_fill_rate DESC;

-- ------------------------------------------------------------
-- 4. Canonical Metric 3: Days of Inventory (DOI) — Target: 15 to 45 days
-- ------------------------------------------------------------
-- Overall DOI
SELECT 
    ROUND(AVG(LABST / NULLIFZERO(DAILY_USG)), 2) AS overall_avg_doi_days,
    ROUND(MIN(LABST / NULLIFZERO(DAILY_USG)), 2) AS min_doi_days,
    ROUND(MAX(LABST / NULLIFZERO(DAILY_USG)), 2) AS max_doi_days
FROM WMS_SOURCE.MARD;

-- DOI by Plant
SELECT 
    p.WERKS AS plant_id,
    p.NAME1 AS plant_name,
    p.REGION_CD AS region,
    ROUND(AVG(m.LABST / NULLIFZERO(m.DAILY_USG)), 2) AS plant_avg_doi_days
FROM WMS_SOURCE.MARD m
JOIN WMS_SOURCE.T001W p ON m.WERKS = p.WERKS
GROUP BY p.WERKS, p.NAME1, p.REGION_CD
ORDER BY p.WERKS;

-- ------------------------------------------------------------
-- 5. Canonical Metric 4: Average Landed Cost — Target: $150 to $900
-- ------------------------------------------------------------
-- Overall Landed Cost Breakdown
SELECT 
    ROUND(AVG(FREIGHT_AMT), 2) AS avg_freight_cost,
    ROUND(AVG(DUTY_AMT), 2) AS avg_duty_cost,
    ROUND(AVG(HANDLING_AMT), 2) AS avg_handling_cost,
    ROUND(AVG(FREIGHT_AMT + DUTY_AMT + HANDLING_AMT), 2) AS overall_avg_landed_cost
FROM TMS_SOURCE.VTTK;

-- Landed Cost by Region
SELECT 
    p.REGION_CD AS region,
    ROUND(AVG(s.FREIGHT_AMT), 2) AS avg_freight,
    ROUND(AVG(s.DUTY_AMT), 2) AS avg_duty,
    ROUND(AVG(s.HANDLING_AMT), 2) AS avg_handling,
    ROUND(AVG(s.FREIGHT_AMT + s.DUTY_AMT + s.HANDLING_AMT), 2) AS regional_avg_landed_cost
FROM TMS_SOURCE.VTTK s
JOIN WMS_SOURCE.T001W p ON s.WERKS = p.WERKS
GROUP BY p.REGION_CD
ORDER BY p.REGION_CD;

-- ------------------------------------------------------------
-- 6. Problem Statement Divergence Proof (Tab 3 Demo Hook)
-- ------------------------------------------------------------
SELECT 
    ROUND(COUNT_IF(s.ACT_DLV_DT <= s.PROM_DLV_DT) / NULLIFZERO(COUNT_IF(s.ACT_DLV_DT IS NOT NULL)), 4) AS authoritative_tms_otd,
    ROUND(COUNT_IF(s.ACT_DLV_DT <= o.ERDAT) / NULLIFZERO(COUNT_IF(s.ACT_DLV_DT IS NOT NULL)), 4) AS naive_erp_otd,
    ROUND((COUNT_IF(s.ACT_DLV_DT <= s.PROM_DLV_DT) - COUNT_IF(s.ACT_DLV_DT <= o.ERDAT)) / NULLIFZERO(COUNT_IF(s.ACT_DLV_DT IS NOT NULL)), 4) AS otd_discrepancy_delta,
    ROUND(COUNT_IF(s.PROM_DLV_DT != o.ERDAT) / COUNT(*), 4) AS date_conflict_rate
FROM TMS_SOURCE.VTTK s
JOIN ERP_SOURCE.VBAK o ON s.VBELN = o.VBELN;

-- ------------------------------------------------------------
-- 7. Data Quality & Referential Integrity Checks
-- ------------------------------------------------------------
-- Overshipping Check (Must be 0)
SELECT COUNT(*) AS overshipped_lines_count FROM ERP_SOURCE.VBAP WHERE QTY_SHIPPED > KWMENG;

-- Primary Sourcing (Must be 250)
SELECT COUNT(*) AS primary_suppliers_count FROM SRM_SOURCE.SOURCING WHERE IS_PRIMARY = TRUE;
