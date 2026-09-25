-- ============================================================
-- 01_generate_masters.sql — Master Data Generator (Suppliers, Parts, Sourcing, Plants, Customers)
-- Task: B04
-- Owner: CoCo
-- Database: SUPPLY_CHAIN_FORGE
-- ============================================================

USE DATABASE SUPPLY_CHAIN_FORGE;
USE WAREHOUSE FORGE_WH;

-- Clean existing master data if rerun
TRUNCATE TABLE IF EXISTS SRM_SOURCE.SOURCING;
TRUNCATE TABLE IF EXISTS SRM_SOURCE.MARA;
TRUNCATE TABLE IF EXISTS SRM_SOURCE.LFA1;
TRUNCATE TABLE IF EXISTS WMS_SOURCE.T001W;
TRUNCATE TABLE IF EXISTS ERP_SOURCE.KNA1;

-- ------------------------------------------------------------
-- 1. SRM_SOURCE.LFA1 (60 Suppliers)
-- ------------------------------------------------------------
INSERT INTO SRM_SOURCE.LFA1 (
    LIFNR, NAME1, LAND1, REGIO, SUPP_TIER, LEAD_TM_DAYS, RELIAB_SCR, ZTERM, EMAIL
)
WITH gen AS (
    SELECT 
        ROW_NUMBER() OVER (ORDER BY NULL) AS seq
    FROM TABLE(GENERATOR(ROWCOUNT => 60))
),
regions AS (
    SELECT 
        seq,
        CASE MOD(seq, 3)
            WHEN 0 THEN 'APAC'
            WHEN 1 THEN 'EMEA'
            ELSE 'AMER'
        END AS region,
        CASE MOD(seq, 3)
            WHEN 0 THEN DECODE(MOD(seq, 4), 0, 'CHN', 1, 'JPN', 2, 'SGP', 'IND')
            WHEN 1 THEN DECODE(MOD(seq, 4), 0, 'DEU', 1, 'GBR', 2, 'FRA', 'NLD')
            ELSE DECODE(MOD(seq, 4), 0, 'USA', 1, 'CAN', 2, 'MEX', 'BRA')
        END AS country,
        -- Supplier tier: Tier 1 (20%), Tier 2 (50%), Tier 3 (30%)
        CASE 
            WHEN seq <= 12 THEN 1
            WHEN seq <= 42 THEN 2
            ELSE 3
        END AS tier,
        -- Payment terms by tier
        CASE 
            WHEN seq <= 12 THEN '2/10 NET30'
            WHEN seq <= 42 THEN 'NET30'
            ELSE 'NET60'
        END AS payment_term,
        -- Reliability: 0.70 to 0.99 (Tier 1 higher)
        ROUND(0.70 + (seq / 60.0) * 0.28 + UNIFORM(-0.02, 0.02, RANDOM(101)), 2) AS rel_score,
        UNIFORM(5, 45, RANDOM(102)) AS lead_time
    FROM gen
),
names AS (
    SELECT 
        seq,
        'SUP' || LPAD(seq::VARCHAR, 5, '0') AS supplier_id,
        DECODE(MOD(seq, 12),
            0, 'Apex Industrial Components',
            1, 'Nordic Microelectronics',
            2, 'Pacific Rim Materials',
            3, 'Shenzhen Precision Tech',
            4, 'Bavarian Fastener Works',
            5, 'Global Polymers & Chemical',
            6, 'Atlas Heavy Mechanical',
            7, 'Kyoto Semiconductor Corp',
            8, 'Vanguard Advanced Packaging',
            9, 'Stuttgart Precision Dynamics',
            10, 'Americas Raw Metal Co',
            'Taichung Electronics Group'
        ) || ' ' || LPAD(seq::VARCHAR, 2, '0') AS supplier_name,
        country,
        region,
        tier,
        lead_time,
        CASE 
            WHEN rel_score > 0.99 THEN 0.99
            WHEN rel_score < 0.70 THEN 0.70
            ELSE rel_score 
        END AS rel_score_bounded,
        payment_term,
        'contact.sup' || LPAD(seq::VARCHAR, 3, '0') || '@supplier-forge.net' AS email
    FROM regions
)
SELECT 
    supplier_id,
    supplier_name,
    country,
    region,
    tier,
    lead_time,
    rel_score_bounded,
    payment_term,
    email
FROM names;

