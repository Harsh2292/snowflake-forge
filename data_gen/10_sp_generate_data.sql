-- ============================================================================
-- data_gen/10_sp_generate_data.sql — OPS.SP_GENERATE_DATA: 10 years of clean source data
-- Card:       C08 (.agents/tasks/claude/C08_data_generator.md)
-- Spec:       docs/DATA_SPEC.md §1–§3, §6, §7.1 (and §2.3 load order)
-- Role:       ACCOUNTADMIN (owns the source tables)   Warehouse: FORGE_WH (XS) at SF <= 1
-- Run order:  2 of 5 (00 → 10 → 20 → 30 → 99). Re-runnable: CREATE OR REPLACE.
-- Needs:      the 10 v2 source tables (CoCo B08c: sql/02_tables/05_source_v2.sql),
--             schema OPS and the log tables (00_setup.sql).
-- Parameters: TARGET_DB (SUPPLY_CHAIN_FORGE, or a clone at B13), SCALE_FACTOR (0.01 dry
--             run, 1 main, 50 at B13), SEED (20260929), END_DATE (the run date).
-- Expected:   CREATE succeeds. A CALL at SF 1 writes, before any mess:
--             T001W 12 · LFA1 150 · MARA 1,200 · KNA1 2,000 · TCURR ~23.3K · SOURCING ~2.4K
--             VBAK 650,000 (±1%) · VBAP ~2.0M · VTTK ~0.72M · MARD ~2.2M
--             and returns {"status": "OK", "rows": {...}, "stages": [...], ...}.
--             On failure it returns {"status": "ERROR", "stage": ..., "sqlerrm": ...}.
--
-- Determinism (§6): every random choice is BITAND(HASH(SEED, '<TABLE>', <key>, '<attr>'),
-- 4294967295) / 4294967295.0; no RANDOM(), no clock in the data (only in the logs). Sums
-- that feed the data are exact NUMBER sums, because floating-point sums can change with
-- parallelism. Numbering is gap-free: orders by (order date, then row), shipments by
-- (order, plant, part). Same inputs => the same rows, byte for byte.
-- ============================================================================

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_FORGE.OPS.SP_GENERATE_DATA(
    TARGET_DB VARCHAR, SCALE_FACTOR FLOAT, SEED NUMBER, END_DATE DATE)
RETURNS VARIANT
LANGUAGE SQL
COMMENT = 'C08: fills the 10 v2 source tables with clean, deterministic data (DATA_SPEC §2-§3). Mess comes from SP_INJECT_MESS.'
EXECUTE AS CALLER
AS
$$
DECLARE
    stage        VARCHAR DEFAULT 'start';
    run_id       VARCHAR;
    ok_name      BOOLEAN;
    s_date       DATE;          -- history start: END_DATE - 10 years
    l_date       DATE;          -- last business date: END_DATE - 1
    fx_start     DATE;          -- one week before the history, so every date has a rate
    n_days       INTEGER;
    n_fx_days    INTEGER;
    n_orders     INTEGER;
    max_k        INTEGER;
    late_start   DATE;          -- suppliers onboarded late: history years 3-10
    late_span    INTEGER;
    cust_span    INTEGER;
    y0           INTEGER;
    y1           INTEGER;
    shp_offset   INTEGER DEFAULT 0;
    n_rows       INTEGER;
    t0           TIMESTAMP_NTZ;
    run_t0       TIMESTAMP_NTZ;
    result       VARIANT;
