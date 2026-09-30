-- ============================================================================
-- tests/scale/20_sp_scale_run.sql — OPS.SP_SCALE_RUN: run every catalogued query, measure it
-- Card:       C12 (.agents/tasks/claude/C12_scale_harness.md)
-- Spec:       docs/DATA_SPEC.md §7.4, docs/references/snowflake_execution_notes.md §7
-- Role:       FORGE_ADMIN        Warehouse: the one set on the session (XS or B13's larger one)
-- Run order:  3 of 4 (00 → 10 → 20 → 99). Re-runnable: CREATE OR REPLACE.
-- Parameters: TARGET_DB      the database to query: SUPPLY_CHAIN_FORGE or B13's clone
--             RUN_LABEL      e.g. 'sf1-xs', 'clone-xs', 'clone-large' (letters, digits, _ . : -)
--             RESULTS_TABLE  a 3-part name. Pass 'SUPPLY_CHAIN_FORGE.OPS.SCALE_RESULTS' so
--                            results survive dropping the clone. Created if missing.
--             QUERY_FILTER   optional (default NULL = all active queries): a LIKE pattern on
--                            QUERY_NAME, to split a slow run into batches under 15 minutes
-- Returns:    VARIANT {"run_label", "queries", "failed", "total_elapsed_ms", "max_elapsed_ms"}
-- Expected:   "failed": 0 once B09/B13 are in place ("failed" 1 for NAIVE_OTD until B15
--             grants FORGE_ADMIN SELECT on VTTK and VBAK). One RESULTS_TABLE row per query.
--
-- Per query (DATA_SPEC §7.4): {{DB}} → TARGET_DB, EXECUTE IMMEDIATE, then
--   - timings, bytes, rows, warehouse size: QUERY_HISTORY_BY_SESSION for that query ID
--   - pruning: GET_QUERY_OPERATOR_STATS, partitions scanned and total over TableScan operators
--   - RESULT_HASH: HASH_AGG(<HASH_EXPR>) over RESULT_SCAN (numbers rounded to 6 dp)
--   - SQL_HASH: HASH(SQL_TEMPLATE), the same text at every scale, whatever TARGET_DB is
-- The result cache is off and QUERY_TAG = 'forge_scale:<RUN_LABEL>' for the whole run.
-- A failing query is a row with ERROR set, and the run goes on.
-- ============================================================================

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_FORGE.OPS.SP_SCALE_RUN(
    TARGET_DB VARCHAR, RUN_LABEL VARCHAR, RESULTS_TABLE VARCHAR, QUERY_FILTER VARCHAR DEFAULT NULL)
RETURNS VARIANT
LANGUAGE SQL
COMMENT = 'C12: runs the SCALE_QUERIES catalogue against TARGET_DB and records timing, pruning and fingerprints.'
EXECUTE AS CALLER
AS
$$
DECLARE
    ok_args     BOOLEAN;
    run_ts      TIMESTAMP_NTZ;
    wh          VARCHAR;
    q_name      VARCHAR;
    q_path      VARCHAR;
    q_metric    VARCHAR;
    q_dim       VARCHAR;
    q_window    VARCHAR;
    q_template  VARCHAR;
    q_hash_expr VARCHAR;
    q_sql       VARCHAR;
    hash_sql    VARCHAR;
    qid         VARCHAR;
    err         VARCHAR;
    elapsed     NUMBER;
    comp        NUMBER;
    exe         NUMBER;
    bytes       NUMBER;
    rows_out    NUMBER;
    wh_size     VARCHAR;
    p_scanned   NUMBER;
    p_total     NUMBER;
    r_hash      NUMBER;
    s_hash      NUMBER;
    summary     VARIANT;
    rs          RESULTSET;
BEGIN
    -- All three end up in SQL text, so only these shapes are accepted.
    ok_args := (SELECT COALESCE(REGEXP_LIKE(:TARGET_DB, '^[A-Za-z_][A-Za-z0-9_$]*$'), FALSE)
                   AND COALESCE(REGEXP_LIKE(:RUN_LABEL, '^[A-Za-z0-9_.:-]{1,64}$'), FALSE)
                   AND COALESCE(REGEXP_LIKE(:RESULTS_TABLE,
                           '^[A-Za-z_][A-Za-z0-9_$]*[.][A-Za-z_][A-Za-z0-9_$]*[.][A-Za-z_][A-Za-z0-9_$]*$'), FALSE));
    IF (NOT ok_args) THEN
        RETURN OBJECT_CONSTRUCT('status', 'ERROR', 'message',
            'TARGET_DB must be a plain identifier, RUN_LABEL 1-64 of [A-Za-z0-9_.:-], RESULTS_TABLE db.schema.table');
    END IF;

    EXECUTE IMMEDIATE 'ALTER SESSION SET USE_CACHED_RESULT = FALSE';
    EXECUTE IMMEDIATE 'ALTER SESSION SET QUERY_TAG = ''forge_scale:' || RUN_LABEL || '''';
    run_ts := SYSDATE();
    wh := CURRENT_WAREHOUSE();

    CREATE TABLE IF NOT EXISTS IDENTIFIER(:RESULTS_TABLE) (
        RUN_LABEL           VARCHAR,
        RUN_TS              TIMESTAMP_NTZ,
        TARGET_DB           VARCHAR,
        WAREHOUSE_NAME      VARCHAR,
        WAREHOUSE_SIZE      VARCHAR,
        QUERY_NAME          VARCHAR,
        PATH                VARCHAR,
        METRIC              VARCHAR,
        DIMENSION           VARCHAR,
        TIME_WINDOW         VARCHAR,
        QUERY_ID            VARCHAR,
        ELAPSED_MS          NUMBER,
        COMPILATION_MS      NUMBER,
        EXECUTION_MS        NUMBER,
        BYTES_SCANNED       NUMBER,
        PARTITIONS_SCANNED  NUMBER,
        PARTITIONS_TOTAL    NUMBER,
        ROWS_PRODUCED       NUMBER,
        RESULT_HASH         NUMBER,
        SQL_HASH            NUMBER,
        ERROR               VARCHAR
    ) COMMENT = 'C12: one row per query per scale run (DATA_SPEC §7.4). Art 12 is read from here.';

    rs := (SELECT QUERY_NAME, PATH, METRIC, DIMENSION, TIME_WINDOW, SQL_TEMPLATE, HASH_EXPR
           FROM SUPPLY_CHAIN_FORGE.OPS.SCALE_QUERIES
           WHERE ACTIVE AND (:QUERY_FILTER IS NULL OR QUERY_NAME LIKE :QUERY_FILTER)
           ORDER BY SORT_ORDER);

    FOR rec IN rs DO
        q_name := rec.QUERY_NAME;
        q_path := rec.PATH;
        q_metric := rec.METRIC;
        q_dim := rec.DIMENSION;
        q_window := rec.TIME_WINDOW;
        q_template := rec.SQL_TEMPLATE;
        q_hash_expr := rec.HASH_EXPR;
        q_sql := REPLACE(q_template, '{{DB}}', TARGET_DB);
        s_hash := (SELECT HASH(:q_template));
        qid := NULL;
        err := NULL;
        elapsed := NULL;
        comp := NULL;
        exe := NULL;
        bytes := NULL;
        rows_out := NULL;
        wh_size := NULL;
        p_scanned := NULL;
        p_total := NULL;
        r_hash := NULL;

        BEGIN
            EXECUTE IMMEDIATE :q_sql;
            qid := LAST_QUERY_ID();
            IF (q_hash_expr IS NOT NULL) THEN
                hash_sql := 'SELECT HASH_AGG(' || q_hash_expr || ') FROM TABLE(RESULT_SCAN(''' || qid || '''))';
                EXECUTE IMMEDIATE :hash_sql;
                r_hash := (SELECT $1 FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
            END IF;
            -- MAX() makes these one-row selects, even when history has no row yet.
            SELECT MAX(TOTAL_ELAPSED_TIME), MAX(COMPILATION_TIME), MAX(EXECUTION_TIME), MAX(BYTES_SCANNED),
                   MAX(ROWS_PRODUCED), MAX(WAREHOUSE_SIZE)
              INTO :elapsed, :comp, :exe, :bytes, :rows_out, :wh_size
              FROM TABLE(SUPPLY_CHAIN_FORGE.INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT => 10000))
             WHERE QUERY_ID = :qid;
            SELECT SUM(operator_statistics:pruning:partitions_scanned::NUMBER),
                   SUM(operator_statistics:pruning:partitions_total::NUMBER)
              INTO :p_scanned, :p_total
              FROM TABLE(GET_QUERY_OPERATOR_STATS(:qid))
             WHERE operator_type = 'TableScan';
        EXCEPTION
            WHEN OTHER THEN
                err := SQLERRM;
        END;

        INSERT INTO IDENTIFIER(:RESULTS_TABLE)
            (RUN_LABEL, RUN_TS, TARGET_DB, WAREHOUSE_NAME, WAREHOUSE_SIZE, QUERY_NAME, PATH, METRIC, DIMENSION,
             TIME_WINDOW, QUERY_ID, ELAPSED_MS, COMPILATION_MS, EXECUTION_MS, BYTES_SCANNED, PARTITIONS_SCANNED,
             PARTITIONS_TOTAL, ROWS_PRODUCED, RESULT_HASH, SQL_HASH, ERROR)
        SELECT :RUN_LABEL, :run_ts, :TARGET_DB, :wh, :wh_size, :q_name, :q_path, :q_metric, :q_dim,
               :q_window, :qid, :elapsed, :comp, :exe, :bytes, :p_scanned,
               :p_total, :rows_out, :r_hash, :s_hash, :err;
    END FOR;

    EXECUTE IMMEDIATE 'ALTER SESSION UNSET QUERY_TAG';
    summary := (SELECT OBJECT_CONSTRUCT(
                           'run_label', :RUN_LABEL,
                           'queries', COUNT(*),
                           'failed', COUNT_IF(ERROR IS NOT NULL),
                           'total_elapsed_ms', SUM(ELAPSED_MS),
                           'max_elapsed_ms', MAX(ELAPSED_MS))
                FROM IDENTIFIER(:RESULTS_TABLE)
                WHERE RUN_LABEL = :RUN_LABEL AND RUN_TS = :run_ts);
    RETURN summary;
END;
$$;