-- ------------------------------------------------------------
-- 2. SRM_SOURCE.MARA (250 Parts / Materials)
-- ------------------------------------------------------------
INSERT INTO SRM_SOURCE.MARA (
    MATNR, MAKTX, MATKL, SUBCAT, STPRS, BRGEW, CRIT_FLG
)
WITH gen AS (
    SELECT 
        ROW_NUMBER() OVER (ORDER BY NULL) AS seq
    FROM TABLE(GENERATOR(ROWCOUNT => 250))
),
categories AS (
    SELECT 
        seq,
        'MAT' || LPAD(seq::VARCHAR, 6, '0') AS part_id,
        CASE MOD(seq, 6)
            WHEN 0 THEN 'ELECTRONICS'
            WHEN 1 THEN 'MECHANICAL'
            WHEN 2 THEN 'RAW_MATERIAL'
            WHEN 3 THEN 'PACKAGING'
            WHEN 4 THEN 'CHEMICAL'
            ELSE 'FASTENERS'
        END AS category,
        CASE MOD(seq, 6)
            WHEN 0 THEN DECODE(MOD(seq, 4), 0, 'MICROCONTROLLERS', 1, 'SENSORS', 2, 'PASSIVES', 'CONNECTORS')
            WHEN 1 THEN DECODE(MOD(seq, 4), 0, 'BEARINGS', 1, 'GEARBOXES', 2, 'PUMPS', 'SHAFTS')
            WHEN 2 THEN DECODE(MOD(seq, 4), 0, 'ALUMINUM_INGOTS', 1, 'COPPER_SHEETS', 2, 'STEEL_RODS', 'TITANIUM_ALLOY')
            WHEN 3 THEN DECODE(MOD(seq, 4), 0, 'CORRUGATED_BOXES', 1, 'PALLETS', 2, 'FOAM_INSERTS', 'SEAL_FILM')
            WHEN 4 THEN DECODE(MOD(seq, 4), 0, 'LUBRICANTS', 1, 'ADHESIVES', 2, 'COATINGS', 'COOLANTS')
            ELSE DECODE(MOD(seq, 4), 0, 'HIGH_TENSILE_BOLTS', 1, 'RIVETS', 2, 'RETAINING_RINGS', 'WASHERS')
        END AS subcategory,
        -- Standard Unit Cost: $5.00 to $450.00
        ROUND(5.00 + (MOD(seq * 37, 445)) + (MOD(seq, 100) / 100.0), 2) AS unit_cost,
        -- Gross Weight in kg: 0.050 to 45.000 kg
        ROUND(0.050 + (MOD(seq * 19, 440) / 10.0), 3) AS weight_kg,
        -- Critical flag: ~15% critical
        CASE WHEN MOD(seq, 7) = 0 THEN TRUE ELSE FALSE END AS is_critical
    FROM gen
)
SELECT 
    part_id,
    INITCAP(REPLACE(subcategory, '_', ' ')) || ' Model-' || LPAD(seq::VARCHAR, 4, '0') AS part_name,
    category,
    subcategory,
    unit_cost,
    weight_kg,
    is_critical
FROM categories;

-- ------------------------------------------------------------
-- 3. SRM_SOURCE.SOURCING (400 Sourcing Contracts: 250 Primary + 150 Secondary)
-- ------------------------------------------------------------
INSERT INTO SRM_SOURCE.SOURCING (
    SOURCE_ID, LIFNR, MATNR, IS_PRIMARY, CONTRACT_PRICE
)
-- 250 Primary contracts (1 per part)
WITH primary_contracts AS (
    SELECT 
        'SRC' || LPAD(ROW_NUMBER() OVER (ORDER BY m.MATNR)::VARCHAR, 6, '0') AS source_id,
        -- Assign suppliers in round-robin fashion from LFA1 (60 suppliers)
        'SUP' || LPAD((MOD(ROW_NUMBER() OVER (ORDER BY m.MATNR) - 1, 60) + 1)::VARCHAR, 5, '0') AS supplier_id,
        m.MATNR AS part_id,
        TRUE AS is_primary,
        -- Contract price is negotiated around unit cost
        ROUND(m.STPRS * (0.95 + MOD(ROW_NUMBER() OVER (ORDER BY m.MATNR), 10) * 0.01), 2) AS contract_price
    FROM SRM_SOURCE.MARA m
),
-- 150 Secondary contracts (for parts 1 to 150)
secondary_contracts AS (
    SELECT 
        'SRC' || LPAD((250 + ROW_NUMBER() OVER (ORDER BY m.MATNR))::VARCHAR, 6, '0') AS source_id,
        -- Different supplier from the primary
        'SUP' || LPAD((MOD(ROW_NUMBER() OVER (ORDER BY m.MATNR) + 29, 60) + 1)::VARCHAR, 5, '0') AS supplier_id,
        m.MATNR AS part_id,
        FALSE AS is_primary,
        ROUND(m.STPRS * (0.98 + MOD(ROW_NUMBER() OVER (ORDER BY m.MATNR), 12) * 0.01), 2) AS contract_price
    FROM SRM_SOURCE.MARA m
    LIMIT 150
)
SELECT * FROM primary_contracts
UNION ALL
SELECT * FROM secondary_contracts;