BEGIN
    -- ── 0. Parameters and context ───────────────────────────────────────────
    SELECT UUID_STRING(), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
           COALESCE(REGEXP_LIKE(:TARGET_DB, '^[A-Za-z_][A-Za-z0-9_$]*$'), FALSE)
      INTO :run_id, :run_t0, :ok_name;
    IF (NOT ok_name OR SCALE_FACTOR IS NULL OR SCALE_FACTOR <= 0 OR SEED IS NULL OR END_DATE IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('status', 'ERROR', 'stage', 'parameters',
            'sqlerrm', 'TARGET_DB must be a plain identifier; SCALE_FACTOR > 0; SEED and END_DATE required');
    END IF;

    EXECUTE IMMEDIATE 'USE SCHEMA ' || :TARGET_DB || '.OPS';

    SELECT DATEADD(year, -10, :END_DATE), DATEADD(day, -1, :END_DATE), DATEADD(day, -7, DATEADD(year, -10, :END_DATE)),
           ROUND(650000 * :SCALE_FACTOR)
      INTO :s_date, :l_date, :fx_start, :n_orders;
    SELECT DATEDIFF(day, :s_date, :l_date) + 1, DATEDIFF(day, :fx_start, :l_date) + 1,
           DATEADD(year, 2, :s_date), DATEDIFF(day, DATEADD(year, 2, :s_date), :l_date) - 30,
           DATEDIFF(day, :s_date, :l_date) - 30, YEAR(:s_date), YEAR(:l_date)
      INTO :n_days, :n_fx_days, :late_start, :late_span, :cust_span, :y0, :y1;

    INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT, PARAMS)
    SELECT :run_id, :TARGET_DB, 'start', NULL, NULL, NULL, :run_t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
           OBJECT_CONSTRUCT('procedure', 'SP_GENERATE_DATA', 'scale_factor', :SCALE_FACTOR, 'seed', :SEED,
                            'end_date', :END_DATE, 'history_start', :s_date, 'last_business_date', :l_date,
                            'orders_target', :n_orders);

    -- Every stage starts by emptying what it writes (§2.3): idempotent re-runs.
    stage := 'truncate';
    TRUNCATE TABLE WMS_SOURCE.MARD;
    TRUNCATE TABLE TMS_SOURCE.VTTK;
    TRUNCATE TABLE ERP_SOURCE.VBAP;
    TRUNCATE TABLE ERP_SOURCE.VBAK;
    TRUNCATE TABLE SRM_SOURCE.SOURCING;
    TRUNCATE TABLE ERP_SOURCE.TCURR;
    TRUNCATE TABLE ERP_SOURCE.KNA1;
    TRUNCATE TABLE SRM_SOURCE.MARA;
    TRUNCATE TABLE SRM_SOURCE.LFA1;
    TRUNCATE TABLE WMS_SOURCE.T001W;

    -- ── 1. Reference tables (session temp) ──────────────────────────────────
    stage := 'reference';
    -- The 12 v1 plants (§2.1), with local currency and a fixed per-plant on-time offset.
    CREATE OR REPLACE TEMPORARY TABLE TMP_PLANT AS
    SELECT v.WERKS, v.NAME1, v.LAND1, v.REGION, v.PLANT_TYPE, v.CAPACITY_UNITS, v.CURRENCY,
           SUBSTR(v.WERKS, 3)::NUMBER AS plant_num,
           (v.CAPACITY_UNITS / 10000)::NUMBER AS units,
           -0.015 + 0.03 * (BITAND(HASH(:SEED, 'T001W', SUBSTR(v.WERKS, 3)::NUMBER, 'ot_offset'), 4294967295) / 4294967295.0) AS ot_offset
    FROM (VALUES
        ('PL01', 'Tokyo Advanced DC',              'JPN', 'APAC', 'DC',  120000, 'JPY'),
        ('PL02', 'Shanghai Mega Manufacturing',    'CHN', 'APAC', 'MFG', 250000, 'CNY'),
        ('PL03', 'Singapore Logistics Gateway',    'SGP', 'APAC', 'HUB', 180000, 'SGD'),
        ('PL04', 'Chennai Heavy Production',       'IND', 'APAC', 'MFG', 220000, 'INR'),
        ('PL05', 'Frankfurt Central Distribution', 'DEU', 'EMEA', 'DC',  140000, 'EUR'),
        ('PL06', 'Rotterdam Freight Hub',          'NLD', 'EMEA', 'HUB', 200000, 'EUR'),
        ('PL07', 'Munich Precision Facility',      'DEU', 'EMEA', 'MFG', 160000, 'EUR'),
        ('PL08', 'London Regional DC',             'GBR', 'EMEA', 'DC',  100000, 'GBP'),
        ('PL09', 'Chicago Industrial Plant',       'USA', 'AMER', 'MFG', 210000, 'USD'),
        ('PL10', 'Dallas Distribution Center',     'USA', 'AMER', 'DC',  150000, 'USD'),
        ('PL11', 'Long Beach Maritime Hub',        'USA', 'AMER', 'HUB', 230000, 'USD'),
        ('PL12', 'Monterrey Assembly Plant',       'MEX', 'AMER', 'MFG', 190000, 'MXN')
    ) AS v(WERKS, NAME1, LAND1, REGION, PLANT_TYPE, CAPACITY_UNITS, CURRENCY);

    -- Capacity-weighted plant pick within a region: one row per capacity unit (10,000).
    -- Numbers 1..N per row via FLATTEN(ARRAY_GENERATE_RANGE(...)), never a range join
    -- (JOIN k ON k.k <= n): Snowflake can plan that as a Cartesian product (B12a: ~9 min
    -- per history year instead of ~1 s). Same rows either way.
    CREATE OR REPLACE TEMPORARY TABLE TMP_PLANT_MAP AS
    WITH c AS (SELECT REGION, WERKS, units,
                 SUM(units) OVER (PARTITION BY REGION ORDER BY WERKS ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum
          FROM TMP_PLANT)
    SELECT c.REGION, c.cum - c.units + f.value::INT AS t, c.WERKS
    FROM c, LATERAL FLATTEN(INPUT => ARRAY_GENERATE_RANGE(1, c.units + 1)) f;

    CREATE OR REPLACE TEMPORARY TABLE TMP_REGION_UNITS AS
    SELECT REGION, SUM(units) AS units FROM TMP_PLANT GROUP BY REGION;

    -- Customer (and supplier) countries per region, with the §2.1 shares.
    CREATE OR REPLACE TEMPORARY TABLE TMP_COUNTRY AS
    SELECT v.REGION, v.COUNTRY, v.CURRENCY, v.LO, v.HI
    FROM (VALUES
        ('AMER', 'USA', 'USD', 0.00, 0.60), ('AMER', 'CAN', 'CAD', 0.60, 0.75),
        ('AMER', 'MEX', 'MXN', 0.75, 0.90), ('AMER', 'BRA', 'BRL', 0.90, 1.00),
        ('EMEA', 'DEU', 'EUR', 0.00, 0.30), ('EMEA', 'GBR', 'GBP', 0.30, 0.55),
        ('EMEA', 'FRA', 'EUR', 0.55, 0.75), ('EMEA', 'NLD', 'EUR', 0.75, 0.90),
        ('EMEA', 'ESP', 'EUR', 0.90, 1.00),
        ('APAC', 'CHN', 'CNY', 0.00, 0.30), ('APAC', 'JPN', 'JPY', 0.30, 0.55),
        ('APAC', 'IND', 'INR', 0.55, 0.80), ('APAC', 'SGP', 'SGD', 0.80, 1.00)
    ) AS v(REGION, COUNTRY, CURRENCY, LO, HI);

    -- FX start rates, USD per unit (§2.1).
    CREATE OR REPLACE TEMPORARY TABLE TMP_CUR AS
    SELECT v.CUR, v.CUR_N, v.START_RATE
    FROM (VALUES ('EUR', 1, 1.10), ('GBP', 2, 1.30), ('JPY', 3, 0.0090), ('CNY', 4, 0.145),
                 ('INR', 5, 0.0135), ('SGD', 6, 0.73), ('CAD', 7, 0.76), ('MXN', 8, 0.052),
                 ('BRL', 9, 0.25)) AS v(CUR, CUR_N, START_RATE);

    -- Part categories (§2.1): subcategories, price and quantity ranges, short-ship factor (§3.3).
    CREATE OR REPLACE TEMPORARY TABLE TMP_CAT AS
    SELECT v.CAT_IDX, v.MATKL, v.SUBS, v.P_LO, v.P_HI, v.Q_LO, v.Q_HI, v.SHORT_F, v.W_LO, v.W_HI
    FROM (VALUES
        (0, 'ELECTRONICS',  'PASSIVES,MICROCONTROLLERS,SENSORS,CONNECTORS',       2.00, 400.0,  10,  2000, 0.8, 0.010,   2.0),
        (1, 'MECHANICAL',   'GEARBOXES,SHAFTS,BEARINGS,VALVES',                  20.00, 1500.0,  2,   300, 1.0, 1.000,  80.0),
        (2, 'RAW_MATERIAL', 'STEEL_RODS,ALUMINUM_INGOTS,COPPER_WIRE,POLYMER_RESIN', 5.00, 300.0, 50, 5000, 0.9, 5.000, 500.0),
        (3, 'PACKAGING',    'SEAL_FILM,PALLETS,CARTONS,FOAM_INSERTS',             0.50,  40.0, 100, 10000, 1.2, 0.100,  20.0),
        (4, 'CHEMICAL',     'LUBRICANTS,COATINGS,ADHESIVES,SOLVENTS',             5.00, 250.0,  20,  2000, 0.9, 0.500,  50.0),
        (5, 'FASTENERS',    'RIVETS,WASHERS,BOLTS,SCREWS',                        0.05,   5.0, 500, 20000, 1.2, 0.001,   0.2)
    ) AS v(CAT_IDX, MATKL, SUBS, P_LO, P_HI, Q_LO, Q_HI, SHORT_F, W_LO, W_HI);

    -- Carriers (§3.4): SLA, on-time offset, freight base (USD), activity, lanes served.
    CREATE OR REPLACE TEMPORARY TABLE TMP_CARRIER AS
    SELECT v.CARRIER_CD, v.SLA, v.OT_OFF, v.BASE_FREIGHT, v.ACTIVE_FROM::DATE AS ACTIVE_FROM, v.ACTIVE_TO::DATE AS ACTIVE_TO, v.LANES
    FROM (VALUES
        ('DHL_EXPRESS',      3,  0.02, 380, '1900-01-01', '2999-12-31', 'AMER,EMEA,APAC,CROSS'),
        ('FEDEX_FREIGHT',    4,  0.01, 300, '1900-01-01', '2999-12-31', 'AMER'),
        ('MAERSK_LOGISTICS', 9, -0.03, 450, '1900-01-01', '2999-12-31', 'APAC,CROSS'),
        ('KUEHNE_NAGEL',     5,  0.00, 320, '1900-01-01', '2999-12-31', 'EMEA'),
        ('DB_SCHENKER',      4,  0.00, 300, '1900-01-01', '2999-12-31', 'EMEA'),
        ('UPS_SUPPLY_CHAIN', 4,  0.01, 290, '1900-01-01', '2022-06-30', 'AMER'),
        ('XPO_LOGISTICS',    5, -0.02, 260, '1900-01-01', '2021-12-31', 'AMER'),
        ('CEVA_LOGISTICS',   6, -0.01, 350, '2019-01-01', '2999-12-31', 'APAC'),
        ('FLEXPORT',         7,  0.01, 400, '2022-07-01', '2999-12-31', 'AMER,CROSS')
    ) AS v(CARRIER_CD, SLA, OT_OFF, BASE_FREIGHT, ACTIVE_FROM, ACTIVE_TO, LANES);

    -- The carriers active on each day for each lane, numbered, for a uniform pick.
    CREATE OR REPLACE TEMPORARY TABLE TMP_CARRIER_DAY AS
    WITH cal AS (SELECT DATEADD(day, (ROW_NUMBER() OVER (ORDER BY SEQ8()) - 1)::INT, :s_date) AS d
                 FROM TABLE(GENERATOR(ROWCOUNT => :n_days))),
    lanes AS (SELECT c.CARRIER_CD, TRIM(f.value::VARCHAR) AS LANE, c.SLA, c.OT_OFF, c.BASE_FREIGHT, c.ACTIVE_FROM, c.ACTIVE_TO
              FROM TMP_CARRIER c, LATERAL SPLIT_TO_TABLE(c.LANES, ',') f)
    SELECT l.LANE, cal.d, l.CARRIER_CD, l.SLA, l.OT_OFF, l.BASE_FREIGHT,
           ROW_NUMBER() OVER (PARTITION BY l.LANE, cal.d ORDER BY l.CARRIER_CD) AS idx,
           COUNT(*) OVER (PARTITION BY l.LANE, cal.d) AS cnt
    FROM cal JOIN lanes l ON cal.d BETWEEN l.ACTIVE_FROM AND l.ACTIVE_TO;

    -- ── 2. Masters (§2.1): T001W, LFA1, MARA, KNA1 ──────────────────────────
    stage := 'masters';
    SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ INTO :t0;
    INSERT INTO WMS_SOURCE.T001W (WERKS, NAME1, LAND1, REGION_CD, PLANT_TYPE, CAPACITY_UNITS, LOAD_TS)
    SELECT WERKS, NAME1, LAND1, REGION, PLANT_TYPE, CAPACITY_UNITS,
           TIMESTAMPADD(minute, (120 + LEAST(180, FLOOR(181 * BITAND(HASH(:SEED, 'T001W', plant_num, 'load'), 4294967295) / 4294967295.0)))::INT,
                        DATEADD(day, 1, :s_date)::TIMESTAMP_NTZ)
    FROM TMP_PLANT;
    n_rows := SQLROWCOUNT;
    INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
    SELECT :run_id, :TARGET_DB, 'masters', 'T001W', NULL, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

    -- Suppliers: 150; tier 20/50/30%; region 35/30/35%; 70% onboarded before the history,
    -- 30% during years 3-10; 15 of the original suppliers are phased out (their sourcing
    -- rows end before END_DATE).
    CREATE OR REPLACE TEMPORARY TABLE TMP_SUP AS
    WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ8()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 150))),
    u AS (
        SELECT n,
            BITAND(HASH(:SEED, 'LFA1', n, 'tier'),    4294967295) / 4294967295.0 AS u_tier,
            BITAND(HASH(:SEED, 'LFA1', n, 'region'),  4294967295) / 4294967295.0 AS u_region,
            BITAND(HASH(:SEED, 'LFA1', n, 'country'), 4294967295) / 4294967295.0 AS u_country,
            BITAND(HASH(:SEED, 'LFA1', n, 'terms'),   4294967295) / 4294967295.0 AS u_terms,
            BITAND(HASH(:SEED, 'LFA1', n, 'lead'),    4294967295) / 4294967295.0 AS u_lead,
            BITAND(HASH(:SEED, 'LFA1', n, 'rel'),     4294967295) / 4294967295.0 AS u_rel,
            BITAND(HASH(:SEED, 'LFA1', n, 'old'),     4294967295) / 4294967295.0 AS u_old,
            BITAND(HASH(:SEED, 'LFA1', n, 'erdat'),   4294967295) / 4294967295.0 AS u_erdat,
            BITAND(HASH(:SEED, 'LFA1', n, 'phaseat'), 4294967295) / 4294967295.0 AS u_phaseat,
            BITAND(HASH(:SEED, 'LFA1', n, 'cur'),     4294967295) / 4294967295.0 AS u_cur
        FROM g),
    a AS (
        SELECT u.*,
            CASE WHEN u_tier < 0.20 THEN 1 WHEN u_tier < 0.70 THEN 2 ELSE 3 END AS tier,
            CASE WHEN u_region < 0.35 THEN 'AMER' WHEN u_region < 0.65 THEN 'EMEA' ELSE 'APAC' END AS region,
            u_old < 0.70 AS is_original,
            CASE WHEN u_old < 0.70 THEN DATEADD(day, (-(1 + LEAST(3649, FLOOR(u_erdat * 3650))))::INT, :s_date)
                 ELSE DATEADD(day, (LEAST(:late_span, FLOOR(u_erdat * (:late_span + 1))))::INT, :late_start) END AS erdat,
            ROW_NUMBER() OVER (PARTITION BY (u_old < 0.70) ORDER BY HASH(:SEED, 'LFA1', n, 'phase'), n) AS phase_rank
        FROM u)
    SELECT a.n, 'SUP' || LPAD(a.n, 5, '0') AS LIFNR, a.tier, a.region, c.COUNTRY, c.CURRENCY, a.erdat,
           GREATEST(a.erdat, :s_date) AS eff_date, a.is_original,
           (a.is_original AND a.phase_rank <= 15) AS is_phased,
           CASE WHEN a.is_original AND a.phase_rank <= 15
                THEN DATEADD(day, (FLOOR(a.u_phaseat * 1826))::INT, DATEADD(year, 4, :s_date)) END AS phase_date,
           a.u_terms, a.u_lead, a.u_rel, a.u_cur
    FROM a JOIN TMP_COUNTRY c
      ON c.REGION = a.region AND a.u_country >= c.LO AND (a.u_country < c.HI OR c.HI >= 1);

    SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ INTO :t0;
    INSERT INTO SRM_SOURCE.LFA1 (LIFNR, NAME1, LAND1, REGIO, SUPP_TIER, LEAD_TM_DAYS, RELIAB_SCR, ZTERM, EMAIL, ERDAT, LOAD_TS)
    SELECT LIFNR,
           DECODE(MOD(n, 12), 0, 'Apex Industrial Components', 1, 'Nordic Microelectronics', 2, 'Pacific Rim Materials',
                  3, 'Shenzhen Precision Tech', 4, 'Bavarian Fastener Works', 5, 'Global Polymers & Chemical',
                  6, 'Atlas Heavy Mechanical', 7, 'Kyoto Semiconductor Corp', 8, 'Vanguard Advanced Packaging',
                  9, 'Stuttgart Precision Dynamics', 10, 'Americas Raw Metal Co', 'Taichung Electronics Group')
               || ' ' || LPAD(n, 3, '0'),
           COUNTRY, region, tier,
           CASE tier WHEN 1 THEN 5 + LEAST(15, FLOOR(u_lead * 16))
                     WHEN 2 THEN 10 + LEAST(25, FLOOR(u_lead * 26))
                     ELSE 15 + LEAST(30, FLOOR(u_lead * 31)) END,
           ROUND(CASE tier WHEN 1 THEN 0.90 + 0.09 * u_rel WHEN 2 THEN 0.80 + 0.15 * u_rel ELSE 0.70 + 0.18 * u_rel END, 2),
           CASE WHEN u_terms < 0.2 THEN 'NET30' WHEN u_terms < 0.4 THEN 'NET60' WHEN u_terms < 0.6 THEN '2/10 NET30'
                WHEN u_terms < 0.8 THEN 'NET45' ELSE 'NET90' END,
           'contact.sup' || LPAD(n, 3, '0') || '@supplier-forge.net',
           erdat,
           TIMESTAMPADD(minute, (120 + LEAST(180, FLOOR(181 * BITAND(HASH(:SEED, 'LFA1', n, 'load'), 4294967295) / 4294967295.0)))::INT,
                        DATEADD(day, 1, eff_date)::TIMESTAMP_NTZ)
    FROM TMP_SUP;
    n_rows := SQLROWCOUNT;
    INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
    SELECT :run_id, :TARGET_DB, 'masters', 'LFA1', NULL, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

    -- Parts: 6 categories × 4 subcategories × 50 parts = 1,200; ~15% critical.
    CREATE OR REPLACE TEMPORARY TABLE TMP_PART AS
    WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ8()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 1200))),
    b AS (SELECT n, FLOOR((n - 1) / 200) AS cat_idx, FLOOR(MOD(n - 1, 200) / 50) AS sub_idx,
                 BITAND(HASH(:SEED, 'MARA', n, 'price'),  4294967295) / 4294967295.0 AS u_price,
                 BITAND(HASH(:SEED, 'MARA', n, 'weight'), 4294967295) / 4294967295.0 AS u_weight,
                 BITAND(HASH(:SEED, 'MARA', n, 'crit'),   4294967295) / 4294967295.0 AS u_crit
          FROM g)
    SELECT b.n, 'MAT' || LPAD(b.n, 6, '0') AS MATNR, b.cat_idx, c.MATKL,
           SPLIT_PART(c.SUBS, ',', b.sub_idx + 1) AS SUBCAT,
           ROUND(EXP(LN(c.P_LO) + b.u_price * (LN(c.P_HI) - LN(c.P_LO))), 2) AS STPRS,
           ROUND(EXP(LN(c.W_LO) + b.u_weight * (LN(c.W_HI) - LN(c.W_LO))), 3) AS BRGEW,
           b.u_crit < 0.15 AS CRIT_FLG,
           c.Q_LO, c.Q_HI, c.SHORT_F
    FROM b JOIN TMP_CAT c ON c.CAT_IDX = b.cat_idx;

    SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ INTO :t0;
    INSERT INTO SRM_SOURCE.MARA (MATNR, MAKTX, MATKL, SUBCAT, STPRS, BRGEW, CRIT_FLG, LOAD_TS)
    SELECT MATNR, INITCAP(REPLACE(SUBCAT, '_', ' ')) || ' Model-' || LPAD(n, 4, '0'), MATKL, SUBCAT, STPRS, BRGEW, CRIT_FLG,
           TIMESTAMPADD(minute, (120 + LEAST(180, FLOOR(181 * BITAND(HASH(:SEED, 'MARA', n, 'load'), 4294967295) / 4294967295.0)))::INT,
                        DATEADD(day, 1, :s_date)::TIMESTAMP_NTZ)
    FROM TMP_PART;
    n_rows := SQLROWCOUNT;
    INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
    SELECT :run_id, :TARGET_DB, 'masters', 'MARA', NULL, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

    -- Customers: 2,000; region 40/35/25% overall (originals lean AMER/EMEA, newcomers lean
    -- APAC, onboarded late); segment 15/35/50%. Order weight: ENTERPRISE 6, MIDMARKET 2.5,
    -- SMB 1 (×4 to keep integers), and ×1.5 for APAC newcomers so APAC's order share grows
    -- from ~20% to ~30% over the decade (§2.1).
    CREATE OR REPLACE TEMPORARY TABLE TMP_CUST AS
    WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ8()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 2000))),
    u AS (
        SELECT n,
            BITAND(HASH(:SEED, 'KNA1', n, 'old'),     4294967295) / 4294967295.0 AS u_old,
            BITAND(HASH(:SEED, 'KNA1', n, 'region'),  4294967295) / 4294967295.0 AS u_region,
            BITAND(HASH(:SEED, 'KNA1', n, 'country'), 4294967295) / 4294967295.0 AS u_country,
            BITAND(HASH(:SEED, 'KNA1', n, 'segment'), 4294967295) / 4294967295.0 AS u_segment,
            BITAND(HASH(:SEED, 'KNA1', n, 'erdat'),   4294967295) / 4294967295.0 AS u_erdat,
            BITAND(HASH(:SEED, 'KNA1', n, 'limit'),   4294967295) / 4294967295.0 AS u_limit,
            BITAND(HASH(:SEED, 'KNA1', n, 'cur'),     4294967295) / 4294967295.0 AS u_cur
        FROM g),
    a AS (
        SELECT u.*, u_old < 0.50 AS is_original,
            CASE WHEN u_old < 0.50
                 THEN CASE WHEN u_region < 0.42 THEN 'AMER' WHEN u_region < 0.81 THEN 'EMEA' ELSE 'APAC' END
                 ELSE CASE WHEN u_region < 0.38 THEN 'AMER' WHEN u_region < 0.69 THEN 'EMEA' ELSE 'APAC' END END AS region,
            CASE WHEN u_segment < 0.15 THEN 'ENTERPRISE' WHEN u_segment < 0.50 THEN 'MIDMARKET' ELSE 'SMB' END AS segment
        FROM u),
    b AS (
        SELECT a.*,
            CASE WHEN is_original THEN DATEADD(day, (-(1 + LEAST(3649, FLOOR(u_erdat * 3650))))::INT, :s_date)
                 ELSE DATEADD(day, (LEAST(:cust_span, FLOOR(:cust_span * CASE WHEN region = 'APAC' THEN SQRT(u_erdat) ELSE u_erdat END)))::INT, :s_date)
            END AS erdat,
            CASE segment WHEN 'ENTERPRISE' THEN 24 WHEN 'MIDMARKET' THEN 10 ELSE 4 END
                * CASE WHEN region = 'APAC' AND NOT is_original THEN 1.5 ELSE 1 END AS weight
        FROM a)
    SELECT b.n, 'CUST' || LPAD(b.n, 5, '0') AS KUNNR, b.region, c.COUNTRY, c.CURRENCY AS local_currency, b.segment,
           b.erdat, GREATEST(b.erdat, :s_date) AS eff_date, b.is_original, b.weight::NUMBER AS weight,
           CASE WHEN c.COUNTRY = 'USA' THEN 'USD' WHEN b.u_cur < 0.50 THEN c.CURRENCY ELSE 'USD' END AS waerk,
           SUM(b.weight::NUMBER) OVER (ORDER BY GREATEST(b.erdat, :s_date), b.n ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum,
           b.u_limit
    FROM b JOIN TMP_COUNTRY c
      ON c.REGION = b.region AND b.u_country >= c.LO AND (b.u_country < c.HI OR c.HI >= 1);

    SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ INTO :t0;
    INSERT INTO ERP_SOURCE.KNA1 (KUNNR, NAME1, EMAIL, LAND1, REGIO, KTOKD, KLIMK, ERDAT, LOAD_TS)
    SELECT KUNNR,
           DECODE(MOD(n, 10), 0, 'Acrobat Aerospace Systems', 1, 'Beacon Global Logistics', 2, 'Crestview Automotive Group',
                  3, 'Delta Energy Dynamics', 4, 'Echo Medical Devices', 5, 'Frontier Renewable Tech',
                  6, 'Genesis Consumer Goods', 7, 'Horizon Industrial Equipment', 8, 'Insignia Electronics LLC',
                  'Keystone Power Systems') || ' - Division ' || LPAD(n, 4, '0'),
           'accounts.payable' || LPAD(n, 4, '0') || '@clientcorp.com',
           COUNTRY, region, segment,
           ROUND(CASE segment WHEN 'ENTERPRISE' THEN EXP(LN(1000000) + u_limit * (LN(5000000) - LN(1000000)))
                              WHEN 'MIDMARKET'  THEN EXP(LN(200000)  + u_limit * (LN(1000000) - LN(200000)))
                              ELSE                    EXP(LN(20000)   + u_limit * (LN(200000)  - LN(20000))) END, 2),
           erdat,
           TIMESTAMPADD(minute, (120 + LEAST(180, FLOOR(181 * BITAND(HASH(:SEED, 'KNA1', n, 'load'), 4294967295) / 4294967295.0)))::INT,
                        DATEADD(day, 1, eff_date)::TIMESTAMP_NTZ)
    FROM TMP_CUST;
    n_rows := SQLROWCOUNT;
    INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
    SELECT :run_id, :TARGET_DB, 'masters', 'KNA1', NULL, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

    -- Weighted customer pick: weight unit t (1..total) -> customer. Customers are ordered by
    -- the day they become active, so "active on day d" is a prefix: t <= TMP_DAYS.w_cust.
    CREATE OR REPLACE TEMPORARY TABLE TMP_CUST_MAP AS
    SELECT c.cum - c.weight + f.value::INT AS t, c.KUNNR
    FROM TMP_CUST c, LATERAL FLATTEN(INPUT => ARRAY_GENERATE_RANGE(1, c.weight + 1)) f;

    -- ── 3. FX rates (TCURR, §2.1) ───────────────────────────────────────────
    -- Business days (Mon-Fri) from one week before the history to L; ~1% holidays (none
    -- before the history start). A bounded, mean-reverting path around the start rate: two
    -- slow waves plus a small daily wobble, in log space (daily step well under 0.6%).
    stage := 'fx';
    SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ INTO :t0;
    INSERT INTO ERP_SOURCE.TCURR (KURST, FCURR, TCURR, GDATU, UKURS, LOAD_TS)
    WITH cal AS (SELECT DATEADD(day, (ROW_NUMBER() OVER (ORDER BY SEQ8()) - 1)::INT, :fx_start) AS d
                 FROM TABLE(GENERATOR(ROWCOUNT => :n_fx_days))),
    bd AS (SELECT d, DATEDIFF(day, :fx_start, d) AS t FROM cal
           WHERE DAYOFWEEKISO(d) <= 5
             AND NOT (d >= :s_date
                      AND BITAND(HASH(:SEED, 'TCURR', DATEDIFF(day, :fx_start, d), 'holiday'), 4294967295) / 4294967295.0 < 0.01))
    SELECT 'M', c.CUR, 'USD', bd.d,
           ROUND(c.START_RATE * EXP(
                   0.06 * SIN(2 * PI() * bd.t / 730  + 2 * PI() * BITAND(HASH(:SEED, 'TCURR', c.CUR_N, 'phase1'), 4294967295) / 4294967295.0)
                 + 0.04 * SIN(2 * PI() * bd.t / 2900 + 2 * PI() * BITAND(HASH(:SEED, 'TCURR', c.CUR_N, 'phase2'), 4294967295) / 4294967295.0)
                 + 0.004 * (BITAND(HASH(:SEED, 'TCURR', c.CUR_N, bd.t, 'noise'), 4294967295) / 4294967295.0 - 0.5)), 9),
           TIMESTAMPADD(minute, (120 + LEAST(180, FLOOR(181 * BITAND(HASH(:SEED, 'TCURR', c.CUR_N, bd.t, 'load'), 4294967295) / 4294967295.0)))::INT,
                        DATEADD(day, 1, GREATEST(bd.d, :fx_start))::TIMESTAMP_NTZ)
    FROM bd CROSS JOIN TMP_CUR c;
    n_rows := SQLROWCOUNT;
    INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
    SELECT :run_id, :TARGET_DB, 'fx', 'TCURR', NULL, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

    -- Daily rate lookup: the latest TCURR rate on or before each day (M05 rule), USD = 1.
    CREATE OR REPLACE TEMPORARY TABLE TMP_FX AS
    WITH cal AS (SELECT DATEADD(day, (ROW_NUMBER() OVER (ORDER BY SEQ8()) - 1)::INT, :fx_start) AS d
                 FROM TABLE(GENERATOR(ROWCOUNT => :n_fx_days))),
    grid AS (SELECT c.CUR, cal.d, t.UKURS
             FROM cal CROSS JOIN TMP_CUR c
             LEFT JOIN ERP_SOURCE.TCURR t ON t.FCURR = c.CUR AND t.GDATU = cal.d AND t.KURST = 'M' AND t.TCURR = 'USD')
    SELECT CUR, d, LAST_VALUE(UKURS IGNORE NULLS) OVER (PARTITION BY CUR ORDER BY d ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS rate
    FROM grid
    UNION ALL
    SELECT 'USD', d, 1 FROM cal;

    -- ── 4. Sourcing (§2.1): one valid primary per part on every date ───────
    -- 75% of parts keep one primary for 10 years; 25% change it once or twice. A primary is
    -- picked among the suppliers that are active at the segment start and never phased out.
    -- 0-2 secondary rows per part, from any supplier, valid from its onboarding (to its
    -- phase-out). Prices are STPRS × U(0.85, 1.05), in the supplier's currency on 30% of rows.
    stage := 'sourcing';
    SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ INTO :t0;
    CREATE OR REPLACE TEMPORARY TABLE TMP_SUP_P AS
    SELECT LIFNR, eff_date, ROW_NUMBER() OVER (ORDER BY eff_date, LIFNR) AS r
    FROM TMP_SUP WHERE NOT is_phased;

    CREATE OR REPLACE TEMPORARY TABLE TMP_SRC AS
    WITH p AS (
        SELECT n AS part_n, MATNR, STPRS,
            BITAND(HASH(:SEED, 'SOURCING', n, 'chg'),  4294967295) / 4294967295.0 AS u_chg,
            BITAND(HASH(:SEED, 'SOURCING', n, 'chg2'), 4294967295) / 4294967295.0 AS u_chg2,
            BITAND(HASH(:SEED, 'SOURCING', n, 'd1'),   4294967295) / 4294967295.0 AS u_d1,
            BITAND(HASH(:SEED, 'SOURCING', n, 'd2'),   4294967295) / 4294967295.0 AS u_d2,
            BITAND(HASH(:SEED, 'SOURCING', n, 'nsec'), 4294967295) / 4294967295.0 AS u_nsec
        FROM TMP_PART),
    c AS (SELECT p.*, CASE WHEN u_chg < 0.75 THEN 0 WHEN u_chg2 < 0.60 THEN 1 ELSE 2 END AS n_chg FROM p),
    d AS (SELECT c.*,
            DATEADD(day, (365 + FLOOR(u_d1 * CASE WHEN n_chg = 1 THEN 2920 ELSE 1460 END))::INT, :s_date) AS d1
          FROM c),
    e AS (SELECT d.*, DATEADD(day, (365 + FLOOR(u_d2 * 1095))::INT, d1) AS d2 FROM d),
    kk AS (SELECT e.*, f.value::INT AS k  -- segments 0 .. n_chg (FLATTEN, not a range join)
           FROM e, LATERAL FLATTEN(INPUT => ARRAY_GENERATE_RANGE(0, e.n_chg + 1)) f),
    seg AS (
        SELECT kk.part_n, kk.MATNR, kk.STPRS, kk.k,
            CASE kk.k WHEN 0 THEN :s_date WHEN 1 THEN DATEADD(day, 1, kk.d1) ELSE DATEADD(day, 1, kk.d2) END AS vdatu,
            CASE WHEN kk.k = kk.n_chg THEN NULL WHEN kk.k = 0 THEN kk.d1 ELSE kk.d2 END AS bdatu
        FROM kk),
    cnt AS (SELECT s.part_n, s.k, COUNT(*) AS n_elig
            FROM seg s JOIN TMP_SUP_P sp ON sp.eff_date <= s.vdatu GROUP BY s.part_n, s.k),
    prim AS (
        SELECT s.part_n, s.MATNR, s.STPRS, sp.LIFNR, TRUE AS IS_PRIMARY, s.vdatu, s.bdatu, s.k
        FROM seg s JOIN cnt ON cnt.part_n = s.part_n AND cnt.k = s.k
        JOIN TMP_SUP_P sp ON sp.r = LEAST(cnt.n_elig,
             1 + FLOOR(cnt.n_elig * BITAND(HASH(:SEED, 'SOURCING', s.part_n, s.k, 'primary'), 4294967295) / 4294967295.0))::INT),
    ks AS (SELECT c.part_n, f.value::INT AS j  -- 0, 1 or 2 secondary rows (FLATTEN, not a range join)
           FROM c, LATERAL FLATTEN(INPUT => ARRAY_GENERATE_RANGE(1,
                CASE WHEN c.u_nsec < 0.45 THEN 0 WHEN c.u_nsec < 0.85 THEN 1 ELSE 2 END + 1)) f),
    sec AS (
        SELECT c.part_n, c.MATNR, c.STPRS, su.LIFNR, FALSE AS IS_PRIMARY,
               su.eff_date AS vdatu, su.phase_date AS bdatu, 10 + ks.j AS k
        FROM c JOIN ks ON ks.part_n = c.part_n
        JOIN TMP_SUP su ON su.n = LEAST(150, 1 + FLOOR(150 * BITAND(HASH(:SEED, 'SOURCING', c.part_n, ks.j, 'secondary'), 4294967295) / 4294967295.0))::INT
        WHERE NOT EXISTS (SELECT 1 FROM prim pr WHERE pr.part_n = c.part_n AND pr.LIFNR = su.LIFNR)
        QUALIFY ROW_NUMBER() OVER (PARTITION BY c.part_n, su.LIFNR ORDER BY ks.j) = 1),
    allrows AS (SELECT * FROM prim UNION ALL SELECT * FROM sec)
    SELECT a.*, su.CURRENCY AS sup_currency,
           CASE WHEN su.CURRENCY <> 'USD'
                 AND BITAND(HASH(:SEED, 'SOURCING', a.part_n, a.k, 'cur'), 4294967295) / 4294967295.0 < 0.30
                THEN su.CURRENCY ELSE 'USD' END AS WAERS,
           a.STPRS * (0.85 + 0.20 * BITAND(HASH(:SEED, 'SOURCING', a.part_n, a.k, 'price'), 4294967295) / 4294967295.0) AS price_usd,
           ROW_NUMBER() OVER (ORDER BY a.MATNR, a.vdatu, a.IS_PRIMARY DESC, a.LIFNR) AS src_n
    FROM allrows a JOIN TMP_SUP su ON su.LIFNR = a.LIFNR;

    INSERT INTO SRM_SOURCE.SOURCING (SOURCE_ID, LIFNR, MATNR, IS_PRIMARY, CONTRACT_PRICE, WAERS, VDATU, BDATU, LOAD_TS)
    SELECT 'SRC' || LPAD(s.src_n, 6, '0'), s.LIFNR, s.MATNR, s.IS_PRIMARY,
           ROUND(s.price_usd / fx.rate, 2), s.WAERS, s.vdatu, s.bdatu,
           TIMESTAMPADD(minute, (120 + LEAST(180, FLOOR(181 * BITAND(HASH(:SEED, 'SOURCING', s.src_n, 'load'), 4294967295) / 4294967295.0)))::INT,
                        DATEADD(day, 1, GREATEST(s.vdatu, :s_date))::TIMESTAMP_NTZ)
    FROM TMP_SRC s JOIN TMP_FX fx ON fx.CUR = s.WAERS AND fx.d = s.vdatu;
    n_rows := SQLROWCOUNT;
    INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
    SELECT :run_id, :TARGET_DB, 'sourcing', 'SOURCING', NULL, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

    -- ── 5. What each plant stocks: 300 of the 1,200 parts (§3.7) ───────────
    CREATE OR REPLACE TEMPORARY TABLE TMP_STOCK AS
    WITH r AS (
        SELECT pl.WERKS, pl.plant_num, pt.n AS part_n, pt.MATNR,
               ROW_NUMBER() OVER (PARTITION BY pl.WERKS ORDER BY HASH(:SEED, 'MARD', pl.plant_num, pt.n, 'stock'), pt.n) AS stock_rank
        FROM TMP_PLANT pl CROSS JOIN TMP_PART pt)
    SELECT r.WERKS, r.plant_num, r.part_n, r.MATNR, r.stock_rank,
           r.plant_num * 10000 + r.part_n AS pair_n,
           EXP(LN(5) + (LN(200) - LN(5)) * BITAND(HASH(:SEED, 'MARD', r.plant_num * 10000 + r.part_n, 'usage'), 4294967295) / 4294967295.0) AS usage_base,
           12 + 36 * BITAND(HASH(:SEED, 'MARD', r.plant_num * 10000 + r.part_n, 'cover'), 4294967295) / 4294967295.0 AS cover_base,
           7 + 7 * BITAND(HASH(:SEED, 'MARD', r.plant_num * 10000 + r.part_n, 'reorder'), 4294967295) / 4294967295.0 AS reorder_f
    FROM r WHERE r.stock_rank <= 300;

    -- ── 6. The order calendar (§3.1) ────────────────────────────────────────
    -- w(d) = growth × season × weekday × shock; orders(d) by cumulative rounding, so the
    -- total is exact. NUMBER arithmetic (not FLOAT) keeps the sums identical on every run.
    stage := 'calendar';
    CREATE OR REPLACE TEMPORARY TABLE TMP_DAYS AS
    WITH cal AS (SELECT DATEADD(day, (ROW_NUMBER() OVER (ORDER BY SEQ8()) - 1)::INT, :s_date) AS d
                 FROM TABLE(GENERATOR(ROWCOUNT => :n_days))),
    w AS (
        SELECT d,
            (POWER(1.08, DATEDIFF(day, :s_date, d) / 365.25)
             * CASE MONTH(d) WHEN 1 THEN 0.95 WHEN 2 THEN 0.85 WHEN 3 THEN 1.00 WHEN 4 THEN 0.98 WHEN 5 THEN 1.00
                             WHEN 6 THEN 1.02 WHEN 7 THEN 0.97 WHEN 8 THEN 0.98 WHEN 9 THEN 1.05 WHEN 10 THEN 1.10
                             WHEN 11 THEN 1.18 ELSE 1.05 END
             * CASE DAYOFWEEKISO(d) WHEN 6 THEN 0.35 WHEN 7 THEN 0.15 ELSE 1.00 END
             * CASE WHEN d BETWEEN '2020-04-01'::DATE AND '2020-06-30'::DATE THEN 0.80 ELSE 1.00 END
            )::NUMBER(20, 10) AS w
        FROM cal),
    c AS (SELECT d, w,
                 SUM(w) OVER (ORDER BY d ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cw,
                 SUM(w) OVER () AS tw
          FROM w),
    r AS (SELECT d, ROUND(:n_orders * cw / tw)::NUMBER AS cum FROM c),
    wc AS (SELECT eff_date, SUM(weight) AS wsum FROM TMP_CUST GROUP BY eff_date)
    SELECT r.d, YEAR(r.d) AS yr,
           COALESCE(LAG(r.cum) OVER (ORDER BY r.d), 0) AS cum_prev,
           r.cum - COALESCE(LAG(r.cum) OVER (ORDER BY r.d), 0) AS cnt,
           SUM(COALESCE(wc.wsum, 0)) OVER (ORDER BY r.d ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS w_cust
    FROM r LEFT JOIN wc ON wc.eff_date = r.d;

    SELECT MAX(cnt) INTO :max_k FROM TMP_DAYS;

    -- Snapshot days for inventory: every Monday, plus every day of the last 90 days (§3.7).
    CREATE OR REPLACE TEMPORARY TABLE TMP_SNAP AS
    SELECT d, YEAR(d) AS yr FROM TMP_DAYS
    WHERE DAYOFWEEKISO(d) = 1 OR d > DATEADD(day, -90, :l_date);

    -- ── 7. Orders, lines and shipments, one history year per statement (§2.2) ─
    FOR y IN y0 TO y1 DO
        stage := 'orders ' || y;

        -- Orders of year y: day d gets cnt(d) orders, numbered cum_prev + 1 … cum.
        CREATE OR REPLACE TEMPORARY TABLE TMP_O AS
        WITH o AS (SELECT d.d AS audat, d.cum_prev + f.value::INT AS n, d.w_cust
              FROM TMP_DAYS d, LATERAL FLATTEN(INPUT => ARRAY_GENERATE_RANGE(1, d.cnt + 1)) f
              WHERE d.yr = :y AND d.cnt > 0),
        u AS (
            SELECT o.*,
                BITAND(HASH(:SEED, 'VBAK', o.n, 'cust'),   4294967295) / 4294967295.0 AS u_cust,
                BITAND(HASH(:SEED, 'VBAK', o.n, 'prio'),   4294967295) / 4294967295.0 AS u_prio,
                BITAND(HASH(:SEED, 'VBAK', o.n, 'cancel'), 4294967295) / 4294967295.0 AS u_cancel,
                BITAND(HASH(:SEED, 'VBAK', o.n, 'proc'),   4294967295) / 4294967295.0 AS u_proc,
                BITAND(HASH(:SEED, 'VBAK', o.n, 'lines'),  4294967295) / 4294967295.0 AS u_lines,
                BITAND(HASH(:SEED, 'VBAK', o.n, 'conf'),   4294967295) / 4294967295.0 AS u_conf,
                BITAND(HASH(:SEED, 'VBAK', o.n, 'confd'),  4294967295) / 4294967295.0 AS u_confd,
                BITAND(HASH(:SEED, 'VBAK', o.n, 'erdat'),  4294967295) / 4294967295.0 AS u_erdat,
                BITAND(HASH(:SEED, 'VBAK', o.n, 'load'),   4294967295) / 4294967295.0 AS u_load,
                BITAND(HASH(:SEED, 'VBAK', o.n, 'inreg'),  4294967295) / 4294967295.0 AS u_inreg,
                BITAND(HASH(:SEED, 'VBAK', o.n, 'plant'),  4294967295) / 4294967295.0 AS u_plant,
                BITAND(HASH(:SEED, 'VBAK', o.n, 'any'),    4294967295) / 4294967295.0 AS u_any
            FROM o),
        a AS (
            SELECT u.*, cm.KUNNR, cu.region AS cust_region, cu.COUNTRY AS cust_country, cu.segment, cu.waerk,
                CASE WHEN u.u_prio < 0.15 THEN 'HIGH' WHEN u.u_prio < 0.85 THEN 'NORMAL' ELSE 'LOW' END AS prio,
                u.u_cancel < 0.04 AS is_cancelled
            FROM u
            JOIN TMP_CUST_MAP cm ON cm.t = LEAST(u.w_cust, 1 + FLOOR(u.u_cust * u.w_cust))::INT
            JOIN TMP_CUST cu ON cu.KUNNR = cm.KUNNR),
        b AS (
            SELECT a.*,
                DATEADD(day, (CASE a.prio WHEN 'HIGH' THEN 1 + LEAST(1, FLOOR(a.u_proc * 2))
                                         WHEN 'NORMAL' THEN 2 + LEAST(2, FLOOR(a.u_proc * 3))
                                         ELSE 3 + LEAST(3, FLOOR(a.u_proc * 4)) END)::INT, a.audat) AS dptbg,
                CASE WHEN a.segment = 'ENTERPRISE' THEN
                        CASE WHEN a.u_lines < 0.08 THEN 1 WHEN a.u_lines < 0.28 THEN 2 WHEN a.u_lines < 0.54 THEN 3
                             WHEN a.u_lines < 0.72 THEN 4 WHEN a.u_lines < 0.84 THEN 5 WHEN a.u_lines < 0.92 THEN 6
                             WHEN a.u_lines < 0.97 THEN 7 ELSE 8 END
                     ELSE
                        CASE WHEN a.u_lines < 0.20 THEN 1 WHEN a.u_lines < 0.50 THEN 2 WHEN a.u_lines < 0.75 THEN 3
                             WHEN a.u_lines < 0.87 THEN 4 WHEN a.u_lines < 0.94 THEN 5 WHEN a.u_lines < 0.98 THEN 6
                             WHEN a.u_lines < 0.99 THEN 7 ELSE 8 END
                END AS nlines
            FROM a)
        SELECT b.*, (NOT b.is_cancelled AND b.dptbg <= :l_date) AS is_shipped,
               CASE WHEN b.u_inreg < 0.85 THEN pm.WERKS
                    ELSE 'PL' || LPAD(LEAST(12, 1 + FLOOR(b.u_any * 12))::INT, 2, '0') END AS home_werks
        FROM b
        JOIN TMP_REGION_UNITS ru ON ru.REGION = b.cust_region
        JOIN TMP_PLANT_MAP pm ON pm.REGION = b.cust_region AND pm.t = LEAST(ru.units, 1 + FLOOR(b.u_plant * ru.units))::INT;

        -- Lines: the order's home plant (in the customer's region 85%, capacity-weighted;
        -- else any plant), and another plant on 3% of lines, so an order ships ~1.1 times
        -- (§2.2; a per-line plant would give ~2.3 shipments per order). A part the plant stocks; quantity log-uniform per category; price STPRS × U(1.15, 1.60)
        -- in the order currency; short-shipped with p = 0.20 (0.27 in 2021) × category factor.
        CREATE OR REPLACE TEMPORARY TABLE TMP_L AS
        WITH k AS (SELECT o.*, f.value::INT AS line_no  -- lines 1 .. nlines (FLATTEN, not a range join)
                   FROM TMP_O o, LATERAL FLATTEN(INPUT => ARRAY_GENERATE_RANGE(1, o.nlines + 1)) f),
        b AS (
            SELECT o.n, o.audat, o.KUNNR, o.cust_region, o.waerk, o.is_shipped, o.home_werks, o.line_no,
                BITAND(HASH(:SEED, 'VBAP', o.n, o.line_no, 'other'),  4294967295) / 4294967295.0 AS u_other,
                BITAND(HASH(:SEED, 'VBAP', o.n, o.line_no, 'any'),    4294967295) / 4294967295.0 AS u_any,
                BITAND(HASH(:SEED, 'VBAP', o.n, o.line_no, 'part'),   4294967295) / 4294967295.0 AS u_part,
                BITAND(HASH(:SEED, 'VBAP', o.n, o.line_no, 'qty'),    4294967295) / 4294967295.0 AS u_qty,
                BITAND(HASH(:SEED, 'VBAP', o.n, o.line_no, 'price'),  4294967295) / 4294967295.0 AS u_price,
                BITAND(HASH(:SEED, 'VBAP', o.n, o.line_no, 'short'),  4294967295) / 4294967295.0 AS u_short,
                BITAND(HASH(:SEED, 'VBAP', o.n, o.line_no, 'shortq'), 4294967295) / 4294967295.0 AS u_shortq,
                BITAND(HASH(:SEED, 'VBAP', o.n, o.line_no, 'load'),   4294967295) / 4294967295.0 AS u_load
            FROM k o),
        p AS (
            SELECT b.*,
                CASE WHEN b.u_other < 0.03 THEN 'PL' || LPAD(LEAST(12, 1 + FLOOR(b.u_any * 12))::INT, 2, '0')
                     ELSE b.home_werks END AS werks
            FROM b)
        SELECT p.n, p.audat, p.line_no, p.werks, p.is_shipped, p.u_load, s.MATNR,
               ROUND(EXP(LN(pt.Q_LO) + p.u_qty * (LN(pt.Q_HI) - LN(pt.Q_LO)))) AS kwmeng,
               pt.STPRS * (1.15 + 0.45 * p.u_price) AS price_usd, p.waerk,
               CASE WHEN YEAR(p.audat) = 2021 THEN 0.27 ELSE 0.20 END * pt.SHORT_F AS p_short,
               p.u_short, p.u_shortq
        FROM p
        JOIN TMP_STOCK s ON s.WERKS = p.werks AND s.stock_rank = LEAST(300, 1 + FLOOR(p.u_part * 300))::INT
        JOIN TMP_PART pt ON pt.MATNR = s.MATNR;

        -- Shipments: one per distinct (order, plant) of a shipped order; 5% split in two (the
        -- second part ships 1-2 days later, if by L). Carrier: an active one serving the
        -- lane (the plant's region, or CROSS). On time with p_ot (§3.5): ACT = PROM - 0..2,
        -- else PROM + 1..6; NULL while in transit (ACT > L). Costs in USD (§3.6), stored in
        -- USD for US plants, else the plant currency on 55% of shipments.
        CREATE OR REPLACE TEMPORARY TABLE TMP_S AS
        WITH g AS (SELECT DISTINCT n, werks FROM TMP_L WHERE is_shipped),
        sp AS (   -- part 1 always; part 2 on the 5% split (UNION ALL, not an OR join: see C08_run.md)
            SELECT g.n, g.werks, 1 AS part_no, SUBSTR(g.werks, 3)::NUMBER AS plant_num FROM g
            UNION ALL
            SELECT g.n, g.werks, 2 AS part_no, SUBSTR(g.werks, 3)::NUMBER AS plant_num FROM g
            WHERE BITAND(HASH(:SEED, 'VTTK', g.n, SUBSTR(g.werks, 3)::NUMBER, 'split'), 4294967295) / 4294967295.0 < 0.05),
        u AS (
            SELECT sp.*, o.KUNNR, o.prio, o.cust_region, o.cust_country, pl.REGION AS plant_region,
                   pl.LAND1 AS plant_country, pl.CURRENCY AS plant_currency, pl.ot_offset,
                   DATEADD(day, (CASE WHEN sp.part_no = 1 THEN 0
                                     ELSE 1 + LEAST(1, FLOOR(2 * BITAND(HASH(:SEED, 'VTTK', sp.n, sp.plant_num, sp.part_no, 'lag'), 4294967295) / 4294967295.0))
                                END)::INT, o.dptbg) AS dptbg,
                   BITAND(HASH(:SEED, 'VTTK', sp.n, sp.plant_num, sp.part_no, 'carrier'), 4294967295) / 4294967295.0 AS u_car,
                   BITAND(HASH(:SEED, 'VTTK', sp.n, sp.plant_num, sp.part_no, 'ontime'),  4294967295) / 4294967295.0 AS u_ot,
                   BITAND(HASH(:SEED, 'VTTK', sp.n, sp.plant_num, sp.part_no, 'days'),    4294967295) / 4294967295.0 AS u_days,
                   BITAND(HASH(:SEED, 'VTTK', sp.n, sp.plant_num, sp.part_no, 'weight'),  4294967295) / 4294967295.0 AS u_w,
                   BITAND(HASH(:SEED, 'VTTK', sp.n, sp.plant_num, sp.part_no, 'duty'),    4294967295) / 4294967295.0 AS u_duty,
                   BITAND(HASH(:SEED, 'VTTK', sp.n, sp.plant_num, sp.part_no, 'handling'),4294967295) / 4294967295.0 AS u_hand,
                   BITAND(HASH(:SEED, 'VTTK', sp.n, sp.plant_num, sp.part_no, 'cur'),     4294967295) / 4294967295.0 AS u_cur,
                   BITAND(HASH(:SEED, 'VTTK', sp.n, sp.plant_num, sp.part_no, 'load'),    4294967295) / 4294967295.0 AS u_load
            FROM sp
            JOIN TMP_O o ON o.n = sp.n
            JOIN TMP_PLANT pl ON pl.WERKS = sp.werks),
        l AS (
            SELECT u.*, CASE WHEN u.plant_region = u.cust_region THEN u.plant_region ELSE 'CROSS' END AS lane,
                   u.plant_country = u.cust_country AS is_domestic
            FROM u WHERE u.dptbg <= :l_date),
        c AS (
            SELECT l.*, cd.CARRIER_CD, cd.SLA + CASE WHEN l.lane = 'CROSS' THEN 5 ELSE 0 END AS sla_days,
                   cd.OT_OFF, cd.BASE_FREIGHT,
                   LEAST(0.97, GREATEST(0.70,
                       CASE WHEN YEAR(l.dptbg) <= 2019 THEN 0.872 WHEN YEAR(l.dptbg) = 2020 THEN 0.865
                            WHEN YEAR(l.dptbg) = 2021 THEN 0.855 WHEN YEAR(l.dptbg) = 2022 THEN 0.867 ELSE 0.870 END
                       + cd.OT_OFF
                       + CASE l.prio WHEN 'HIGH' THEN 0.02 WHEN 'LOW' THEN -0.01 ELSE 0 END
                       + l.ot_offset)) AS p_ot,
                   CASE WHEN l.dptbg < '2021-07-01'::DATE THEN 1.00
                        WHEN l.dptbg <= '2022-12-31'::DATE THEN 1.00 + 0.35 * DATEDIFF(day, '2021-07-01'::DATE, l.dptbg) / 548
                        WHEN l.dptbg <= '2023-12-31'::DATE THEN 1.35 - 0.25 * DATEDIFF(day, '2022-12-31'::DATE, l.dptbg) / 365
                        ELSE 1.10 END AS fuel
            FROM l
            JOIN TMP_CARRIER_DAY cd ON cd.LANE = l.lane AND cd.d = l.dptbg
             AND cd.idx = LEAST(cd.cnt, 1 + FLOOR(l.u_car * cd.cnt))::INT),
        t AS (
            SELECT c.*, DATEADD(day, c.sla_days, c.dptbg) AS prom,
                   CASE WHEN c.u_ot < c.p_ot THEN DATEADD(day, (-LEAST(2, FLOOR(c.u_days * 3)))::INT, DATEADD(day, c.sla_days, c.dptbg))
                        ELSE DATEADD(day, (1 + LEAST(5, FLOOR(c.u_days * 6)))::INT, DATEADD(day, c.sla_days, c.dptbg)) END AS act,
                   c.BASE_FREIGHT * CASE WHEN c.is_domestic THEN 0.7 WHEN c.lane <> 'CROSS' THEN 1.0 ELSE 1.8 END
                       * (0.6 + c.u_w) * c.fuel AS freight_usd,
                   CASE WHEN c.plant_country = 'USA' THEN 'USD' WHEN c.u_cur < 0.55 THEN c.plant_currency ELSE 'USD' END AS waers
            FROM c)
        SELECT t.n, t.werks, t.part_no, t.plant_num, t.CARRIER_CD, t.dptbg, t.prom,
               CASE WHEN t.act > :l_date THEN NULL ELSE t.act END AS act_dlv,
               t.freight_usd,
               CASE WHEN t.is_domestic THEN 0 ELSE t.freight_usd * (0.08 + 0.14 * t.u_duty) END AS duty_usd,
               40 + 80 * t.u_hand AS handling_usd,
               t.waers, t.u_load,
               :shp_offset + ROW_NUMBER() OVER (ORDER BY t.n, t.werks, t.part_no) AS shp_n
        FROM t;

        -- Order roll-up: status, the first shipment's promise, and the business date.
        CREATE OR REPLACE TEMPORARY TABLE TMP_OS AS
        SELECT o.n, o.audat, o.KUNNR, o.prio, o.waerk, o.is_cancelled, o.is_shipped,
               o.u_conf, o.u_confd, o.u_erdat, o.u_load,
               COUNT(s.shp_n) AS n_ship, COUNT(s.act_dlv) AS n_delivered,
               MIN_BY(s.prom, s.shp_n) AS first_prom, MIN(s.dptbg) AS first_dptbg, MAX(s.act_dlv) AS last_act
        FROM TMP_O o LEFT JOIN TMP_S s ON s.n = o.n
        GROUP BY o.n, o.audat, o.KUNNR, o.prio, o.waerk, o.is_cancelled, o.is_shipped,
                 o.u_conf, o.u_confd, o.u_erdat, o.u_load;

        SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ INTO :t0;
        INSERT INTO ERP_SOURCE.VBAK (VBELN, KUNNR, AUDAT, ERDAT, GBSTK, PRIO, AUART, WAERK, LOAD_TS)
        WITH s AS (
            SELECT os.*,
                CASE WHEN os.is_cancelled THEN 'CANCELLED' WHEN NOT os.is_shipped THEN 'OPEN'
                     WHEN os.n_ship = os.n_delivered THEN 'DELIVERED' ELSE 'SHIPPED' END AS gbstk
            FROM TMP_OS os)
        SELECT 'ORD' || LPAD(s.n, 9, '0'), s.KUNNR, s.audat,
               CASE WHEN s.gbstk IN ('SHIPPED', 'DELIVERED')
                    THEN CASE WHEN s.u_conf < 0.20 THEN DATEADD(day, (-(2 + LEAST(5, FLOOR(s.u_confd * 6))))::INT, s.first_prom)
                              ELSE s.first_prom END
                    ELSE DATEADD(day, (7 + LEAST(7, FLOOR(s.u_erdat * 8)))::INT, s.audat) END,
               s.gbstk, s.prio, 'OR', s.waerk,
               TIMESTAMPADD(minute, (120 + LEAST(180, FLOOR(181 * s.u_load)))::INT,
                   DATEADD(day, 1, CASE s.gbstk WHEN 'SHIPPED' THEN s.first_dptbg WHEN 'DELIVERED' THEN s.last_act
                                                ELSE s.audat END)::TIMESTAMP_NTZ)
        FROM s;
        n_rows := SQLROWCOUNT;
        INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
        SELECT :run_id, :TARGET_DB, 'orders', 'VBAK', :y::VARCHAR, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

        -- Lines carry their order's business date for LOAD_TS (§3.8).
        SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ INTO :t0;
        INSERT INTO ERP_SOURCE.VBAP (LINE_ID, VBELN, MATNR, WERKS, KWMENG, QTY_SHIPPED, NETPR, LOAD_TS)
        SELECT 'ORD' || LPAD(l.n, 9, '0') || '-' || LPAD(l.line_no, 3, '0'),
               'ORD' || LPAD(l.n, 9, '0'), l.MATNR, l.werks, l.kwmeng,
               CASE WHEN NOT l.is_shipped THEN 0
                    WHEN l.u_short < l.p_short THEN ROUND(l.kwmeng * (0.40 + 0.55 * l.u_shortq))
                    ELSE l.kwmeng END,
               ROUND(l.price_usd / fx.rate, 2),
               TIMESTAMPADD(minute, (120 + LEAST(180, FLOOR(181 * l.u_load)))::INT,
                   DATEADD(day, 1, CASE WHEN os.is_cancelled OR NOT os.is_shipped THEN os.audat
                                        WHEN os.n_ship = os.n_delivered THEN os.last_act
                                        ELSE os.first_dptbg END)::TIMESTAMP_NTZ)
        FROM TMP_L l
        JOIN TMP_OS os ON os.n = l.n
        JOIN TMP_FX fx ON fx.CUR = l.waerk AND fx.d = l.audat;
        n_rows := SQLROWCOUNT;
        INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
        SELECT :run_id, :TARGET_DB, 'orders', 'VBAP', :y::VARCHAR, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

        SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ INTO :t0;
        INSERT INTO TMS_SOURCE.VTTK (TKNUM, VBELN, WERKS, CARRIER_CD, DPTBG, PROM_DLV_DT, ACT_DLV_DT,
                                     FREIGHT_AMT, DUTY_AMT, HANDLING_AMT, SHP_STATUS, WAERS, LOAD_TS)
        SELECT 'SHP' || LPAD(s.shp_n, 9, '0'), 'ORD' || LPAD(s.n, 9, '0'), s.werks, s.CARRIER_CD,
               s.dptbg, s.prom, s.act_dlv,
               ROUND(s.freight_usd / fx.rate, 2), ROUND(s.duty_usd / fx.rate, 2), ROUND(s.handling_usd / fx.rate, 2),
               CASE WHEN s.act_dlv IS NOT NULL AND s.act_dlv <= s.prom THEN 'DELIVERED'
                    WHEN s.act_dlv IS NOT NULL THEN 'DELAYED'
                    WHEN :l_date > s.prom THEN 'DELAYED'
                    ELSE 'IN_TRANSIT' END,
               s.waers,
               TIMESTAMPADD(minute, (120 + LEAST(180, FLOOR(181 * s.u_load)))::INT,
                            DATEADD(day, 1, COALESCE(s.act_dlv, s.dptbg))::TIMESTAMP_NTZ)
        FROM TMP_S s JOIN TMP_FX fx ON fx.CUR = s.waers AND fx.d = s.dptbg;
        n_rows := SQLROWCOUNT;
        shp_offset := shp_offset + n_rows;
        INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
        SELECT :run_id, :TARGET_DB, 'orders', 'VTTK', :y::VARCHAR, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    END FOR;

    -- ── 8. Inventory snapshots, one history year per statement (§3.7) ──────
    FOR y IN y0 TO y1 DO
        stage := 'inventory ' || y;
        SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ INTO :t0;
        INSERT INTO WMS_SOURCE.MARD (INV_KEY, WERKS, MATNR, LABST, INSME, REORD_PT, DAILY_USG, SNAP_DT, LOAD_TS)
        WITH s AS (SELECT d, DATEDIFF(day, :s_date, d) AS dn, FLOOR(DATEDIFF(day, :s_date, d) / 7) AS wk
                   FROM TMP_SNAP WHERE yr = :y),
        b AS (
            SELECT st.WERKS, st.MATNR, st.pair_n, st.reorder_f, s.d, s.dn,
                st.usage_base
                  * CASE MONTH(s.d) WHEN 1 THEN 0.95 WHEN 2 THEN 0.85 WHEN 3 THEN 1.00 WHEN 4 THEN 0.98 WHEN 5 THEN 1.00
                                    WHEN 6 THEN 1.02 WHEN 7 THEN 0.97 WHEN 8 THEN 0.98 WHEN 9 THEN 1.05 WHEN 10 THEN 1.10
                                    WHEN 11 THEN 1.18 ELSE 1.05 END
                  * (0.85 + 0.30 * BITAND(HASH(:SEED, 'MARD', st.pair_n, s.wk, 'wnoise'), 4294967295) / 4294967295.0) AS usg,
                st.cover_base * CASE WHEN MONTH(s.d) IN (9, 10) THEN 1.20 ELSE 1.00 END
                  * (0.90 + 0.20 * BITAND(HASH(:SEED, 'MARD', st.pair_n, s.dn, 'cnoise'), 4294967295) / 4294967295.0) AS cover,
                BITAND(HASH(:SEED, 'MARD', st.pair_n, s.dn, 'insme'), 4294967295) / 4294967295.0 AS u_ins,
                BITAND(HASH(:SEED, 'MARD', st.pair_n, s.dn, 'load'),  4294967295) / 4294967295.0 AS u_load
            FROM TMP_STOCK st CROSS JOIN s)
        SELECT WERKS || '-' || MATNR || '-' || TO_CHAR(d, 'YYYYMMDD'), WERKS, MATNR,
               ROUND(usg * cover, 3), ROUND(usg * cover * 0.10 * u_ins, 3), ROUND(usg * reorder_f, 3), ROUND(usg, 3), d,
               TIMESTAMPADD(minute, (120 + LEAST(180, FLOOR(181 * u_load)))::INT, DATEADD(day, 1, d)::TIMESTAMP_NTZ)
        FROM b;
        n_rows := SQLROWCOUNT;
        INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
        SELECT :run_id, :TARGET_DB, 'inventory', 'MARD', :y::VARCHAR, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    END FOR;

    -- ── 9. Clean-load facts for the self-checks (GEN_STATS, phase CLEAN) ────
    stage := 'stats';
    SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ INTO :t0;
    CREATE OR REPLACE TEMPORARY TABLE TMP_TSTATS AS
    SELECT 'T001W' AS t, COUNT(*) AS n, COUNT(DISTINCT WERKS) AS k, TO_VARCHAR(HASH_AGG(*)) AS h FROM WMS_SOURCE.T001W
    UNION ALL SELECT 'LFA1', COUNT(*), COUNT(DISTINCT LIFNR), TO_VARCHAR(HASH_AGG(*)) FROM SRM_SOURCE.LFA1
    UNION ALL SELECT 'MARA', COUNT(*), COUNT(DISTINCT MATNR), TO_VARCHAR(HASH_AGG(*)) FROM SRM_SOURCE.MARA
    UNION ALL SELECT 'KNA1', COUNT(*), COUNT(DISTINCT KUNNR), TO_VARCHAR(HASH_AGG(*)) FROM ERP_SOURCE.KNA1
    UNION ALL SELECT 'TCURR', COUNT(*), COUNT(DISTINCT FCURR || '|' || GDATU), TO_VARCHAR(HASH_AGG(*)) FROM ERP_SOURCE.TCURR
    UNION ALL SELECT 'SOURCING', COUNT(*), COUNT(DISTINCT SOURCE_ID), TO_VARCHAR(HASH_AGG(*)) FROM SRM_SOURCE.SOURCING
    UNION ALL SELECT 'VBAK', COUNT(*), COUNT(DISTINCT VBELN), TO_VARCHAR(HASH_AGG(*)) FROM ERP_SOURCE.VBAK
    UNION ALL SELECT 'VBAP', COUNT(*), COUNT(DISTINCT LINE_ID), TO_VARCHAR(HASH_AGG(*)) FROM ERP_SOURCE.VBAP
    UNION ALL SELECT 'VTTK', COUNT(*), COUNT(DISTINCT TKNUM), TO_VARCHAR(HASH_AGG(*)) FROM TMS_SOURCE.VTTK
    UNION ALL SELECT 'MARD', COUNT(*), COUNT(DISTINCT INV_KEY), TO_VARCHAR(HASH_AGG(*)) FROM WMS_SOURCE.MARD;

    INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_STATS (RUN_ID, TARGET_DB, PHASE, NAME, TABLE_NAME, VALUE, DETAIL, PARAMS, LOGGED_AT)
    WITH p AS (SELECT OBJECT_CONSTRUCT('scale_factor', :SCALE_FACTOR, 'seed', :SEED, 'end_date', :END_DATE) AS params),
    m AS (SELECT 'ROWS' AS name, t, n::FLOAT AS value, NULL AS detail FROM TMP_TSTATS
          UNION ALL SELECT 'DISTINCT_KEYS', t, k::FLOAT, NULL FROM TMP_TSTATS
          UNION ALL SELECT 'CHECKSUM', t, NULL, h FROM TMP_TSTATS)
    SELECT :run_id, :TARGET_DB, 'CLEAN', m.name, m.t, m.value, m.detail, p.params, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
    FROM m CROSS JOIN p;

    -- The §5.3 metrics on the clean load (anchor END_DATE), so a mis-tuned distribution
    -- shows up here, not at B08c. Complete calendar years only for the per-year ranges.
    INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_STATS (RUN_ID, TARGET_DB, PHASE, NAME, TABLE_NAME, VALUE, DETAIL, PARAMS, LOGGED_AT)
    WITH ship AS (
        SELECT s.DPTBG, s.PROM_DLV_DT, s.ACT_DLV_DT, s.WERKS, o.ERDAT, YEAR(s.DPTBG) AS yr,
               (s.FREIGHT_AMT + s.DUTY_AMT + s.HANDLING_AMT) * fx.rate AS landed_usd,
               s.DPTBG > DATEADD(month, -12, :END_DATE) AND s.DPTBG <= :END_DATE AS in_t12m
        FROM TMS_SOURCE.VTTK s
        JOIN ERP_SOURCE.VBAK o ON o.VBELN = s.VBELN
        JOIN TMP_FX fx ON fx.CUR = s.WAERS AND fx.d = s.DPTBG),
    otd AS (
        SELECT yr, COUNT_IF(ACT_DLV_DT <= PROM_DLV_DT) / NULLIFZERO(COUNT_IF(ACT_DLV_DT IS NOT NULL AND PROM_DLV_DT IS NOT NULL)) AS otd,
               AVG(landed_usd) AS landed
        FROM ship GROUP BY yr),
    fill AS (
        SELECT YEAR(o.AUDAT) AS yr, SUM(l.QTY_SHIPPED) / NULLIFZERO(SUM(l.KWMENG)) AS fill
        FROM ERP_SOURCE.VBAP l JOIN ERP_SOURCE.VBAK o ON o.VBELN = l.VBELN
        WHERE o.GBSTK IN ('SHIPPED', 'DELIVERED') GROUP BY YEAR(o.AUDAT)),
    doi AS (SELECT YEAR(SNAP_DT) AS yr, AVG(LABST) / NULLIFZERO(AVG(DAILY_USG)) AS doi FROM WMS_SOURCE.MARD GROUP BY YEAR(SNAP_DT)),
    full_years AS (SELECT yr FROM otd WHERE yr > YEAR(:s_date) AND yr < YEAR(:l_date)),
    m AS (
        SELECT 'OTD_T12M' AS name, COUNT_IF(ACT_DLV_DT <= PROM_DLV_DT) / NULLIFZERO(COUNT_IF(ACT_DLV_DT IS NOT NULL)) AS value FROM ship WHERE in_t12m
        UNION ALL SELECT 'OTD_10Y', COUNT_IF(ACT_DLV_DT <= PROM_DLV_DT) / NULLIFZERO(COUNT_IF(ACT_DLV_DT IS NOT NULL)) FROM ship
        UNION ALL SELECT 'OTD_YEAR_MIN', MIN(otd) FROM otd WHERE yr IN (SELECT yr FROM full_years)
        UNION ALL SELECT 'OTD_YEAR_MAX', MAX(otd) FROM otd WHERE yr IN (SELECT yr FROM full_years)
        UNION ALL SELECT 'NAIVE_OTD_T12M', COUNT_IF(ACT_DLV_DT <= ERDAT) / NULLIFZERO(COUNT_IF(ACT_DLV_DT IS NOT NULL)) FROM ship WHERE in_t12m
        UNION ALL SELECT 'LANDED_T12M', AVG(landed_usd) FROM ship WHERE in_t12m
        UNION ALL SELECT 'LANDED_10Y', AVG(landed_usd) FROM ship
        UNION ALL SELECT 'LANDED_YEAR_MIN', MIN(landed) FROM otd WHERE yr IN (SELECT yr FROM full_years)
        UNION ALL SELECT 'LANDED_YEAR_MAX', MAX(landed) FROM otd WHERE yr IN (SELECT yr FROM full_years)
        UNION ALL SELECT 'FILL_T12M', SUM(l.QTY_SHIPPED) / NULLIFZERO(SUM(l.KWMENG))
                  FROM ERP_SOURCE.VBAP l JOIN ERP_SOURCE.VBAK o ON o.VBELN = l.VBELN
                  WHERE o.GBSTK IN ('SHIPPED', 'DELIVERED') AND o.AUDAT > DATEADD(month, -12, :END_DATE) AND o.AUDAT <= :END_DATE
        UNION ALL SELECT 'FILL_10Y', SUM(l.QTY_SHIPPED) / NULLIFZERO(SUM(l.KWMENG))
                  FROM ERP_SOURCE.VBAP l JOIN ERP_SOURCE.VBAK o ON o.VBELN = l.VBELN WHERE o.GBSTK IN ('SHIPPED', 'DELIVERED')
        UNION ALL SELECT 'FILL_YEAR_MIN', MIN(fill) FROM fill WHERE yr IN (SELECT yr FROM full_years)
        UNION ALL SELECT 'FILL_YEAR_MAX', MAX(fill) FROM fill WHERE yr IN (SELECT yr FROM full_years)
        UNION ALL SELECT 'DOI_LATEST', AVG(LABST) / NULLIFZERO(AVG(DAILY_USG)) FROM WMS_SOURCE.MARD
                  WHERE SNAP_DT = (SELECT MAX(SNAP_DT) FROM WMS_SOURCE.MARD)
        UNION ALL SELECT 'DOI_YEAR_MIN', MIN(doi) FROM doi WHERE yr IN (SELECT yr FROM full_years)
        UNION ALL SELECT 'DOI_YEAR_MAX', MAX(doi) FROM doi WHERE yr IN (SELECT yr FROM full_years)
        UNION ALL SELECT 'PLANT_YEARS_WITHOUT_SHIPMENTS', COUNT(*)
                  FROM (SELECT pl.WERKS, y.yr FROM TMP_PLANT pl CROSS JOIN (SELECT DISTINCT yr FROM ship) y) py
                  WHERE NOT EXISTS (SELECT 1 FROM ship s WHERE s.WERKS = py.WERKS AND s.yr = py.yr)
        UNION ALL SELECT 'E10_CONFLICT_RATE', AVG(IFF(o.ERDAT <> f.first_prom, 1, 0))
                  FROM ERP_SOURCE.VBAK o
                  JOIN (SELECT VBELN, MIN_BY(PROM_DLV_DT, TKNUM) AS first_prom FROM TMS_SOURCE.VTTK GROUP BY VBELN) f
                    ON f.VBELN = o.VBELN
                  WHERE o.GBSTK IN ('SHIPPED', 'DELIVERED')
        UNION ALL SELECT 'M05_VBAK_NON_USD_RATE', AVG(IFF(WAERK <> 'USD', 1, 0)) FROM ERP_SOURCE.VBAK
        UNION ALL SELECT 'M05_VTTK_NON_USD_RATE', AVG(IFF(WAERS <> 'USD', 1, 0)) FROM TMS_SOURCE.VTTK
        UNION ALL SELECT 'M05_SOURCING_NON_USD_RATE', AVG(IFF(WAERS <> 'USD', 1, 0)) FROM SRM_SOURCE.SOURCING
        UNION ALL SELECT 'TCURR_MAX_DAILY_STEP', MAX(ABS(LN(UKURS / prev)))
                  FROM (SELECT UKURS, LAG(UKURS) OVER (PARTITION BY FCURR ORDER BY GDATU) AS prev FROM ERP_SOURCE.TCURR)
                  WHERE prev IS NOT NULL
        UNION ALL SELECT 'APAC_ORDER_SHARE_FIRST_YEAR', AVG(IFF(c.REGIO = 'APAC', 1, 0))
                  FROM ERP_SOURCE.VBAK o JOIN ERP_SOURCE.KNA1 c ON c.KUNNR = o.KUNNR
                  WHERE o.AUDAT < DATEADD(year, 1, :s_date)
        UNION ALL SELECT 'APAC_ORDER_SHARE_LAST_YEAR', AVG(IFF(c.REGIO = 'APAC', 1, 0))
                  FROM ERP_SOURCE.VBAK o JOIN ERP_SOURCE.KNA1 c ON c.KUNNR = o.KUNNR
                  WHERE o.AUDAT > DATEADD(year, -1, :END_DATE))
    SELECT :run_id, :TARGET_DB, 'CLEAN', m.name, NULL, m.value::FLOAT, NULL,
           OBJECT_CONSTRUCT('scale_factor', :SCALE_FACTOR, 'seed', :SEED, 'end_date', :END_DATE),
           CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
    FROM m;

    INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
    SELECT :run_id, :TARGET_DB, 'stats', NULL, NULL, NULL, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

    -- ── 10. Result ──────────────────────────────────────────────────────────
    stage := 'result';
    result := (SELECT OBJECT_CONSTRUCT(
               'status', 'OK', 'run_id', :run_id, 'target_db', :TARGET_DB, 'scale_factor', :SCALE_FACTOR,
               'seed', :SEED, 'end_date', :END_DATE,
               'rows', (SELECT OBJECT_AGG(TABLE_NAME, TO_VARIANT(VALUE::NUMBER)) FROM SUPPLY_CHAIN_FORGE.OPS.GEN_STATS
                        WHERE RUN_ID = :run_id AND NAME = 'ROWS'),
               'elapsed_s', DATEDIFF(millisecond, :run_t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ) / 1000,
               'stages', (SELECT ARRAY_AGG(OBJECT_CONSTRUCT('stage', STAGE, 'table', TABLE_NAME, 'chunk', CHUNK,
                                                            'rows', ROWS_WRITTEN,
                                                            'elapsed_s', DATEDIFF(millisecond, STARTED_AT, ENDED_AT) / 1000))
                                    WITHIN GROUP (ORDER BY STARTED_AT)
                          FROM SUPPLY_CHAIN_FORGE.OPS.GEN_LOG WHERE RUN_ID = :run_id AND TABLE_NAME IS NOT NULL)));

    INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
    SELECT :run_id, :TARGET_DB, 'done', NULL, NULL, NULL, :run_t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    RETURN result;

EXCEPTION
    WHEN OTHER THEN
        LET err_code VARCHAR := SQLCODE;
        LET err_msg VARCHAR := SQLERRM;
        INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT, PARAMS)
        SELECT COALESCE(:run_id, 'unknown'), :TARGET_DB, 'error', NULL, :stage, NULL, :run_t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
               OBJECT_CONSTRUCT('sqlcode', :err_code, 'sqlerrm', :err_msg);
        RETURN OBJECT_CONSTRUCT('status', 'ERROR', 'run_id', run_id, 'stage', stage, 'sqlcode', err_code, 'sqlerrm', err_msg);
END;
$$;
