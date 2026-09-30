-- ============================================================================
-- quality/40_sp_dq_self_checks.sql — OPS.SP_DQ_SELF_CHECKS: the C10 gate as one query
-- Card:       C10 (.agents/tasks/claude/C10_data_quality.md)
-- Spec:       docs/DATA_SPEC.md §7.2 (shape, layering), §4 (rates)
-- Role:       create as ACCOUNTADMIN, CALL as FORGE_ADMIN (the role the app and the tool
--             run as: it proves the grants too)        Warehouse: FORGE_WH
-- Run order:  5 of 6 (00 → 10 → 20 → 30 → 40 → 99). Re-runnable: CREATE OR REPLACE.
-- Parameters: TARGET_DB (SUPPLY_CHAIN_FORGE, for a clone only the coverage rows run,
--             because SP_DATA_HEALTH reads SUPPLY_CHAIN_FORGE).
-- Returns:    TABLE (CHECK_ID, TABLE_NAME, EXPECTED, ACTUAL, TOLERANCE, PASSED, DETAIL), the
--             same shape as C08's SP_GEN_SELF_CHECKS:
--             - HEALTH_SHAPE_<ENTITY> (9 + ALL): every §7.2 key present, 1 or 9 entities,
--               the catalogue's number of checks per entity, a valid status
--             - HEALTH_BAD_ENTITY: an unknown entity gives status ERROR and no entities
--             - HEALTH_ALL_SIZE: the ALL answer is ≤ 16,384 bytes
--             - HEALTH_AS_OF: ALL's as_of_date = the shipments' latest business date
--             - HEALTH_NO_FAILED_CHECKS: no check FAILs (no repairable defect left in CONFORMED)
--             - HEALTH_REFERENCE_KINDS / HEALTH_REFERENCE_NOT_AGED (C16): the 5 reference
--               entities read freshness_status REFERENCE, and their status is their checks'
--               worst, never their age
--             - DQ_<CHECK_ID> (46): SOURCE shows each defect (INFO: > 0, MAX_RATE: between
--               0.95 × the injected count in OPS.GEN_MESS_LOG (B12: later repairs can undo a
--               few, E04 measured 19,390 of 19,589) and 1.25 × it + 5, since M01/M02
--               copies can repeat a defective row), CONFORMED ZERO rows are 0, CONFORMED
--               MAX_RATE rows are > 0 and within threshold
--             - DQ_<CHECK_ID> for the 31 ROW_COUNT / FRESHNESS associations: a result exists
-- Expected:   every row PASSED = TRUE (NULL only for the skipped-for-a-clone row). A FALSE
--             with "no DMF result yet" means the schedule hasn't run: wait and call again.
-- ============================================================================

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_FORGE.OPS.SP_DQ_SELF_CHECKS(TARGET_DB VARCHAR)
RETURNS TABLE (CHECK_ID VARCHAR, TABLE_NAME VARCHAR, EXPECTED FLOAT, ACTUAL FLOAT, TOLERANCE FLOAT,
               PASSED BOOLEAN, DETAIL VARCHAR)
LANGUAGE SQL
COMMENT = 'C10: DMF results by layer, and the SP_DATA_HEALTH shape for every entity (the C10 gate).'
EXECUTE AS CALLER
AS
$$
DECLARE
    ok_name     BOOLEAN;
    asked       ARRAY DEFAULT ARRAY_CONSTRUCT('suppliers', 'parts', 'sourcing', 'plants', 'inventory', 'customers',
                                              'orders', 'order_lines', 'shipments', 'ALL', 'no_such_entity');
    e           VARCHAR;
    hj          VARCHAR;
    health      OBJECT DEFAULT OBJECT_CONSTRUCT();
    health_json VARCHAR DEFAULT '{}';
    rs          RESULTSET;