-- ------------------------------------------------------------
-- 4. WMS_SOURCE.T001W (12 Plants: 4 APAC, 4 EMEA, 4 AMER)
-- ------------------------------------------------------------
INSERT INTO WMS_SOURCE.T001W (
    WERKS, NAME1, LAND1, REGION_CD, PLANT_TYPE, CAPACITY_UNITS
)
VALUES
    -- APAC (4)
    ('PL01', 'Tokyo Advanced DC',            'JPN', 'APAC', 'DC',  120000),
    ('PL02', 'Shanghai Mega Manufacturing',  'CHN', 'APAC', 'MFG', 250000),
    ('PL03', 'Singapore Logistics Gateway',  'SGP', 'APAC', 'HUB', 180000),
    ('PL04', 'Chennai Heavy Production',     'IND', 'APAC', 'MFG', 220000),
    -- EMEA (4)
    ('PL05', 'Frankfurt Central Distribution','DEU', 'EMEA', 'DC',  140000),
    ('PL06', 'Rotterdam Freight Hub',        'NLD', 'EMEA', 'HUB', 200000),
    ('PL07', 'Munich Precision Facility',    'DEU', 'EMEA', 'MFG', 160000),
    ('PL08', 'London Regional DC',           'GBR', 'EMEA', 'DC',  100000),
    -- AMER (4)
    ('PL09', 'Chicago Industrial Plant',     'USA', 'AMER', 'MFG', 210000),
    ('PL10', 'Dallas Distribution Center',   'USA', 'AMER', 'DC',  150000),
    ('PL11', 'Long Beach Maritime Hub',      'USA', 'AMER', 'HUB', 230000),
    ('PL12', 'Monterrey Assembly Plant',     'MEX', 'AMER', 'MFG', 190000);

-- ------------------------------------------------------------
-- 5. ERP_SOURCE.KNA1 (120 Customers across 3 Segments & 3 Regions)
-- ------------------------------------------------------------
INSERT INTO ERP_SOURCE.KNA1 (
    KUNNR, NAME1, EMAIL, LAND1, REGIO, KTOKD, KLIMK
)
WITH gen AS (
    SELECT 
        ROW_NUMBER() OVER (ORDER BY NULL) AS seq
    FROM TABLE(GENERATOR(ROWCOUNT => 120))
),
cust_calc AS (
    SELECT 
        seq,
        'CUST' || LPAD(seq::VARCHAR, 5, '0') AS customer_id,
        DECODE(MOD(seq, 10),
            0, 'Acrobat Aerospace Systems',
            1, 'Beacon Global Logistics',
            2, 'Crestview Automotive Group',
            3, 'Delta Energy Dynamics',
            4, 'Echo Medical Devices',
            5, 'Frontier Renewable Tech',
            6, 'Genesis Consumer Goods',
            7, 'Horizon Industrial Equipment',
            8, 'Insignia Electronics LLC',
            'Keystone Power Systems'
        ) || ' - Division ' || LPAD(seq::VARCHAR, 3, '0') AS customer_name,
        'accounts.payable' || LPAD(seq::VARCHAR, 3, '0') || '@clientcorp.com' AS email,
        CASE MOD(seq, 3)
            WHEN 0 THEN 'APAC'
            WHEN 1 THEN 'EMEA'
            ELSE 'AMER'
        END AS region,
        CASE MOD(seq, 3)
            WHEN 0 THEN DECODE(MOD(seq, 4), 0, 'JPN', 1, 'CHN', 2, 'SGP', 'IND')
            WHEN 1 THEN DECODE(MOD(seq, 4), 0, 'DEU', 1, 'GBR', 2, 'FRA', 'NLD')
            ELSE DECODE(MOD(seq, 4), 0, 'USA', 1, 'CAN', 2, 'MEX', 'BRA')
        END AS country,
        -- Segment distribution: ENTERPRISE (30%), MIDMARKET (45%), SMB (25%)
        CASE 
            WHEN seq <= 36 THEN 'ENTERPRISE'
            WHEN seq <= 90 THEN 'MIDMARKET'
            ELSE 'SMB'
        END AS segment,
        -- Credit limit by segment
        CASE 
            WHEN seq <= 36 THEN 1500000.00 + (MOD(seq * 31, 500) * 1000)
            WHEN seq <= 90 THEN 500000.00 + (MOD(seq * 17, 300) * 1000)
            ELSE 100000.00 + (MOD(seq * 13, 100) * 1000)
        END AS credit_limit
    FROM gen
)
SELECT 
    customer_id,
    customer_name,
    email,
    country,
    region,
    segment,
    credit_limit
FROM cust_calc;
