-- ============================================================================
-- data_gen/30_sp_gen_self_checks.sql — OPS.SP_GEN_SELF_CHECKS: did the generator do its job?
-- Card:       C08 (.agents/tasks/claude/C08_data_generator.md)
-- Spec:       docs/DATA_SPEC.md §7.1 (self-checks), §2 (volumes), §4 (rates), §5.4 (targets)
-- Role:       ACCOUNTADMIN        Warehouse: FORGE_WH
-- Run order:  4 of 5 (00 → 10 → 20 → 30 → 99). Re-runnable: CREATE OR REPLACE.
-- Parameters: TARGET_DB.
-- Returns:    TABLE (CHECK_ID, TABLE_NAME, EXPECTED, ACTUAL, TOLERANCE, PASSED, DETAIL), one row
--             per check, for the latest completed SP_GENERATE_DATA run on TARGET_DB and the
--             SP_INJECT_MESS run after it (if any). PASSED is NULL for report-only rows
--             (M05 currency shares, APAC share, a checksum with no earlier run to compare).
-- Expected:   every row PASSED = TRUE or NULL.
-- ============================================================================

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_FORGE.OPS.SP_GEN_SELF_CHECKS(TARGET_DB VARCHAR)
RETURNS TABLE (CHECK_ID VARCHAR, TABLE_NAME VARCHAR, EXPECTED FLOAT, ACTUAL FLOAT, TOLERANCE FLOAT,
               PASSED BOOLEAN, DETAIL VARCHAR)
LANGUAGE SQL
EXECUTE AS CALLER
COMMENT = 'C08: row counts, uniqueness, determinism, §4 rates and §5.4 targets for the latest generated load.'
AS
$$
DECLARE
    ok_name     BOOLEAN;
    gen_run     VARCHAR;
    gen_ts      TIMESTAMP_NTZ;
    mess_run    VARCHAR;
    sf          FLOAT;
    gen_seed    NUMBER;
    gen_end     DATE;
    rs          RESULTSET;