BEGIN
    SELECT COALESCE(REGEXP_LIKE(:TARGET_DB, '^[A-Za-z_][A-Za-z0-9_$]*$'), FALSE) INTO :ok_name;
    IF (NOT ok_name) THEN
        rs := (SELECT 'PARAMETERS' AS CHECK_ID, NULL::VARCHAR AS TABLE_NAME, NULL::FLOAT AS EXPECTED, NULL::FLOAT AS ACTUAL,
                      NULL::FLOAT AS TOLERANCE, FALSE AS PASSED, 'TARGET_DB must be a plain identifier' AS DETAIL);
        RETURN TABLE(rs);
    END IF;

    -- Ask SP_DATA_HEALTH about every entity, ALL, and one unknown entity.
    IF (UPPER(TARGET_DB) = 'SUPPLY_CHAIN_FORGE') THEN
        FOR i IN 0 TO 10 DO
            e := GET(asked, i)::VARCHAR;
            BEGIN
                CALL SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH(:e);
                SELECT TO_JSON($1) INTO :hj FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
            EXCEPTION
                WHEN OTHER THEN
                    hj := TO_JSON(OBJECT_CONSTRUCT('_error', SQLERRM));
            END;
            health := OBJECT_INSERT(health, e, PARSE_JSON(hj));
        END FOR;
        health_json := TO_JSON(health);
    END IF;

    rs := (
        WITH h AS (SELECT PARSE_JSON(:health_json) AS J),
        answers AS (SELECT k.key AS ASKED, k.value AS R FROM h, LATERAL FLATTEN(INPUT => h.J) k),
        ent_rows AS (SELECT a.ASKED, x.value AS E FROM answers a, LATERAL FLATTEN(INPUT => a.R:entities) x),
        chk_rows AS (SELECT r.ASKED, c.value AS C FROM ent_rows r, LATERAL FLATTEN(INPUT => r.E:checks) c),
        ent_missing AS (
            SELECT ASKED, COUNT(*) AS N,
                   SUM(ARRAY_SIZE(ARRAY_EXCEPT(ARRAY_CONSTRUCT('entity', 'table', 'row_count', 'latest_business_date',
                                                               'latest_load_ts', 'freshness_hours', 'freshness_status',
                                                               'status', 'checks'), OBJECT_KEYS(E)))) AS MISSING
            FROM ent_rows GROUP BY ASKED
        ),
        chk_missing AS (
            SELECT ASKED, COUNT(*) AS N, COUNT_IF(C:status::VARCHAR = 'FAIL') AS FAILS,
                   SUM(ARRAY_SIZE(ARRAY_EXCEPT(ARRAY_CONSTRUCT('check', 'code', 'layer', 'dmf', 'table', 'columns', 'value',
                                                               'rate', 'threshold_rate', 'status', 'handled_by',
                                                               'measured_at'), OBJECT_KEYS(C)))) AS MISSING
            FROM chk_rows GROUP BY ASKED
        ),
        catalogue_n AS (
            SELECT ENTITY, COUNT(*) AS N FROM SUPPLY_CHAIN_FORGE.OPS.DQ_CHECKS
            WHERE EXPECT IN ('ZERO', 'MAX_RATE', 'INFO') GROUP BY ENTITY
        ),
        shape AS (
            SELECT a.ASKED,
                   IFF(IS_OBJECT(a.R),
                       ARRAY_SIZE(ARRAY_EXCEPT(ARRAY_CONSTRUCT('entity', 'generated_at', 'as_of_date', 'status', 'summary',
                                                               'entities'), OBJECT_KEYS(a.R))), 6)
                     + COALESCE(em.MISSING, 0) + COALESCE(cm.MISSING, 0) AS MISSING,
                   a.R:status::VARCHAR AS STATUS, a.R:as_of_date::VARCHAR AS AS_OF, a.R:"_error"::VARCHAR AS ERR,
                   LENGTH(TO_JSON(a.R)) AS BYTES,
                   COALESCE(em.N, 0) AS N_ENT, COALESCE(cm.N, 0) AS N_CHK, COALESCE(cm.FAILS, 0) AS FAILS,
                   IFF(a.ASKED = 'ALL', 9, 1) AS WANT_ENT,
                   IFF(a.ASKED = 'ALL', NULL, COALESCE(cn.N, 0)) AS WANT_CHK
            FROM answers a
            LEFT JOIN ent_missing em ON em.ASKED = a.ASKED
            LEFT JOIN chk_missing cm ON cm.ASKED = a.ASKED
            LEFT JOIN catalogue_n cn ON cn.ENTITY = a.ASKED
            WHERE a.ASKED <> 'no_such_entity'
        ),
        mess AS (
            SELECT CODE, TABLE_NAME, AFFECTED_ROWS FROM SUPPLY_CHAIN_FORGE.OPS.GEN_MESS_LOG
            WHERE TARGET_DB = :TARGET_DB
            QUALIFY ROW_NUMBER() OVER (PARTITION BY CODE, TABLE_NAME ORDER BY LOGGED_AT DESC) = 1
        ),
        per_check AS (
            SELECT cat.CHECK_ID, cat.LAYER, cat.EXPECT, cat.SCHEMA_NAME || '.' || cat.TABLE_NAME AS TBL, cat.THRESHOLD_RATE,
                   x.C:value::FLOAT AS VALUE, x.C:rate::FLOAT AS RATE, x.C:status::VARCHAR AS STATUS,
                   m.AFFECTED_ROWS::FLOAT AS INJECTED
            FROM chk_rows x
            JOIN SUPPLY_CHAIN_FORGE.OPS.DQ_CHECKS cat
              ON 'SUPPLY_CHAIN_FORGE.' || cat.SCHEMA_NAME || '.' || cat.TABLE_NAME = x.C:table::VARCHAR
             AND cat.CHECK_NAME = x.C:check::VARCHAR
            LEFT JOIN mess m ON m.CODE = cat.CODE AND m.TABLE_NAME = cat.TABLE_NAME AND cat.LAYER = 'SOURCE'
            WHERE x.ASKED <> 'ALL'
        ),
        dq AS (
            SELECT table_schema, table_name, metric_name, value::FLOAT AS VALUE
            FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
            WHERE table_database = :TARGET_DB AND metric_schema = 'CORE' AND metric_name IN ('ROW_COUNT', 'FRESHNESS')
            QUALIFY ROW_NUMBER() OVER (PARTITION BY table_schema, table_name, metric_name ORDER BY measurement_time DESC) = 1
        ),
        coverage AS (
            SELECT cat.CHECK_ID, cat.SCHEMA_NAME || '.' || cat.TABLE_NAME AS TBL, cat.EXPECT, d.VALUE
            FROM SUPPLY_CHAIN_FORGE.OPS.DQ_CHECKS cat
            LEFT JOIN dq d ON d.table_schema = cat.SCHEMA_NAME AND d.table_name = cat.TABLE_NAME
                          AND d.metric_name = SPLIT_PART(cat.DMF, '.', -1)
            WHERE cat.EXPECT IN ('VOLUME', 'FRESHNESS')
        )
        SELECT 'HEALTH_SHAPE_' || UPPER(ASKED) AS CHECK_ID, 'SEMANTIC.SP_DATA_HEALTH' AS TABLE_NAME,
               0::FLOAT AS EXPECTED, MISSING::FLOAT AS ACTUAL, NULL::FLOAT AS TOLERANCE,
               COALESCE(MISSING = 0 AND ERR IS NULL AND N_ENT = WANT_ENT AND (WANT_CHK IS NULL OR N_CHK = WANT_CHK)
                        AND STATUS IN ('OK', 'WARN', 'FAIL', 'UNKNOWN'), FALSE) AS PASSED,
               'missing keys ' || MISSING || '; entities ' || N_ENT || '/' || WANT_ENT || '; checks ' || N_CHK
                 || COALESCE('/' || WANT_CHK, '') || '; status ' || COALESCE(STATUS, '?') || '; ' || BYTES || ' bytes'
                 || COALESCE('; error: ' || ERR, '') AS DETAIL
        FROM shape
        UNION ALL
        SELECT 'HEALTH_BAD_ENTITY', 'SEMANTIC.SP_DATA_HEALTH', NULL::FLOAT, NULL::FLOAT, NULL::FLOAT,
               COALESCE(R:status::VARCHAR = 'ERROR' AND ARRAY_SIZE(R:entities) = 0, FALSE),
               'status ' || COALESCE(R:status::VARCHAR, '?') || '; summary: ' || COALESCE(R:summary::VARCHAR, R:"_error"::VARCHAR, '?')
        FROM answers WHERE ASKED = 'no_such_entity'
        UNION ALL
        SELECT 'HEALTH_ALL_SIZE', 'SEMANTIC.SP_DATA_HEALTH', 16384::FLOAT, BYTES::FLOAT, NULL::FLOAT,
               COALESCE(BYTES <= 16384, FALSE), 'bytes of the ALL answer (the agent tool budget)'
        FROM shape WHERE ASKED = 'ALL'
        UNION ALL
        SELECT 'HEALTH_AS_OF', 'SEMANTIC.SP_DATA_HEALTH', NULL::FLOAT, NULL::FLOAT, NULL::FLOAT,
               COALESCE(a.AS_OF IS NOT NULL AND a.AS_OF = s.E:latest_business_date::VARCHAR, FALSE),
               'ALL as_of_date ' || COALESCE(a.AS_OF, 'null') || '; shipments latest_business_date '
                 || COALESCE(s.E:latest_business_date::VARCHAR, 'null')
        FROM shape a LEFT JOIN ent_rows s ON s.ASKED = 'shipments'
        WHERE a.ASKED = 'ALL'
        UNION ALL
        SELECT 'HEALTH_NO_FAILED_CHECKS', 'SEMANTIC.SP_DATA_HEALTH', 0::FLOAT, SUM(FAILS)::FLOAT, NULL::FLOAT,
               COALESCE(SUM(FAILS) = 0, FALSE), 'checks with status FAIL across the 9 single-entity answers'
        FROM shape WHERE ASKED <> 'ALL'
        HAVING COUNT(*) > 0
        UNION ALL
        -- C16 (freshness fix 1): the 5 reference entities read REFERENCE, the 4 daily ones never do
        SELECT 'HEALTH_REFERENCE_KINDS', 'SEMANTIC.SP_DATA_HEALTH', 5::FLOAT,
               COUNT_IF(E:freshness_status::VARCHAR = 'REFERENCE')::FLOAT, NULL::FLOAT,
               COALESCE(COUNT_IF(E:freshness_status::VARCHAR = 'REFERENCE'
                                 AND E:entity::VARCHAR IN ('suppliers', 'parts', 'sourcing', 'plants', 'customers')) = 5
                        AND COUNT_IF(E:freshness_status::VARCHAR = 'REFERENCE'
                                     AND E:entity::VARCHAR IN ('orders', 'order_lines', 'shipments', 'inventory')) = 0, FALSE),
               'entities reading REFERENCE in the ALL answer (want the 5 reference ones only)'
        FROM ent_rows WHERE ASKED = 'ALL'
        UNION ALL
        -- ... and a reference entity's status is its checks' worst, whatever its age
        SELECT 'HEALTH_REFERENCE_NOT_AGED', 'SEMANTIC.SP_DATA_HEALTH', 0::FLOAT, COUNT(*)::FLOAT, NULL::FLOAT,
               COUNT(*) = 0,
               'reference entities whose status is worse than their worst check: '
                 || COALESCE(LISTAGG(ASKED, ', '), 'none')
        FROM (
            SELECT r.ASKED, r.E:status::VARCHAR AS ENT_STATUS,
                   MAX(DECODE(c.C:status::VARCHAR, 'OK', 0, 'UNKNOWN', 1, 'WARN', 2, 'FAIL', 3, 0)) AS CHECK_SEV
            FROM ent_rows r
            LEFT JOIN chk_rows c ON c.ASKED = r.ASKED
            WHERE r.ASKED IN ('suppliers', 'parts', 'sourcing', 'plants', 'customers')
            GROUP BY r.ASKED, r.E:status::VARCHAR
        )
        WHERE DECODE(ENT_STATUS, 'OK', 0, 'UNKNOWN', 1, 'WARN', 2, 3) > COALESCE(CHECK_SEV, 0)
        UNION ALL
        SELECT 'HEALTH', 'SEMANTIC.SP_DATA_HEALTH', NULL::FLOAT, NULL::FLOAT, NULL::FLOAT, NULL::BOOLEAN,
               'skipped: SP_DATA_HEALTH reads SUPPLY_CHAIN_FORGE only, not ' || :TARGET_DB
        FROM h WHERE :health_json = '{}'
        UNION ALL
        SELECT 'DQ_' || CHECK_ID, TBL,
               CASE WHEN EXPECT = 'ZERO' THEN 0
                    WHEN LAYER = 'SOURCE' AND EXPECT = 'MAX_RATE' THEN INJECTED
                    WHEN LAYER = 'CONFORMED' AND EXPECT = 'MAX_RATE' THEN THRESHOLD_RATE END::FLOAT,
               IFF(LAYER = 'CONFORMED' AND EXPECT = 'MAX_RATE', RATE, VALUE)::FLOAT,
               IFF(LAYER = 'SOURCE' AND EXPECT = 'MAX_RATE' AND INJECTED IS NOT NULL, 0.25, NULL)::FLOAT,
               COALESCE(CASE WHEN STATUS = 'UNKNOWN' OR VALUE IS NULL THEN FALSE
                             WHEN EXPECT = 'ZERO' THEN VALUE = 0
                             WHEN EXPECT = 'INFO' THEN VALUE > 0
                             WHEN LAYER = 'SOURCE' AND INJECTED IS NOT NULL
                                  THEN VALUE >= INJECTED * 0.95 AND VALUE <= INJECTED * 1.25 + 5 AND STATUS = 'OK'
                             ELSE VALUE > 0 AND STATUS = 'OK' END, FALSE),
               'layer ' || LAYER || '; expect ' || EXPECT || '; status ' || COALESCE(STATUS, '?')
                 || '; value ' || COALESCE(VALUE::VARCHAR, 'null') || COALESCE('; rate ' || ROUND(RATE, 6), '')
                 || COALESCE('; injected ' || INJECTED::NUMBER, '')
                 || IFF(STATUS = 'UNKNOWN', '; no DMF result yet (wait for the schedule)', '')
        FROM per_check
        UNION ALL
        SELECT 'DQ_' || CHECK_ID, TBL, NULL::FLOAT, VALUE, NULL::FLOAT,
               COALESCE(IFF(EXPECT = 'VOLUME', VALUE > 0, VALUE IS NOT NULL), FALSE),
               IFF(VALUE IS NULL, 'no DMF result yet (wait for the schedule)',
                   IFF(EXPECT = 'VOLUME', 'rows', 'seconds since the latest load timestamp'))
        FROM coverage
        ORDER BY 1
    );
    RETURN TABLE(rs);
END;
$$;

GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.OPS.SP_DQ_SELF_CHECKS(VARCHAR) TO ROLE FORGE_ADMIN;
