-- ============================================================================
-- data_gen/40_sp_append_day.sql — OPS.SP_APPEND_DAY: one more real business day, every night
-- Card:       C17 part B (.agents/tasks/claude/C17_nightly_day_append.md)
-- Spec:       docs/DATA_SPEC.md §7.1a (plus §3, §4, §6: the generator's own formulas)
-- Role:       ACCOUNTADMIN (owns the source tables)   Warehouse: FORGE_WH (XS)
-- Run order:  after 00 → 10 → 20 → 30 (it reads OPS.GEN_LOG for the generator's END_DATE).
--             Re-runnable: CREATE OR REPLACE. A CALL is idempotent (see Expected).
-- Parameters: TARGET_DB (SUPPLY_CHAIN_FORGE, or a clone), SCALE_FACTOR and SEED (the same as
--             the SP_GENERATE_DATA run: 1, 20260929), NEW_END_DATE (the nightly task passes
--             the UTC date; never CURRENT_DATE() in here: the account runs on LA time).
-- Expected:   CREATE succeeds. A CALL adds every business day from the current end
--             (MAX(VBAK.LOAD_TS)::DATE) to NEW_END_DATE, one day per transaction, and returns
--             {"status": "OK", "from_end_date", "new_end_date", "days_added", "rows": {...},
--              "max_load_ts", "elapsed_s"}. At SF 1 a weekday (Oct, +8%/yr growth) is ~330 new
--             orders (Sat ~115, Sun ~50) with ~950 lines, ~300-350 shipments leaving and as many
--             delivered, 3,600 stock rows, 9 FX rows (business days), in seconds. NEW_END_DATE <= the current end: days_added 0,
--             nothing written. On failure: {"status": "ERROR", "stage", "sqlerrm"}; the
--             failing day is rolled back, earlier days stay.
--
-- How (§7.1a): the full generator can't be re-run for "one more day" (its 10-year window
-- would move every row). But each order's whole life is a pure function of its number n:
-- HASH(SEED, 'VBAK' | 'VBAP' | 'VTTK', n, ...). So for day D (the new last business date
-- L = NEW end - 1) this procedure re-derives the orders of the last 40 days EXACTLY as
-- SP_GENERATE_DATA does (the formulas below are copies; tests/unit/test_data_gen_sql.py fails
-- if they drift), compares their state at L = D with L = D - 1, and writes only what changed:
--   new orders (AUDAT = D) and their lines, at the §3.1 volume, numbered after the last one
--   orders that ship on D: a new VBAK version (SHIPPED), new VBAP versions (QTY_SHIPPED), and
--     their shipments (new TKNUMs after the current maximum)
--   shipments delivered on D, or overdue since D: a new VTTK version
--   orders whose status changes (all delivered, or a second shipment leaves): a VBAK version
--   the day's stock snapshot (all 3,600 stocked pairs) and FX rates (business days)
-- Row versions copy the latest existing row and change only the state columns, so the mess
-- already on that row (test customer, return order, whitespace, missing duty...) stays.
-- Never UPDATE or DELETE: CONFORMED's "latest LOAD_TS wins" (§5.1) shows the current state.
-- New rows carry the §4 mess at its rates: M03 code variants, E01 missing promise, E04
-- over-shipment, E05 negative stock, and E06 zero-usage pairs carried forward.
-- ============================================================================

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_FORGE.OPS.SP_APPEND_DAY(
    TARGET_DB VARCHAR, SCALE_FACTOR FLOAT, SEED NUMBER, NEW_END_DATE DATE)
RETURNS VARIANT
LANGUAGE SQL
COMMENT = 'C17: appends business days to the source tables, as the generator would have (DATA_SPEC §7.1a). Idempotent per NEW_END_DATE.'
EXECUTE AS CALLER
AS
$$
DECLARE
    stage        VARCHAR DEFAULT 'start';
    run_id       VARCHAR;
    ok_name      BOOLEAN;
    end0         DATE;          -- the generator's END_DATE: anchors the order calendar
    s_date       DATE;          -- history start: end0 - 10 years
    l0           DATE;          -- the generator's last business date
    fx_start     DATE;
    n_orders     INTEGER;
    cust_span    INTEGER;
    from_end     DATE;
    n_new        INTEGER;
    n_cal        INTEGER;
    cd_start     DATE;
    cd_days      INTEGER;
    e            DATE;          -- the new end date being added
    d            DATE;          -- its business date: L = e - 1
    w0           DATE;          -- the re-derived window: orders placed on w0 .. d
    max_shp      INTEGER;
    days_added   INTEGER DEFAULT 0;
    n_rows       INTEGER;
    t0           TIMESTAMP_NTZ;
    run_t0       TIMESTAMP_NTZ;
    result       VARIANT;
BEGIN
    -- ── 0. Parameters and where we are ──────────────────────────────────────
    SELECT UUID_STRING(), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
           COALESCE(REGEXP_LIKE(:TARGET_DB, '^[A-Za-z_][A-Za-z0-9_$]*$'), FALSE)
      INTO :run_id, :run_t0, :ok_name;
    IF (NOT ok_name OR SCALE_FACTOR IS NULL OR SCALE_FACTOR <= 0 OR SEED IS NULL OR NEW_END_DATE IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('status', 'ERROR', 'stage', 'parameters',
            'sqlerrm', 'TARGET_DB must be a plain identifier; SCALE_FACTOR > 0; SEED and NEW_END_DATE required');
    END IF;

    EXECUTE IMMEDIATE 'USE SCHEMA ' || :TARGET_DB || '.OPS';

    -- The generator's END_DATE for this seed and scale (its own run of this database first,
    -- else the run a clone was made from).
    stage := 'anchor';
    SELECT MAX_BY(PARAMS:end_date::DATE,  -- an aggregate: one row (NULL) even when nothing matches
                  IFF(TARGET_DB = :TARGET_DB, 10000000000, 0) + DATE_PART(epoch_second, STARTED_AT)) INTO :end0
    FROM SUPPLY_CHAIN_FORGE.OPS.GEN_LOG
    WHERE STAGE = 'start' AND PARAMS:procedure::VARCHAR = 'SP_GENERATE_DATA'
      AND PARAMS:seed::NUMBER = :SEED AND PARAMS:scale_factor::FLOAT = :SCALE_FACTOR;
    IF (end0 IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('status', 'ERROR', 'stage', 'anchor',
            'sqlerrm', 'No SP_GENERATE_DATA run with this SEED and SCALE_FACTOR in OPS.GEN_LOG');
    END IF;

    SELECT DATEADD(year, -10, :end0), DATEADD(day, -1, :end0), DATEADD(day, -7, DATEADD(year, -10, :end0)),
           ROUND(650000 * :SCALE_FACTOR)
      INTO :s_date, :l0, :fx_start, :n_orders;
    SELECT DATEDIFF(day, :s_date, :l0) - 30 INTO :cust_span;

    SELECT MAX(LOAD_TS)::DATE INTO :from_end FROM ERP_SOURCE.VBAK;
    n_new := DATEDIFF(day, from_end, NEW_END_DATE);

    INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT, PARAMS)
    SELECT :run_id, :TARGET_DB, 'start', NULL, NULL, NULL, :run_t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
           OBJECT_CONSTRUCT('procedure', 'SP_APPEND_DAY', 'scale_factor', :SCALE_FACTOR, 'seed', :SEED,
                            'generator_end_date', :end0, 'from_end_date', :from_end, 'new_end_date', :NEW_END_DATE);

    IF (n_new <= 0) THEN  -- already there: idempotent, writes nothing
        RETURN OBJECT_CONSTRUCT('status', 'OK', 'run_id', :run_id, 'target_db', :TARGET_DB,
            'from_end_date', :from_end, 'new_end_date', :NEW_END_DATE, 'days_added', 0, 'rows', OBJECT_CONSTRUCT());
    END IF;
    IF (n_new > 60) THEN
        RETURN OBJECT_CONSTRUCT('status', 'ERROR', 'stage', 'parameters',
            'sqlerrm', 'More than 60 days to catch up: check NEW_END_DATE, or call it in steps');
    END IF;

    -- ── 1. Reference tables: verbatim copies of SP_GENERATE_DATA §1, §2, §5 ─
    stage := 'reference';
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

    CREATE OR REPLACE TEMPORARY TABLE TMP_PLANT_MAP AS
    WITH c AS (SELECT REGION, WERKS, units,
                 SUM(units) OVER (PARTITION BY REGION ORDER BY WERKS ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum
          FROM TMP_PLANT)
    SELECT c.REGION, c.cum - c.units + f.value::INT AS t, c.WERKS
    FROM c, LATERAL FLATTEN(INPUT => ARRAY_GENERATE_RANGE(1, c.units + 1)) f;

    CREATE OR REPLACE TEMPORARY TABLE TMP_REGION_UNITS AS
    SELECT REGION, SUM(units) AS units FROM TMP_PLANT GROUP BY REGION;

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

    CREATE OR REPLACE TEMPORARY TABLE TMP_CUR AS
    SELECT v.CUR, v.CUR_N, v.START_RATE
    FROM (VALUES ('EUR', 1, 1.10), ('GBP', 2, 1.30), ('JPY', 3, 0.0090), ('CNY', 4, 0.145),
                 ('INR', 5, 0.0135), ('SGD', 6, 0.73), ('CAD', 7, 0.76), ('MXN', 8, 0.052),
                 ('BRL', 9, 0.25)) AS v(CUR, CUR_N, START_RATE);

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

    -- The carriers active on each day for each lane, numbered (the window's days only).
    SELECT DATEADD(day, -60, :from_end), DATEDIFF(day, DATEADD(day, -60, :from_end), :NEW_END_DATE) + 10
      INTO :cd_start, :cd_days;
    CREATE OR REPLACE TEMPORARY TABLE TMP_CARRIER_DAY AS
    WITH cal AS (SELECT DATEADD(day, (ROW_NUMBER() OVER (ORDER BY SEQ8()) - 1)::INT, :cd_start) AS d
                 FROM TABLE(GENERATOR(ROWCOUNT => :cd_days))),
    lanes AS (SELECT c.CARRIER_CD, TRIM(f.value::VARCHAR) AS LANE, c.SLA, c.OT_OFF, c.BASE_FREIGHT, c.ACTIVE_FROM, c.ACTIVE_TO
              FROM TMP_CARRIER c, LATERAL SPLIT_TO_TABLE(c.LANES, ',') f)
    SELECT l.LANE, cal.d, l.CARRIER_CD, l.SLA, l.OT_OFF, l.BASE_FREIGHT,
           ROW_NUMBER() OVER (PARTITION BY l.LANE, cal.d ORDER BY l.CARRIER_CD) AS idx,
           COUNT(*) OVER (PARTITION BY l.LANE, cal.d) AS cnt
    FROM cal JOIN lanes l ON cal.d BETWEEN l.ACTIVE_FROM AND l.ACTIVE_TO;

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

    CREATE OR REPLACE TEMPORARY TABLE TMP_CUST_MAP AS
    SELECT c.cum - c.weight + f.value::INT AS t, c.KUNNR
    FROM TMP_CUST c, LATERAL FLATTEN(INPUT => ARRAY_GENERATE_RANGE(1, c.weight + 1)) f;

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

    -- The §4.3 code variants (copy of SP_INJECT_MESS's TMP_VAR), for the M03 mess on new rows.
    CREATE OR REPLACE TEMPORARY TABLE TMP_VAR AS
    SELECT v.DOMAIN, v.CANONICAL, f.value::VARCHAR AS VARIANT, f.index AS IDX,
           COUNT(*) OVER (PARTITION BY v.DOMAIN, v.CANONICAL) AS CNT
    FROM (VALUES
        ('ORDER_STATUS', 'OPEN', 'Open|OPN'),
        ('ORDER_STATUS', 'SHIPPED', 'Shipped|SHP'),
        ('ORDER_STATUS', 'DELIVERED', 'Delivered|DLV|delivered '),
        ('ORDER_STATUS', 'CANCELLED', 'Cancelled|CANCELED|CNL'),
        ('PRIORITY', 'HIGH', 'High|H|URGENT'),
        ('PRIORITY', 'NORMAL', 'Normal|MED|MEDIUM'),
        ('PRIORITY', 'LOW', 'Low|L'),
        ('SHIPMENT_STATUS', 'IN_TRANSIT', 'In Transit|IN-TRANSIT|INTRANSIT'),
        ('SHIPMENT_STATUS', 'DELIVERED', 'Delivered|DLV'),
        ('SHIPMENT_STATUS', 'DELAYED', 'Delayed|LATE'),
        ('CARRIER', 'DHL_EXPRESS', 'DHL|DHL Express|dhl_express'),
        ('CARRIER', 'FEDEX_FREIGHT', 'FedEx|FEDEX FREIGHT'),
        ('CARRIER', 'MAERSK_LOGISTICS', 'Maersk|MAERSK'),
        ('CARRIER', 'KUEHNE_NAGEL', 'K+N|Kuehne+Nagel|KUEHNE + NAGEL'),
        ('CARRIER', 'DB_SCHENKER', 'DB Schenker|SCHENKER'),
        ('CARRIER', 'UPS_SUPPLY_CHAIN', 'UPS|UPS SCS'),
        ('CARRIER', 'XPO_LOGISTICS', 'XPO'),
        ('CARRIER', 'CEVA_LOGISTICS', 'CEVA'),
        ('CARRIER', 'FLEXPORT', 'Flexport')
    ) AS v(DOMAIN, CANONICAL, VARIANTS), LATERAL SPLIT_TO_TABLE(v.VARIANTS, '|') f;

    -- ── 2. The order calendar (§3.1), extended past the generator's end ─────
    -- Identical to SP_GENERATE_DATA §6 up to l0 (same weights, same total tw over the
    -- generator's window), so cum(d) and the order numbers match; after l0 the cumulative
    -- weight simply continues, and new orders are numbered after the generator's last.
    stage := 'calendar';
    SELECT DATEDIFF(day, :s_date, DATEADD(day, -1, :NEW_END_DATE)) + 1 INTO :n_cal;
    CREATE OR REPLACE TEMPORARY TABLE TMP_DAYS AS
    WITH cal AS (SELECT DATEADD(day, (ROW_NUMBER() OVER (ORDER BY SEQ8()) - 1)::INT, :s_date) AS d
                 FROM TABLE(GENERATOR(ROWCOUNT => :n_cal))),
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
                 SUM(IFF(d <= :l0, w, 0)) OVER () AS tw
          FROM w),
    r AS (SELECT d, ROUND(:n_orders * cw / tw)::NUMBER AS cum FROM c),
    wc AS (SELECT eff_date, SUM(weight) AS wsum FROM TMP_CUST GROUP BY eff_date)
    SELECT r.d, YEAR(r.d) AS yr,
           COALESCE(LAG(r.cum) OVER (ORDER BY r.d), 0) AS cum_prev,
           r.cum - COALESCE(LAG(r.cum) OVER (ORDER BY r.d), 0) AS cnt,
           SUM(COALESCE(wc.wsum, 0)) OVER (ORDER BY r.d ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS w_cust
    FROM r LEFT JOIN wc ON wc.eff_date = r.d;

    -- ── 3. One business day at a time ───────────────────────────────────────
    FOR i IN 1 TO n_new DO
        e := DATEADD(day, i, from_end);
        d := DATEADD(day, -1, e);
        w0 := DATEADD(day, -40, d);
        stage := 'derive ' || d::VARCHAR;
        SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ INTO :t0;

        -- FX for D (business days, ~1% holidays): the generator's formula at t = D - fx_start.
        CREATE OR REPLACE TEMPORARY TABLE TMP_FXDAY (KURST, FCURR, TCURR, GDATU, UKURS, LOAD_TS) AS
        WITH cal AS (SELECT :d AS d),
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
                            DATEADD(day, 1, bd.d)::TIMESTAMP_NTZ)
        FROM bd CROSS JOIN TMP_CUR c
        WHERE NOT EXISTS (SELECT 1 FROM ERP_SOURCE.TCURR x WHERE x.FCURR = c.CUR AND x.GDATU = bd.d AND x.KURST = 'M');

        -- Daily rate lookup over the window (the latest rate on or before each day), USD = 1.
        CREATE OR REPLACE TEMPORARY TABLE TMP_FX AS
        WITH cal AS (SELECT DATEADD(day, (ROW_NUMBER() OVER (ORDER BY SEQ8()) - 1)::INT, DATEADD(day, -20, :w0)) AS d
                     FROM TABLE(GENERATOR(ROWCOUNT => 62))),
        rates AS (SELECT FCURR, GDATU, UKURS FROM ERP_SOURCE.TCURR
                  WHERE KURST = 'M' AND TCURR = 'USD' AND GDATU BETWEEN DATEADD(day, -20, :w0) AND :d
                  UNION ALL SELECT FCURR, GDATU, UKURS FROM TMP_FXDAY),
        grid AS (SELECT c.CUR, cal.d, r.UKURS
                 FROM cal CROSS JOIN TMP_CUR c
                 LEFT JOIN rates r ON r.FCURR = c.CUR AND r.GDATU = cal.d)
        SELECT CUR, d, LAST_VALUE(UKURS IGNORE NULLS) OVER (PARTITION BY CUR ORDER BY d ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS rate
        FROM grid
        UNION ALL
        SELECT 'USD', d, 1 FROM cal;

        -- Orders placed w0 .. D: SP_GENERATE_DATA §7's TMP_O, with the state at L = D
        -- (is_shipped) and at L = D - 1 (was_shipped).
        CREATE OR REPLACE TEMPORARY TABLE TMP_O AS
        WITH o AS (SELECT d.d AS audat, d.cum_prev + f.value::INT AS n, d.w_cust
              FROM TMP_DAYS d, LATERAL FLATTEN(INPUT => ARRAY_GENERATE_RANGE(1, d.cnt + 1)) f
              WHERE d.d BETWEEN :w0 AND :d AND d.cnt > 0),
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
        SELECT b.*, (NOT b.is_cancelled AND b.dptbg <= :d) AS is_shipped,
               (NOT b.is_cancelled AND b.dptbg <= DATEADD(day, -1, :d)) AS was_shipped,
               'ORD' || LPAD(b.n, 9, '0') AS vbeln,
               CASE WHEN b.u_inreg < 0.85 THEN pm.WERKS
                    ELSE 'PL' || LPAD(LEAST(12, 1 + FLOOR(b.u_any * 12))::INT, 2, '0') END AS home_werks
        FROM b
        JOIN TMP_REGION_UNITS ru ON ru.REGION = b.cust_region
        JOIN TMP_PLANT_MAP pm ON pm.REGION = b.cust_region AND pm.t = LEAST(ru.units, 1 + FLOOR(b.u_plant * ru.units))::INT;

        -- Lines: SP_GENERATE_DATA §7's TMP_L.
        CREATE OR REPLACE TEMPORARY TABLE TMP_L AS
        WITH k AS (SELECT o.*, f.value::INT AS line_no
                   FROM TMP_O o, LATERAL FLATTEN(INPUT => ARRAY_GENERATE_RANGE(1, o.nlines + 1)) f),
        b AS (
            SELECT o.n, o.vbeln, o.audat, o.KUNNR, o.cust_region, o.waerk, o.is_shipped, o.was_shipped, o.home_werks, o.line_no,
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
        SELECT p.n, p.vbeln, p.audat, p.line_no, p.werks, p.is_shipped, p.was_shipped, p.u_load, s.MATNR,
               p.vbeln || '-' || LPAD(p.line_no, 3, '0') AS line_id,
               ROUND(EXP(LN(pt.Q_LO) + p.u_qty * (LN(pt.Q_HI) - LN(pt.Q_LO)))) AS kwmeng,
               pt.STPRS * (1.15 + 0.45 * p.u_price) AS price_usd, p.waerk,
               CASE WHEN YEAR(p.audat) = 2021 THEN 0.27 ELSE 0.20 END * pt.SHORT_F AS p_short,
               p.u_short, p.u_shortq
        FROM p
        JOIN TMP_STOCK s ON s.WERKS = p.werks AND s.stock_rank = LEAST(300, 1 + FLOOR(p.u_part * 300))::INT
        JOIN TMP_PART pt ON pt.MATNR = s.MATNR;

        -- Shipments: SP_GENERATE_DATA §7's TMP_S for every order that isn't cancelled, without
        -- its "dptbg <= L" filter and before act > L becomes NULL: which of them exist, and
        -- whether they're delivered, is decided below for L = D and L = D - 1.
        CREATE OR REPLACE TEMPORARY TABLE TMP_S AS
        WITH g AS (SELECT DISTINCT l.n, l.werks FROM TMP_L l JOIN TMP_O o ON o.n = l.n WHERE NOT o.is_cancelled),
        sp AS (
            SELECT g.n, g.werks, 1 AS part_no, SUBSTR(g.werks, 3)::NUMBER AS plant_num FROM g
            UNION ALL
            SELECT g.n, g.werks, 2 AS part_no, SUBSTR(g.werks, 3)::NUMBER AS plant_num FROM g
            WHERE BITAND(HASH(:SEED, 'VTTK', g.n, SUBSTR(g.werks, 3)::NUMBER, 'split'), 4294967295) / 4294967295.0 < 0.05),
        u AS (
            SELECT sp.*, o.vbeln, o.KUNNR, o.prio, o.cust_region, o.cust_country, pl.REGION AS plant_region,
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
            FROM u),
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
        SELECT t.n, t.vbeln, t.werks, t.part_no, t.plant_num, t.CARRIER_CD, t.dptbg, t.prom, t.act,
               t.freight_usd,
               CASE WHEN t.is_domestic THEN 0 ELSE t.freight_usd * (0.08 + 0.14 * t.u_duty) END AS duty_usd,
               40 + 80 * t.u_hand AS handling_usd,
               t.waers, t.u_load
        FROM t;

        -- Order state at L = D and at L = D - 1 (SP_GENERATE_DATA's TMP_OS roll-up and status rule).
        CREATE OR REPLACE TEMPORARY TABLE TMP_OS AS
        WITH r AS (
            SELECT o.n, o.vbeln, o.audat, o.is_cancelled, o.dptbg, o.u_conf, o.u_confd, o.u_erdat, o.u_load,
                   COUNT_IF(s.dptbg <= :d) AS ns1, COUNT_IF(s.act <= :d) AS nd1,
                   COUNT_IF(s.dptbg <= DATEADD(day, -1, :d)) AS ns0, COUNT_IF(s.act <= DATEADD(day, -1, :d)) AS nd0,
                   MIN_BY(s.prom, IFF(s.dptbg <= :d, s.werks || '-' || s.part_no, NULL)) AS first_prom
            FROM TMP_O o LEFT JOIN TMP_S s ON s.n = o.n
            GROUP BY o.n, o.vbeln, o.audat, o.is_cancelled, o.dptbg, o.u_conf, o.u_confd, o.u_erdat, o.u_load)
        SELECT r.*,
               CASE WHEN is_cancelled THEN 'CANCELLED' WHEN dptbg > :d THEN 'OPEN'
                    WHEN ns1 = nd1 THEN 'DELIVERED' ELSE 'SHIPPED' END AS status1,
               CASE WHEN is_cancelled THEN 'CANCELLED' WHEN dptbg > DATEADD(day, -1, :d) THEN 'OPEN'
                    WHEN ns0 = nd0 THEN 'DELIVERED' ELSE 'SHIPPED' END AS status0
        FROM r;

        -- What already exists: each shipment's TKNUM (part 1 before part 2 within an order and
        -- plant), and the latest row of every key the day may version.
        CREATE OR REPLACE TEMPORARY TABLE TMP_SHIPID AS
        SELECT TKNUM, vbeln, WERKS,
               ROW_NUMBER() OVER (PARTITION BY vbeln, WERKS ORDER BY TKNUM) AS part_no
        FROM (SELECT DISTINCT TKNUM, UPPER(TRIM(VBELN)) AS vbeln, WERKS FROM TMS_SOURCE.VTTK  -- one row per shipment:
              WHERE UPPER(TRIM(VBELN)) IN (SELECT vbeln FROM TMP_O));                          -- M01/M02 copies, M07 spaces

        CREATE OR REPLACE TEMPORARY TABLE TMP_VTTK_LAST AS
        SELECT * FROM TMS_SOURCE.VTTK WHERE TKNUM IN (SELECT TKNUM FROM TMP_SHIPID)
        QUALIFY ROW_NUMBER() OVER (PARTITION BY TKNUM ORDER BY LOAD_TS DESC) = 1;

        CREATE OR REPLACE TEMPORARY TABLE TMP_VBAK_LAST AS
        SELECT * FROM ERP_SOURCE.VBAK WHERE UPPER(TRIM(VBELN)) IN (SELECT vbeln FROM TMP_O)
        QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(VBELN)) ORDER BY LOAD_TS DESC) = 1;

        CREATE OR REPLACE TEMPORARY TABLE TMP_VBAP_LAST AS
        SELECT * FROM ERP_SOURCE.VBAP WHERE LINE_ID IN (SELECT line_id FROM TMP_L WHERE is_shipped AND NOT was_shipped)
        QUALIFY ROW_NUMBER() OVER (PARTITION BY LINE_ID ORDER BY LOAD_TS DESC) = 1;

        SELECT COALESCE(MAX(TRY_TO_NUMBER(SUBSTR(TKNUM, 4))), 0) INTO :max_shp
        FROM TMS_SOURCE.VTTK WHERE TKNUM LIKE 'SHP%';

        -- Stock pairs whose usage is zero (E06) stay zero: carried from the latest snapshot.
        CREATE OR REPLACE TEMPORARY TABLE TMP_E06 AS
        SELECT DISTINCT WERKS, MATNR FROM WMS_SOURCE.MARD
        WHERE SNAP_DT = (SELECT MAX(SNAP_DT) FROM WMS_SOURCE.MARD) AND DAILY_USG = 0;

        INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
        SELECT :run_id, :TARGET_DB, 'derive', NULL, :d::VARCHAR, (SELECT COUNT(*) FROM TMP_O), :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

        -- ── The day's writes: one transaction, VBAK last ────────────────────
        stage := 'write ' || d::VARCHAR;
        BEGIN TRANSACTION;

        INSERT INTO ERP_SOURCE.TCURR (KURST, FCURR, TCURR, GDATU, UKURS, LOAD_TS)
        SELECT KURST, FCURR, TCURR, GDATU, UKURS, LOAD_TS FROM TMP_FXDAY;
        n_rows := SQLROWCOUNT;
        INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
        SELECT :run_id, :TARGET_DB, 'append', 'TCURR', :d::VARCHAR, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

        -- Stock: the daily snapshot for D (SP_GENERATE_DATA §8's formula), E05 / E06 mess.
        INSERT INTO WMS_SOURCE.MARD (INV_KEY, WERKS, MATNR, LABST, INSME, REORD_PT, DAILY_USG, SNAP_DT, LOAD_TS)
        WITH s AS (SELECT :d AS d, DATEDIFF(day, :s_date, :d) AS dn, FLOOR(DATEDIFF(day, :s_date, :d) / 7) AS wk),
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
            FROM TMP_STOCK st CROSS JOIN s),
        k AS (SELECT b.*, b.WERKS || '-' || b.MATNR || '-' || TO_CHAR(b.d, 'YYYYMMDD') AS inv_key,
                     z.WERKS IS NOT NULL AS zero_usage
              FROM b LEFT JOIN TMP_E06 z ON z.WERKS = b.WERKS AND z.MATNR = b.MATNR)
        SELECT inv_key, WERKS, MATNR,
               CASE WHEN zero_usage THEN 50 + FLOOR(451 * BITAND(HASH(:SEED, 'MARD', inv_key, 'E06q'), 4294967295) / 4294967295.0)
                    WHEN BITAND(HASH(:SEED, 'MARD', inv_key, 'A05'), 4294967295) / 4294967295.0 < 0.003
                    THEN -(1 + FLOOR(50 * BITAND(HASH(:SEED, 'MARD', inv_key, 'E05q'), 4294967295) / 4294967295.0))
                    ELSE ROUND(usg * cover, 3) END,
               ROUND(usg * cover * 0.10 * u_ins, 3),
               IFF(zero_usage, 0, ROUND(usg * reorder_f, 3)), IFF(zero_usage, 0, ROUND(usg, 3)), d,
               TIMESTAMPADD(minute, (120 + LEAST(180, FLOOR(181 * u_load)))::INT, DATEADD(day, 1, d)::TIMESTAMP_NTZ)
        FROM k
        WHERE NOT EXISTS (SELECT 1 FROM WMS_SOURCE.MARD x WHERE x.SNAP_DT = :d);
        n_rows := SQLROWCOUNT;
        INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
        SELECT :run_id, :TARGET_DB, 'append', 'MARD', :d::VARCHAR, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

        -- Shipments that leave on D: new rows, numbered after the current maximum. Status at
        -- L = D is IN_TRANSIT (the promise is days away). M03 mess: status 3%, carrier 6%.
        INSERT INTO TMS_SOURCE.VTTK (TKNUM, VBELN, WERKS, CARRIER_CD, DPTBG, PROM_DLV_DT, ACT_DLV_DT,
                                     FREIGHT_AMT, DUTY_AMT, HANDLING_AMT, SHP_STATUS, WAERS, LOAD_TS)
        WITH ns AS (
            SELECT s.*, 'SHP' || LPAD(:max_shp + ROW_NUMBER() OVER (ORDER BY s.n, s.werks, s.part_no), 9, '0') AS tknum,
                   CASE WHEN s.act <= :d THEN s.act END AS act_dlv
            FROM TMP_S s
            WHERE s.dptbg = :d
              AND NOT EXISTS (SELECT 1 FROM TMP_SHIPID x WHERE x.vbeln = s.vbeln AND x.WERKS = s.werks AND x.part_no = s.part_no)),
        st AS (
            SELECT ns.*, CASE WHEN ns.act_dlv IS NOT NULL AND ns.act_dlv <= ns.prom THEN 'DELIVERED'
                              WHEN ns.act_dlv IS NOT NULL THEN 'DELAYED'
                              WHEN :d > ns.prom THEN 'DELAYED' ELSE 'IN_TRANSIT' END AS status,
                   BITAND(HASH(:SEED, 'VTTK', ns.tknum, 'A03s'), 4294967295) / 4294967295.0 AS u_ms,
                   BITAND(HASH(:SEED, 'VTTK', ns.tknum, 'A03c'), 4294967295) / 4294967295.0 AS u_mc
            FROM ns)
        SELECT st.tknum, st.vbeln, st.werks,
               COALESCE(vc.VARIANT, st.CARRIER_CD), st.dptbg, st.prom, st.act_dlv,
               ROUND(st.freight_usd / fx.rate, 2), ROUND(st.duty_usd / fx.rate, 2), ROUND(st.handling_usd / fx.rate, 2),
               COALESCE(vs.VARIANT, st.status), st.waers,
               TIMESTAMPADD(minute, (120 + LEAST(180, FLOOR(181 * st.u_load)))::INT, DATEADD(day, 1, :d)::TIMESTAMP_NTZ)
        FROM st
        JOIN TMP_FX fx ON fx.CUR = st.waers AND fx.d = st.dptbg
        LEFT JOIN TMP_VAR vs ON st.u_ms < 0.03 AND vs.DOMAIN = 'SHIPMENT_STATUS' AND vs.CANONICAL = st.status
             AND vs.IDX = LEAST(vs.CNT, 1 + FLOOR(st.u_ms / 0.03 * vs.CNT))::INT
        LEFT JOIN TMP_VAR vc ON st.u_mc < 0.06 AND vc.DOMAIN = 'CARRIER' AND vc.CANONICAL = st.CARRIER_CD
             AND vc.IDX = LEAST(vc.CNT, 1 + FLOOR(st.u_mc / 0.06 * vc.CNT))::INT;
        n_rows := SQLROWCOUNT;
        INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
        SELECT :run_id, :TARGET_DB, 'append', 'VTTK new', :d::VARCHAR, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

        -- Shipments delivered on D, or overdue since D: a new version of the latest row.
        -- E01 (0.8% of deliveries lose their promised date), M03 status variants 3%.
        INSERT INTO TMS_SOURCE.VTTK (TKNUM, VBELN, WERKS, CARRIER_CD, DPTBG, PROM_DLV_DT, ACT_DLV_DT,
                                     FREIGHT_AMT, DUTY_AMT, HANDLING_AMT, SHP_STATUS, WAERS, LOAD_TS)
        WITH ev AS (
            SELECT s.*, x.TKNUM AS tknum,
                   CASE WHEN s.act = :d THEN s.act END AS act_dlv,
                   CASE WHEN s.act = :d AND s.act <= s.prom THEN 'DELIVERED' ELSE 'DELAYED' END AS status,
                   BITAND(HASH(:SEED, 'VTTK', x.TKNUM, :d, 'A01'), 4294967295) / 4294967295.0 AS u_e01,
                   BITAND(HASH(:SEED, 'VTTK', x.TKNUM, :d, 'A03s'), 4294967295) / 4294967295.0 AS u_ms
            FROM TMP_S s
            JOIN TMP_SHIPID x ON x.vbeln = s.vbeln AND x.WERKS = s.werks AND x.part_no = s.part_no
            WHERE s.dptbg < :d
              AND (s.act = :d OR (s.act > :d AND s.prom = DATEADD(day, -1, :d))))
        SELECT v.TKNUM, v.VBELN, v.WERKS, v.CARRIER_CD, v.DPTBG,
               IFF(ev.act_dlv IS NOT NULL AND ev.u_e01 < 0.008, NULL, v.PROM_DLV_DT),
               ev.act_dlv, v.FREIGHT_AMT, v.DUTY_AMT, v.HANDLING_AMT,
               COALESCE(vs.VARIANT, ev.status), v.WAERS,
               TIMESTAMPADD(minute, (120 + LEAST(180, FLOOR(181 * ev.u_load)))::INT, DATEADD(day, 1, :d)::TIMESTAMP_NTZ)
        FROM ev
        JOIN TMP_VTTK_LAST v ON v.TKNUM = ev.tknum
        LEFT JOIN TMP_VAR vs ON ev.u_ms < 0.03 AND vs.DOMAIN = 'SHIPMENT_STATUS' AND vs.CANONICAL = ev.status
             AND vs.IDX = LEAST(vs.CNT, 1 + FLOOR(ev.u_ms / 0.03 * vs.CNT))::INT;
        n_rows := SQLROWCOUNT;
        INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
        SELECT :run_id, :TARGET_DB, 'append', 'VTTK versions', :d::VARCHAR, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

        -- Lines of the orders placed on D (new), and of the orders that ship on D (a new
        -- version of the latest row with QTY_SHIPPED, §3.3; E04 over-ships 1%).
        INSERT INTO ERP_SOURCE.VBAP (LINE_ID, VBELN, MATNR, WERKS, KWMENG, QTY_SHIPPED, NETPR, LOAD_TS)
        SELECT l.line_id, l.vbeln, l.MATNR, l.werks, l.kwmeng, 0, ROUND(l.price_usd / fx.rate, 2),
               TIMESTAMPADD(minute, (120 + LEAST(180, FLOOR(181 * l.u_load)))::INT, DATEADD(day, 1, :d)::TIMESTAMP_NTZ)
        FROM TMP_L l
        JOIN TMP_FX fx ON fx.CUR = l.waerk AND fx.d = l.audat
        WHERE l.audat = :d
          AND NOT EXISTS (SELECT 1 FROM ERP_SOURCE.VBAP x WHERE x.LINE_ID = l.line_id);
        n_rows := SQLROWCOUNT;
        INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
        SELECT :run_id, :TARGET_DB, 'append', 'VBAP new', :d::VARCHAR, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

        INSERT INTO ERP_SOURCE.VBAP (LINE_ID, VBELN, MATNR, WERKS, KWMENG, QTY_SHIPPED, NETPR, LOAD_TS)
        SELECT v.LINE_ID, v.VBELN, v.MATNR, v.WERKS, v.KWMENG,
               CASE WHEN BITAND(HASH(:SEED, 'VBAP', l.line_id, 'A04'), 4294967295) / 4294967295.0 < 0.01
                    THEN ROUND(v.KWMENG * (1.05 + 0.15 * BITAND(HASH(:SEED, 'VBAP', l.line_id, 'E04q'), 4294967295) / 4294967295.0))
                    WHEN l.u_short < l.p_short THEN ROUND(l.kwmeng * (0.40 + 0.55 * l.u_shortq))
                    ELSE l.kwmeng END,
               v.NETPR,
               TIMESTAMPADD(minute, (120 + LEAST(180, FLOOR(181 * l.u_load)))::INT, DATEADD(day, 1, :d)::TIMESTAMP_NTZ)
        FROM TMP_L l
        JOIN TMP_VBAP_LAST v ON v.LINE_ID = l.line_id
        WHERE l.is_shipped AND NOT l.was_shipped;
        n_rows := SQLROWCOUNT;
        INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
        SELECT :run_id, :TARGET_DB, 'append', 'VBAP versions', :d::VARCHAR, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

        -- Orders: new ones placed on D (OPEN, or CANCELLED at 4%), then a new version of every
        -- order whose status changes on D. ERDAT as the generator sets it. M03: status 3%,
        -- priority 2% (new orders; a version keeps the latest row's priority).
        INSERT INTO ERP_SOURCE.VBAK (VBELN, KUNNR, AUDAT, ERDAT, GBSTK, PRIO, AUART, WAERK, LOAD_TS)
        WITH o AS (
            SELECT o.*, os.status1,
                   BITAND(HASH(:SEED, 'VBAK', o.vbeln, 'A03g'), 4294967295) / 4294967295.0 AS u_mg,
                   BITAND(HASH(:SEED, 'VBAK', o.vbeln, 'A03p'), 4294967295) / 4294967295.0 AS u_mp
            FROM TMP_O o JOIN TMP_OS os ON os.n = o.n
            WHERE o.audat = :d
              AND NOT EXISTS (SELECT 1 FROM TMP_VBAK_LAST x WHERE UPPER(TRIM(x.VBELN)) = o.vbeln))
        SELECT o.vbeln, o.KUNNR, o.audat,
               DATEADD(day, (7 + LEAST(7, FLOOR(o.u_erdat * 8)))::INT, o.audat),
               COALESCE(vg.VARIANT, o.status1), COALESCE(vp.VARIANT, o.prio), 'OR', o.waerk,
               TIMESTAMPADD(minute, (120 + LEAST(180, FLOOR(181 * o.u_load)))::INT, DATEADD(day, 1, :d)::TIMESTAMP_NTZ)
        FROM o
        LEFT JOIN TMP_VAR vg ON o.u_mg < 0.03 AND vg.DOMAIN = 'ORDER_STATUS' AND vg.CANONICAL = o.status1
             AND vg.IDX = LEAST(vg.CNT, 1 + FLOOR(o.u_mg / 0.03 * vg.CNT))::INT
        LEFT JOIN TMP_VAR vp ON o.u_mp < 0.02 AND vp.DOMAIN = 'PRIORITY' AND vp.CANONICAL = o.prio
             AND vp.IDX = LEAST(vp.CNT, 1 + FLOOR(o.u_mp / 0.02 * vp.CNT))::INT;
        n_rows := SQLROWCOUNT;
        INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
        SELECT :run_id, :TARGET_DB, 'append', 'VBAK new', :d::VARCHAR, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

        INSERT INTO ERP_SOURCE.VBAK (VBELN, KUNNR, AUDAT, ERDAT, GBSTK, PRIO, AUART, WAERK, LOAD_TS)
        WITH os AS (
            SELECT os.*, BITAND(HASH(:SEED, 'VBAK', os.vbeln, :d, 'A03g'), 4294967295) / 4294967295.0 AS u_mg
            FROM TMP_OS os
            WHERE os.audat < :d AND os.status1 <> os.status0)
        SELECT v.VBELN, v.KUNNR, v.AUDAT,
               CASE WHEN os.status1 IN ('SHIPPED', 'DELIVERED')
                    THEN CASE WHEN os.u_conf < 0.20 THEN DATEADD(day, (-(2 + LEAST(5, FLOOR(os.u_confd * 6))))::INT, os.first_prom)
                              ELSE os.first_prom END
                    ELSE v.ERDAT END,
               COALESCE(vg.VARIANT, os.status1), v.PRIO, v.AUART, v.WAERK,
               TIMESTAMPADD(minute, (120 + LEAST(180, FLOOR(181 * os.u_load)))::INT, DATEADD(day, 1, :d)::TIMESTAMP_NTZ)
        FROM os
        JOIN TMP_VBAK_LAST v ON UPPER(TRIM(v.VBELN)) = os.vbeln
        LEFT JOIN TMP_VAR vg ON os.u_mg < 0.03 AND vg.DOMAIN = 'ORDER_STATUS' AND vg.CANONICAL = os.status1
             AND vg.IDX = LEAST(vg.CNT, 1 + FLOOR(os.u_mg / 0.03 * vg.CNT))::INT;
        n_rows := SQLROWCOUNT;
        INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
        SELECT :run_id, :TARGET_DB, 'append', 'VBAK versions', :d::VARCHAR, :n_rows, :t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

        COMMIT;
        days_added := days_added + 1;
    END FOR;

    -- ── 4. Result ───────────────────────────────────────────────────────────
    stage := 'result';
    result := (SELECT OBJECT_CONSTRUCT(
               'status', 'OK', 'run_id', :run_id, 'target_db', :TARGET_DB,
               'from_end_date', :from_end, 'new_end_date', :NEW_END_DATE, 'days_added', :days_added,
               'rows', (SELECT OBJECT_AGG(TABLE_NAME, TO_VARIANT(n)) FROM (
                          SELECT TABLE_NAME, SUM(ROWS_WRITTEN) AS n FROM SUPPLY_CHAIN_FORGE.OPS.GEN_LOG
                          WHERE RUN_ID = :run_id AND STAGE = 'append' GROUP BY TABLE_NAME)),
               'max_load_ts', (SELECT MAX(LOAD_TS) FROM ERP_SOURCE.VBAK),
               'elapsed_s', DATEDIFF(millisecond, :run_t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ) / 1000));
    INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT)
    SELECT :run_id, :TARGET_DB, 'done', NULL, NULL, :days_added, :run_t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
    RETURN result;

EXCEPTION
    WHEN OTHER THEN
        LET err_code VARCHAR := SQLCODE;
        LET err_msg VARCHAR := SQLERRM;
        ROLLBACK;  -- the failing day leaves nothing behind; earlier days stay committed
        INSERT INTO SUPPLY_CHAIN_FORGE.OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK, ROWS_WRITTEN, STARTED_AT, ENDED_AT, PARAMS)
        SELECT COALESCE(:run_id, 'unknown'), :TARGET_DB, 'error', NULL, :stage, :days_added, :run_t0, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
               OBJECT_CONSTRUCT('sqlcode', :err_code, 'sqlerrm', :err_msg);
        RETURN OBJECT_CONSTRUCT('status', 'ERROR', 'run_id', run_id, 'stage', stage, 'days_added', days_added,
                                'sqlcode', err_code, 'sqlerrm', err_msg);
END;
$$;