BEGIN
    SELECT COALESCE(REGEXP_LIKE(:TARGET_DB, '^[A-Za-z_][A-Za-z0-9_$]*$'), FALSE) INTO :ok_name;
    IF (NOT ok_name) THEN
        rs := (SELECT 'PARAMETERS' AS CHECK_ID, NULL::VARCHAR AS TABLE_NAME, NULL::FLOAT AS EXPECTED, NULL::FLOAT AS ACTUAL,
                      NULL::FLOAT AS TOLERANCE, FALSE AS PASSED, 'TARGET_DB must be a plain identifier' AS DETAIL);
        RETURN TABLE(rs);
    END IF;
    EXECUTE IMMEDIATE 'USE SCHEMA ' || :TARGET_DB || '.OPS';

    -- The latest completed generator run on this database, and the injection after it.
    SELECT MAX_BY(l.RUN_ID, l.STARTED_AT), MAX(l.STARTED_AT),
           MAX_BY(l.PARAMS:scale_factor::FLOAT, l.STARTED_AT), MAX_BY(l.PARAMS:seed::NUMBER, l.STARTED_AT),
           MAX_BY(l.PARAMS:end_date::DATE, l.STARTED_AT)
      INTO :gen_run, :gen_ts, :sf, :gen_seed, :gen_end
    FROM SUPPLY_CHAIN_FORGE.OPS.GEN_LOG l
    WHERE l.TARGET_DB = :TARGET_DB AND l.STAGE = 'start' AND l.PARAMS:procedure::VARCHAR = 'SP_GENERATE_DATA'
      AND EXISTS (SELECT 1 FROM SUPPLY_CHAIN_FORGE.OPS.GEN_LOG d WHERE d.RUN_ID = l.RUN_ID AND d.STAGE = 'done');
    SELECT MAX_BY(l.RUN_ID, l.STARTED_AT) INTO :mess_run
    FROM SUPPLY_CHAIN_FORGE.OPS.GEN_LOG l
    WHERE l.TARGET_DB = :TARGET_DB AND l.STAGE = 'start' AND l.PARAMS:procedure::VARCHAR = 'SP_INJECT_MESS'
      AND l.STARTED_AT > :gen_ts
      AND EXISTS (SELECT 1 FROM SUPPLY_CHAIN_FORGE.OPS.GEN_LOG d WHERE d.RUN_ID = l.RUN_ID AND d.STAGE = 'done');

    CREATE OR REPLACE TEMPORARY TABLE TMP_CHECKS (
        CHECK_ID VARCHAR, TABLE_NAME VARCHAR, EXPECTED FLOAT, ACTUAL FLOAT, TOLERANCE FLOAT, PASSED BOOLEAN, DETAIL VARCHAR);

    IF (gen_run IS NULL) THEN
        INSERT INTO TMP_CHECKS VALUES ('GENERATOR_RUN', NULL, NULL, NULL, NULL, FALSE,
            'No completed SP_GENERATE_DATA run found for this database');
        rs := (SELECT * FROM TMP_CHECKS);
        RETURN TABLE(rs);
    END IF;

    -- 1. Row counts of the clean load vs §2 (fixed masters exact; "~" tables ±10%).
    INSERT INTO TMP_CHECKS
    WITH exp AS (
        SELECT v.T, v.E * CASE WHEN v.SCALED THEN :sf ELSE 1 END AS e, v.TOL
        FROM (VALUES ('T001W', 12, FALSE, 0.0), ('LFA1', 150, FALSE, 0.0), ('MARA', 1200, FALSE, 0.0),
                     ('KNA1', 2000, FALSE, 0.0), ('TCURR', 23300, FALSE, 0.10), ('SOURCING', 2400, FALSE, 0.10),
                     ('VBAK', 650000, TRUE, 0.01), ('VBAP', 2000000, TRUE, 0.10), ('VTTK', 720000, TRUE, 0.10),
                     ('MARD', 2200000, FALSE, 0.10)) AS v(T, E, SCALED, TOL))
    SELECT 'ROWS_CLEAN', exp.T, exp.e, st.VALUE, exp.TOL,
           ABS(st.VALUE - exp.e) <= exp.TOL * exp.e + 0.5,
           'relative tolerance; SF ' || :sf
    FROM exp JOIN SUPPLY_CHAIN_FORGE.OPS.GEN_STATS st
      ON st.RUN_ID = :gen_run AND st.PHASE = 'CLEAN' AND st.NAME = 'ROWS' AND st.TABLE_NAME = exp.T;

    -- 2. Unique keys in the clean load.
    INSERT INTO TMP_CHECKS
    SELECT 'UNIQUE_KEYS_CLEAN', r.TABLE_NAME, r.VALUE, k.VALUE, 0, r.VALUE = k.VALUE, 'COUNT(*) = COUNT(DISTINCT key)'
    FROM SUPPLY_CHAIN_FORGE.OPS.GEN_STATS r
    JOIN SUPPLY_CHAIN_FORGE.OPS.GEN_STATS k ON k.RUN_ID = r.RUN_ID AND k.PHASE = 'CLEAN' AND k.NAME = 'DISTINCT_KEYS'
     AND k.TABLE_NAME = r.TABLE_NAME
    WHERE r.RUN_ID = :gen_run AND r.PHASE = 'CLEAN' AND r.NAME = 'ROWS';

    -- 3. Determinism: the same checksum as the previous run with the same parameters.
    INSERT INTO TMP_CHECKS
    WITH prev AS (
        SELECT MAX_BY(l.RUN_ID, l.STARTED_AT) AS run_id
        FROM SUPPLY_CHAIN_FORGE.OPS.GEN_LOG l
        WHERE l.TARGET_DB = :TARGET_DB AND l.STAGE = 'start' AND l.PARAMS:procedure::VARCHAR = 'SP_GENERATE_DATA'
          AND l.RUN_ID <> :gen_run AND l.STARTED_AT < :gen_ts
          AND l.PARAMS:scale_factor::FLOAT = :sf
          AND l.PARAMS:seed::NUMBER = :gen_seed
          AND l.PARAMS:end_date::DATE = :gen_end
          AND EXISTS (SELECT 1 FROM SUPPLY_CHAIN_FORGE.OPS.GEN_LOG d WHERE d.RUN_ID = l.RUN_ID AND d.STAGE = 'done'))
    SELECT 'CHECKSUM_REPEAT', c.TABLE_NAME, NULL, NULL, NULL,
           CASE WHEN p.DETAIL IS NULL THEN NULL ELSE c.DETAIL = p.DETAIL END,
           CASE WHEN p.DETAIL IS NULL THEN 'no earlier run with the same parameters; run again to compare'
                ELSE 'this run ' || c.DETAIL || ' vs earlier ' || p.DETAIL END
    FROM SUPPLY_CHAIN_FORGE.OPS.GEN_STATS c
    CROSS JOIN prev
    LEFT JOIN SUPPLY_CHAIN_FORGE.OPS.GEN_STATS p
      ON p.RUN_ID = prev.run_id AND p.PHASE = 'CLEAN' AND p.NAME = 'CHECKSUM' AND p.TABLE_NAME = c.TABLE_NAME
    WHERE c.RUN_ID = :gen_run AND c.PHASE = 'CLEAN' AND c.NAME = 'CHECKSUM';

    -- 4. Clean-load facts vs §2/§3/§5.4 targets (value must be within EXPECTED ± TOLERANCE).
    INSERT INTO TMP_CHECKS
    WITH t AS (
        SELECT v.NAME, v.LO, v.HI, v.GATED
        FROM (VALUES
            ('OTD_T12M', 0.855, 0.885, TRUE), ('OTD_10Y', 0.855, 0.885, TRUE),
            ('OTD_YEAR_MIN', 0.845, 0.895, TRUE), ('OTD_YEAR_MAX', 0.845, 0.895, TRUE),
            ('FILL_T12M', 0.915, 0.945, TRUE), ('FILL_10Y', 0.915, 0.945, TRUE),
            ('FILL_YEAR_MIN', 0.905, 0.945, TRUE), ('FILL_YEAR_MAX', 0.905, 0.945, TRUE),
            ('DOI_LATEST', 20, 40, TRUE), ('DOI_YEAR_MIN', 18, 42, TRUE), ('DOI_YEAR_MAX', 18, 42, TRUE),
            ('LANDED_T12M', 400, 700, TRUE), ('LANDED_10Y', 400, 700, TRUE),
            ('LANDED_YEAR_MIN', 300, 750, TRUE), ('LANDED_YEAR_MAX', 300, 750, TRUE),
            ('E10_CONFLICT_RATE', 0.18, 0.22, TRUE),
            ('PLANT_YEARS_WITHOUT_SHIPMENTS', 0, 0, TRUE),
            ('TCURR_MAX_DAILY_STEP', 0, 0.006, TRUE),
            ('M05_VBAK_NON_USD_RATE', 0.28, 0.48, FALSE), ('M05_VTTK_NON_USD_RATE', 0.30, 0.50, FALSE),
            ('M05_SOURCING_NON_USD_RATE', 0.15, 0.35, FALSE),
            ('APAC_ORDER_SHARE_FIRST_YEAR', 0.15, 0.25, FALSE), ('APAC_ORDER_SHARE_LAST_YEAR', 0.25, 0.36, FALSE)
        ) AS v(NAME, LO, HI, GATED))
    SELECT 'CLEAN_' || t.NAME, NULL, (t.LO + t.HI) / 2, st.VALUE, (t.HI - t.LO) / 2,
           CASE WHEN NOT t.GATED THEN NULL ELSE st.VALUE BETWEEN t.LO AND t.HI END,
           'target ' || t.LO || ' to ' || t.HI || CASE WHEN t.GATED THEN '' ELSE ' (report only)' END
    FROM t LEFT JOIN SUPPLY_CHAIN_FORGE.OPS.GEN_STATS st
      ON st.RUN_ID = :gen_run AND st.PHASE = 'CLEAN' AND st.NAME = t.NAME;

    -- §5.4: the naive ERP-date OTD is at least 8 points below the governed OTD.
    INSERT INTO TMP_CHECKS
    SELECT 'CLEAN_NAIVE_GAP_T12M', NULL, 0.08, g.VALUE - n.VALUE, NULL, g.VALUE - n.VALUE >= 0.08,
           'governed ' || ROUND(g.VALUE, 4) || ' minus naive ' || ROUND(n.VALUE, 4) || '; needs >= 0.08'
    FROM SUPPLY_CHAIN_FORGE.OPS.GEN_STATS g
    JOIN SUPPLY_CHAIN_FORGE.OPS.GEN_STATS n ON n.RUN_ID = g.RUN_ID AND n.PHASE = 'CLEAN' AND n.NAME = 'NAIVE_OTD_T12M'
    WHERE g.RUN_ID = :gen_run AND g.PHASE = 'CLEAN' AND g.NAME = 'OTD_T12M';

    -- 5. M05 gate: every non-USD amount has a TCURR rate on or before its date.
    INSERT INTO TMP_CHECKS
    WITH rates AS (SELECT FCURR, MIN(GDATU) AS first_rate FROM ERP_SOURCE.TCURR GROUP BY FCURR),
    missing AS (
        SELECT 'VBAK' AS t, COUNT(*) AS n FROM ERP_SOURCE.VBAK o LEFT JOIN rates r ON r.FCURR = o.WAERK
        WHERE o.WAERK <> 'USD' AND (r.first_rate IS NULL OR r.first_rate > o.AUDAT)
        UNION ALL SELECT 'VTTK', COUNT(*) FROM TMS_SOURCE.VTTK s LEFT JOIN rates r ON r.FCURR = s.WAERS
        WHERE s.WAERS <> 'USD' AND (r.first_rate IS NULL OR r.first_rate > s.DPTBG)
        UNION ALL SELECT 'SOURCING', COUNT(*) FROM SRM_SOURCE.SOURCING s LEFT JOIN rates r ON r.FCURR = s.WAERS
        WHERE s.WAERS <> 'USD' AND (r.first_rate IS NULL OR r.first_rate > s.VDATU))
    SELECT 'M05_FX_COVERAGE', t, 0, n, 0, n = 0, 'non-USD amounts without a rate on or before their date'
    FROM missing;

    -- 6. The §4 defect rates, as injected (exact counts, so a miss means a bug).
    IF (mess_run IS NULL) THEN
        INSERT INTO TMP_CHECKS VALUES ('MESS_RUN', NULL, NULL, NULL, NULL, NULL,
            'No SP_INJECT_MESS run after this load yet: clean-load checks only');
    ELSE
        INSERT INTO TMP_CHECKS
        SELECT 'RATE_' || m.CODE, m.TABLE_NAME, m.TARGET_RATE,
               m.AFFECTED_ROWS / NULLIFZERO(m.BASE_ROWS),
               GREATEST(0.10 * m.TARGET_RATE, 0.0005),
               ABS(m.AFFECTED_ROWS / NULLIFZERO(m.BASE_ROWS) - m.TARGET_RATE) <= GREATEST(0.10 * m.TARGET_RATE, 0.0005),
               m.AFFECTED_ROWS || ' of ' || m.BASE_ROWS
        FROM SUPPLY_CHAIN_FORGE.OPS.GEN_MESS_LOG m
        WHERE m.RUN_ID = :mess_run;

        -- Cross-checks on the data itself (independent of the log).
        INSERT INTO TMP_CHECKS
        WITH lg AS (SELECT CODE, TABLE_NAME, AFFECTED_ROWS FROM SUPPLY_CHAIN_FORGE.OPS.GEN_MESS_LOG WHERE RUN_ID = :mess_run),
        c AS (
            SELECT 'DUPLICATE_KEYS' AS id, 'VBAK' AS t,
                   (SELECT SUM(AFFECTED_ROWS) FROM lg WHERE CODE IN ('M01', 'M02') AND TABLE_NAME = 'VBAK') AS e,
                   (SELECT COUNT(*) - COUNT(DISTINCT VBELN) FROM ERP_SOURCE.VBAK) AS a
            UNION ALL SELECT 'DUPLICATE_KEYS', 'VTTK',
                   (SELECT SUM(AFFECTED_ROWS) FROM lg WHERE CODE IN ('M01', 'M02') AND TABLE_NAME = 'VTTK'),
                   (SELECT COUNT(*) - COUNT(DISTINCT TKNUM) FROM TMS_SOURCE.VTTK)
            UNION ALL SELECT 'DUPLICATE_KEYS', 'VBAP',
                   (SELECT SUM(AFFECTED_ROWS) FROM lg WHERE CODE = 'M01' AND TABLE_NAME = 'VBAP'),
                   (SELECT COUNT(*) - COUNT(DISTINCT LINE_ID) FROM ERP_SOURCE.VBAP)
            UNION ALL SELECT 'DUPLICATE_KEYS', 'MARD',
                   (SELECT SUM(AFFECTED_ROWS) FROM lg WHERE CODE = 'M01' AND TABLE_NAME = 'MARD'),
                   (SELECT COUNT(*) - COUNT(DISTINCT INV_KEY) FROM WMS_SOURCE.MARD)
            UNION ALL SELECT 'DUPLICATE_KEYS', 'KNA1',
                   (SELECT SUM(AFFECTED_ROWS) FROM lg WHERE CODE = 'M01' AND TABLE_NAME = 'KNA1'),
                   (SELECT COUNT(*) - COUNT(DISTINCT KUNNR) FROM ERP_SOURCE.KNA1)
            UNION ALL SELECT 'TEST_MASTERS', 'KNA1', 5, (SELECT COUNT(DISTINCT KUNNR) FROM ERP_SOURCE.KNA1 WHERE KUNNR LIKE 'TEST%')
            UNION ALL SELECT 'TEST_MASTERS', 'LFA1', 2, (SELECT COUNT(*) FROM SRM_SOURCE.LFA1 WHERE LIFNR LIKE 'TEST%')
            UNION ALL SELECT 'TEST_MASTERS', 'MARA', 4, (SELECT COUNT(*) FROM SRM_SOURCE.MARA WHERE MATNR LIKE 'MAT9999%')
            UNION ALL SELECT 'MISSING_PROMISED_DATE', 'VTTK',
                   (SELECT SUM(AFFECTED_ROWS) FROM lg WHERE CODE = 'E01'),
                   (SELECT COUNT(DISTINCT TKNUM) FROM TMS_SOURCE.VTTK WHERE PROM_DLV_DT IS NULL)
            UNION ALL SELECT 'ORPHAN_LINES', 'VBAP',
                   (SELECT SUM(AFFECTED_ROWS) FROM lg WHERE CODE = 'E09a'),
                   (SELECT COUNT(DISTINCT l.LINE_ID) FROM ERP_SOURCE.VBAP l
                    WHERE NOT EXISTS (SELECT 1 FROM ERP_SOURCE.VBAK o WHERE UPPER(TRIM(o.VBELN)) = UPPER(TRIM(l.VBELN))))
            UNION ALL SELECT 'ORPHAN_SHIPMENTS', 'VTTK',
                   (SELECT SUM(AFFECTED_ROWS) FROM lg WHERE CODE = 'E09b'),
                   (SELECT COUNT(DISTINCT s.TKNUM) FROM TMS_SOURCE.VTTK s
                    WHERE NOT EXISTS (SELECT 1 FROM ERP_SOURCE.VBAK o WHERE UPPER(TRIM(o.VBELN)) = UPPER(TRIM(s.VBELN))))
            UNION ALL SELECT 'FUTURE_DATED_ORDERS', 'VBAK',
                   (SELECT SUM(AFFECTED_ROWS) FROM lg WHERE CODE = 'E12'),
                   (SELECT COUNT(DISTINCT VBELN) FROM ERP_SOURCE.VBAK WHERE AUDAT > LOAD_TS::DATE)
            UNION ALL SELECT 'NON_CONTRACT_CODES', 'VBAK.GBSTK',
                   (SELECT SUM(AFFECTED_ROWS) FROM lg WHERE CODE = 'M03' AND TABLE_NAME = 'VBAK.GBSTK'),
                   (SELECT COUNT(*) FROM ERP_SOURCE.VBAK WHERE GBSTK NOT IN ('OPEN', 'SHIPPED', 'DELIVERED', 'CANCELLED'))
            UNION ALL SELECT 'NON_CONTRACT_CODES', 'VTTK.CARRIER_CD',
                   (SELECT SUM(AFFECTED_ROWS) FROM lg WHERE CODE = 'M03' AND TABLE_NAME = 'VTTK.CARRIER_CD'),
                   (SELECT COUNT(*) FROM TMS_SOURCE.VTTK WHERE CARRIER_CD NOT IN ('DHL_EXPRESS', 'FEDEX_FREIGHT',
                        'MAERSK_LOGISTICS', 'KUEHNE_NAGEL', 'DB_SCHENKER', 'UPS_SUPPLY_CHAIN', 'XPO_LOGISTICS',
                        'CEVA_LOGISTICS', 'FLEXPORT')))
        SELECT 'DATA_' || c.id, c.t, c.e, c.a,
               CASE WHEN c.id IN ('DUPLICATE_KEYS', 'NON_CONTRACT_CODES', 'MISSING_PROMISED_DATE') THEN 0.02 * c.e ELSE 0 END,
               -- M01 copies of already-changed rows can add a few; allow 2% on those checks
               ABS(c.a - c.e) <= CASE WHEN c.id IN ('DUPLICATE_KEYS', 'NON_CONTRACT_CODES', 'MISSING_PROMISED_DATE')
                                      THEN 0.02 * c.e + 1 ELSE 0 END,
               'expected from the injection log vs counted in the data'
        FROM c;

        -- No LOAD_TS after END_DATE 05:00 (§3.8).
        INSERT INTO TMP_CHECKS
        WITH cap AS (SELECT TIMESTAMPADD(hour, 5, :gen_end::TIMESTAMP_NTZ) AS ts),
        x AS (
            SELECT 'VBAK' AS t, COUNT_IF(LOAD_TS > (SELECT ts FROM cap)) AS n FROM ERP_SOURCE.VBAK
            UNION ALL SELECT 'VBAP', COUNT_IF(LOAD_TS > (SELECT ts FROM cap)) FROM ERP_SOURCE.VBAP
            UNION ALL SELECT 'VTTK', COUNT_IF(LOAD_TS > (SELECT ts FROM cap)) FROM TMS_SOURCE.VTTK
            UNION ALL SELECT 'MARD', COUNT_IF(LOAD_TS > (SELECT ts FROM cap)) FROM WMS_SOURCE.MARD
            UNION ALL SELECT 'KNA1', COUNT_IF(LOAD_TS > (SELECT ts FROM cap)) FROM ERP_SOURCE.KNA1)
        SELECT 'LOAD_TS_CAP', t, 0, n, 0, n = 0, 'rows loaded after END_DATE 05:00' FROM x;
    END IF;

    rs := (SELECT * FROM TMP_CHECKS ORDER BY CHECK_ID, TABLE_NAME);
    RETURN TABLE(rs);
END;
$$;
