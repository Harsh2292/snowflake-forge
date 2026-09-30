-- ============================================================================
-- quality/20_sp_attach_dmfs.sql — OPS.SP_ATTACH_DMFS: attach every catalogued DMF
-- Card:       C10 (.agents/tasks/claude/C10_data_quality.md)
-- Spec:       docs/DATA_SPEC.md §7.2 (layering: SOURCE and CONFORMED, schedule)
--             docs/references/data_metric_functions.md §6–7
-- Role:       ACCOUNTADMIN (the owner of the source tables, the CONFORMED tables' owner
--             must be ACCOUNTADMIN or a role granted to it)        Warehouse: FORGE_WH
-- Run order:  3 of 6 (00 → 10 → 20 → 30 → 40 → 99). Re-runnable: CREATE OR REPLACE.
-- Parameters: TARGET_DB  the database to attach in (SUPPLY_CHAIN_FORGE, or a clone at B13).
--             SCHEDULE   applied to every catalogued table: '5 MINUTE' (warm-up, so results
--                        appear right after attaching), 'TRIGGER_ON_CHANGES' (steady state),
--                        'USING CRON ...', or '' (suspends every DMF on those tables).
-- Returns:    TABLE (STEP, OBJECT_NAME, ACTION, DMF, ARGS, STATUS, DETAIL), one row per
--             statement: 21 SET SCHEDULE rows (10 SOURCE + 11 CONFORMED tables) and 77 ADD
--             DMF rows (OPS.DQ_CHECKS).
-- Expected:   first call: every SET SCHEDULE row OK or FALLBACK, every ADD row ADDED.
--             Later calls: SET SCHEDULE rows OK/FALLBACK, ADD rows EXISTS. No ERROR rows.
-- Behaviour:  - An association that already exists is reported EXISTS (error text contains
--               "already", to verify live), never duplicated. So a second call with another
--               SCHEDULE only changes the schedule.
--             - A table that refuses ALTER TABLE is retried as ALTER DYNAMIC TABLE.
--             - A table that refuses TRIGGER_ON_CHANGES falls back to
--               'USING CRON 0 6 * * * UTC' (DATA_SPEC §7.2), STATUS = FALLBACK.
--             - Nothing is detached: associations are only added.
-- ============================================================================

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_FORGE.OPS.SP_ATTACH_DMFS(TARGET_DB VARCHAR, SCHEDULE VARCHAR)
RETURNS TABLE (STEP NUMBER, OBJECT_NAME VARCHAR, ACTION VARCHAR, DMF VARCHAR, ARGS VARCHAR, STATUS VARCHAR,
               DETAIL VARCHAR)
LANGUAGE SQL
COMMENT = 'C10: attach the DQ_CHECKS catalogue DMFs to SOURCE and CONFORMED tables, on one schedule. Re-runnable.'
EXECUTE AS CALLER
AS
$$
DECLARE
    ok_args     BOOLEAN;
    fqn         VARCHAR;
    prev_fqn    VARCHAR DEFAULT '';
    kw          VARCHAR DEFAULT 'TABLE';
    other_kw    VARCHAR;
    sched       VARCHAR;
    attempt     INTEGER;
    done        BOOLEAN;
    errs        VARCHAR;
    dmf_fqn     VARCHAR;
    on_args     VARCHAR;
    stmt        VARCHAR;
    add_status  VARCHAR;
    add_detail  VARCHAR;
    step        INTEGER DEFAULT 0;
    out_rows    ARRAY DEFAULT ARRAY_CONSTRUCT();
    out_json    VARCHAR;
    rs          RESULTSET;
    c_checks CURSOR FOR
        SELECT SCHEMA_NAME, TABLE_NAME, DMF, COLUMNS, REF_TABLE, REF_COLUMN
        FROM SUPPLY_CHAIN_FORGE.OPS.DQ_CHECKS
        ORDER BY SCHEMA_NAME, TABLE_NAME, SORT_ORDER, CHECK_ID;
BEGIN
    -- Both arguments end up in DDL text, so only these shapes are accepted.
    SELECT COALESCE(REGEXP_LIKE(:TARGET_DB, '^[A-Za-z_][A-Za-z0-9_$]*$'), FALSE)
       AND COALESCE(REGEXP_LIKE(:SCHEDULE, '^(|TRIGGER_ON_CHANGES|[0-9]+ MINUTE|USING CRON [0-9A-Za-z*/,_ -]+)$'), FALSE)
      INTO :ok_args;
    IF (NOT ok_args) THEN
        rs := (SELECT 0 AS STEP, NULL::VARCHAR AS OBJECT_NAME, 'PARAMETERS' AS ACTION, NULL::VARCHAR AS DMF,
                      NULL::VARCHAR AS ARGS, 'ERROR' AS STATUS,
                      'TARGET_DB must be a plain identifier; SCHEDULE must be empty, TRIGGER_ON_CHANGES, <n> MINUTE or USING CRON <expr> <tz>' AS DETAIL);
        RETURN TABLE(rs);
    END IF;

    FOR r IN c_checks DO
        fqn := TARGET_DB || '.' || r.SCHEMA_NAME || '.' || r.TABLE_NAME;

        -- 1. Once per table: the schedule (all DMFs on a table share it).
        IF (fqn <> prev_fqn) THEN
            prev_fqn := fqn;
            done := FALSE;
            errs := '';
            attempt := 0;
            -- Attempts: TABLE, DYNAMIC TABLE, then, for TRIGGER_ON_CHANGES only, both with the CRON fallback.
            WHILE (NOT done AND attempt < 4) DO
                attempt := attempt + 1;
                IF (attempt = 3 AND SCHEDULE <> 'TRIGGER_ON_CHANGES') THEN
                    BREAK;
                END IF;
                kw := IFF(attempt = 1 OR attempt = 3, 'TABLE', 'DYNAMIC TABLE');
                sched := IFF(attempt <= 2, SCHEDULE, 'USING CRON 0 6 * * * UTC');
                stmt := 'ALTER ' || kw || ' ' || fqn || ' SET DATA_METRIC_SCHEDULE = ''' || sched || '''';
                BEGIN
                    EXECUTE IMMEDIATE :stmt;
                    done := TRUE;
                EXCEPTION
                    WHEN OTHER THEN
                        errs := errs || 'ALTER ' || kw || ' (' || sched || '): ' || SQLERRM || ' | ';
                END;
            END WHILE;
            IF (NOT done) THEN
                kw := 'TABLE';
            END IF;
            step := step + 1;
            out_rows := ARRAY_APPEND(out_rows, OBJECT_CONSTRUCT_KEEP_NULL(
                'STEP', step, 'OBJECT_NAME', fqn, 'ACTION', 'SET SCHEDULE', 'DMF', NULL, 'ARGS', sched,
                'STATUS', IFF(done, IFF(attempt > 2, 'FALLBACK', 'OK'), 'ERROR'),
                'DETAIL', IFF(done, 'ALTER ' || kw || IFF(errs = '', '', ' | refused first: ' || errs), errs)));
        END IF;

        -- 2. The association. A custom DMF (OPS.*) and a reference table live in TARGET_DB.
        dmf_fqn := IFF(STARTSWITH(r.DMF, 'OPS.'), TARGET_DB || '.' || r.DMF, r.DMF);
        on_args := COALESCE(r.COLUMNS, '');
        IF (r.REF_TABLE IS NOT NULL) THEN
            on_args := on_args || ', TABLE(' || TARGET_DB || '.' || r.REF_TABLE || '(' || r.REF_COLUMN || '))';
        END IF;
        stmt := 'ALTER ' || kw || ' ' || fqn || ' ADD DATA METRIC FUNCTION ' || dmf_fqn || ' ON (' || on_args || ')';
        BEGIN
            EXECUTE IMMEDIATE :stmt;
            add_status := 'ADDED';
            add_detail := 'ALTER ' || kw;
        EXCEPTION
            WHEN OTHER THEN
                add_status := IFF(CONTAINS(LOWER(SQLERRM), 'already'), 'EXISTS', 'ERROR');
                add_detail := SQLERRM;
        END;
        -- The other keyword, if this object refused the first one.
        IF (add_status = 'ERROR') THEN
            other_kw := IFF(kw = 'TABLE', 'DYNAMIC TABLE', 'TABLE');
            stmt := 'ALTER ' || other_kw || ' ' || fqn || ' ADD DATA METRIC FUNCTION ' || dmf_fqn || ' ON (' || on_args || ')';
            BEGIN
                EXECUTE IMMEDIATE :stmt;
                add_status := 'ADDED';
                add_detail := 'ALTER ' || other_kw || ' | refused first: ' || add_detail;
            EXCEPTION
                WHEN OTHER THEN
                    add_status := IFF(CONTAINS(LOWER(SQLERRM), 'already'), 'EXISTS', 'ERROR');
                    add_detail := add_detail || ' | ALTER ' || other_kw || ': ' || SQLERRM;
            END;
        END IF;
        step := step + 1;
        out_rows := ARRAY_APPEND(out_rows, OBJECT_CONSTRUCT_KEEP_NULL(
            'STEP', step, 'OBJECT_NAME', fqn, 'ACTION', 'ADD DMF', 'DMF', dmf_fqn, 'ARGS', on_args,
            'STATUS', add_status, 'DETAIL', add_detail));
    END FOR;

    out_json := TO_JSON(out_rows);
    rs := (SELECT f.value:STEP::NUMBER AS STEP, f.value:OBJECT_NAME::VARCHAR AS OBJECT_NAME,
                  f.value:ACTION::VARCHAR AS ACTION, f.value:DMF::VARCHAR AS DMF, f.value:ARGS::VARCHAR AS ARGS,
                  f.value:STATUS::VARCHAR AS STATUS, f.value:DETAIL::VARCHAR AS DETAIL
           FROM TABLE(FLATTEN(INPUT => PARSE_JSON(:out_json))) f
           ORDER BY 1);
    RETURN TABLE(rs);
END;
$$;
