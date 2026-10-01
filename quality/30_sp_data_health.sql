-- ============================================================================
-- quality/30_sp_data_health.sql — SEMANTIC.SP_DATA_HEALTH: the agent's data-health tool
-- Card:       C10 (.agents/tasks/claude/C10_data_quality.md)
-- Spec:       docs/DATA_SPEC.md §7.2 (signature, JSON shape, status rules), §5.2 (as-of date)
-- Role:       FORGE_ADMIN (the owner, owner's rights)        Warehouse: FORGE_WH
-- Run order:  4 of 6 (00 → 10 → 20 → 30 → 40 → 99), after 00 (its grants to FORGE_ADMIN).
--             Re-runnable: CREATE OR REPLACE, then the USAGE grants again.
-- Parameters: ENTITY  suppliers, parts, sourcing, plants, inventory, customers, orders,
--                     order_lines, shipments, or ALL (case-insensitive).
-- Returns:    VARIANT, exactly the §7.2 shape, every key always present (null if unknown):
--             {entity, generated_at, as_of_date, status, summary, entities: [{entity, table,
--             row_count, latest_business_date, latest_load_ts, freshness_hours,
--             freshness_status, status, checks: [{check, code, layer, dmf, table, columns,
--             value, rate, threshold_rate, status, handled_by, measured_at}]}]}
-- Expected:   CALL SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH('shipments') → one entity with 11
--             checks, ('ALL') → 9 entities, ≤ 16 KB, as_of_date = the shipments' latest
--             ship_date, ('nope') → status "ERROR", entities []. Same answer for every role.
--
-- What it reads (and nothing else):
--   - SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS: the latest result per association,
--     matched to the OPS.DQ_CHECKS catalogue (needs the DATA_QUALITY_MONITORING_VIEWER
--     application role, granted in 00)
--   - OPS.V_CONFORMED_FACTS: COUNT(*), MAX(load_ts), MAX(business date) per CONFORMED
--     table (metadata-answered, so the cost doesn't grow with the data)
--   Counts and rates only: no row values, no masked column, no source table.
-- Status rules (§7.2, made explicit per catalogue row):
--   check     UNKNOWN until its DMF has a result, INFO rows (raw-data defects) OK, ZERO rows
--             FAIL unless 0, MAX_RATE rows WARN above THRESHOLD_RATE (value ÷ ROW_COUNT of
--             the same table, both DMF results)
--   freshness daily entities (orders, order_lines, shipments, inventory): OK ≤ 36 h since
--             MAX(load_ts) (UTC), WARN ≤ 72 h, FAIL beyond. Reference entities (suppliers,
--             parts, sourcing, plants, customers) change rarely by nature: REFERENCE, never
--             judged on age and not counted in the status (C16, "freshness fix 1", §7.2).
--             UNKNOWN if the CONFORMED table can't be read.
--   entity    the worst of its checks and its freshness, top level the worst entity.
--             Order: OK < UNKNOWN < WARN < FAIL.
-- Size guard: if the answer exceeds 16,000 bytes (ALL, ~46 checks), it lists only the checks
--             that aren't OK, then none, and says so in the summary. The shape doesn't change.
--
-- Agent tool (B10, DATA_SPEC §7.2 and docs/references/agent_custom_tools.md §4):
--   - tool_spec:
--       type: generic
--       name: data_health
--       description: >
--         Freshness and data-quality status of one supply chain entity (or ALL): when it was
--         last loaded, the as-of date, and which data-quality checks pass. Call it when the user
--         asks whether data is up to date or trustworthy, or before answering if a result looks
--         incomplete. Returns counts and rates only, never row values.
--       input_schema:
--         type: object
--         properties:
--           entity:
--             type: string
--             description: "suppliers, parts, sourcing, plants, inventory, customers, orders, order_lines, shipments, or ALL"
--         required: [entity]
--   tool_resources:
--     data_health:
--       type: procedure
--       identifier: SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH(VARCHAR)
--       execution_environment: {type: warehouse, warehouse: FORGE_WH}
-- ============================================================================

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH(ENTITY VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
COMMENT = 'C10: freshness, as-of date and data-quality status of one entity or ALL (DATA_SPEC §7.2). Counts and rates only.'
EXECUTE AS OWNER
AS
$$
DECLARE
    ent         VARCHAR;
    ent_out     VARCHAR;
    now_utc     TIMESTAMP_NTZ;
    generated   VARCHAR;
    facts_json  VARCHAR DEFAULT '[]';
    dq_json     VARCHAR DEFAULT '[]';
    notes       VARCHAR DEFAULT '';
    top_status  VARCHAR;
    as_of       VARCHAR;
    summary_text VARCHAR;
    ent_full    VARCHAR;
    ent_slim    VARCHAR;
    ent_bare    VARCHAR;
    answer      VARIANT;
    rs          RESULTSET;
BEGIN
    ent := LOWER(TRIM(COALESCE(ENTITY, '')));
    now_utc := SYSDATE();
    generated := TO_CHAR(now_utc, 'YYYY-MM-DD"T"HH24:MI:SS"Z"');

    IF (NOT ARRAY_CONTAINS(TO_VARIANT(ent), ARRAY_CONSTRUCT('all', 'suppliers', 'parts', 'sourcing', 'plants', 'inventory',
                                                           'customers', 'orders', 'order_lines', 'shipments'))) THEN
        RETURN OBJECT_CONSTRUCT_KEEP_NULL(
            'entity', LEFT(ENTITY, 64), 'generated_at', generated, 'as_of_date', NULL, 'status', 'ERROR',
            'summary', 'Unknown entity. Use one of: suppliers, parts, sourcing, plants, inventory, customers, orders, order_lines, shipments, or ALL.',
            'entities', ARRAY_CONSTRUCT());
    END IF;
    ent_out := IFF(ent = 'all', 'ALL', ent);

    -- Facts per CONFORMED table (aggregates only). Missing before B08c: freshness UNKNOWN.
    BEGIN
        SELECT TO_JSON(ARRAY_AGG(OBJECT_CONSTRUCT_KEEP_NULL(
                   'entity', f.ENTITY, 'row_count', f.ROW_COUNT,
                   'latest_load_ts', TO_CHAR(f.LATEST_LOAD_TS, 'YYYY-MM-DD"T"HH24:MI:SS'),
                   'latest_business_date', TO_CHAR(f.LATEST_BUSINESS_DATE, 'YYYY-MM-DD'))))
          INTO :facts_json
          FROM SUPPLY_CHAIN_FORGE.OPS.V_CONFORMED_FACTS f;
    EXCEPTION
        WHEN OTHER THEN
            facts_json := '[]';
            notes := notes || ' The cleaned tables could not be read.';
    END;

    -- The latest result of every DMF association in this database. Missing before B12: checks UNKNOWN.
    BEGIN
        SELECT TO_JSON(ARRAY_AGG(OBJECT_CONSTRUCT_KEEP_NULL(
                   's', r.table_schema, 't', r.table_name, 'ms', r.metric_schema, 'm', r.metric_name,
                   'a', UPPER(TO_JSON(r.argument_names)), 'v', r.value,
                   'at', TO_CHAR(CONVERT_TIMEZONE('UTC', r.measurement_time), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))))
          INTO :dq_json
          FROM (SELECT table_schema, table_name, metric_schema, metric_name, argument_names, value, measurement_time
                FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
                WHERE table_database = 'SUPPLY_CHAIN_FORGE'
                  AND table_schema IN ('ERP_SOURCE', 'WMS_SOURCE', 'TMS_SOURCE', 'SRM_SOURCE', 'CONFORMED')
                QUALIFY ROW_NUMBER() OVER (PARTITION BY table_schema, table_name, metric_schema, metric_name,
                                                        TO_JSON(argument_names)
                                           ORDER BY measurement_time DESC) = 1) r;
    EXCEPTION
        WHEN OTHER THEN
            dq_json := '[]';
            notes := notes || ' Data-quality results could not be read.';
    END;

    BEGIN
        rs := (
            WITH wanted AS (
                SELECT w.column1 AS ENTITY, w.column2 AS CONFORMED_TABLE, w.column3 AS LABEL, w.column4 AS ORD,
                       w.column5 AS KIND
                FROM (VALUES ('suppliers', 'SUPPLIER', 'Suppliers', 1, 'REFERENCE'),
                             ('parts', 'PART', 'Parts', 2, 'REFERENCE'),
                             ('sourcing', 'SOURCING', 'Sourcing rows', 3, 'REFERENCE'),
                             ('plants', 'PLANT', 'Plants', 4, 'REFERENCE'),
                             ('inventory', 'INVENTORY', 'Inventory snapshots', 5, 'DAILY'),
                             ('customers', 'CUSTOMER', 'Customers', 6, 'REFERENCE'),
                             ('orders', 'SALES_ORDER', 'Orders', 7, 'DAILY'),
                             ('order_lines', 'ORDER_LINE', 'Order lines', 8, 'DAILY'),
                             ('shipments', 'SHIPMENT', 'Shipments', 9, 'DAILY')) AS w
                WHERE :ent = 'all' OR w.column1 = :ent
            ),
            facts AS (
                SELECT f.value:entity::VARCHAR AS ENTITY, f.value:row_count::NUMBER AS ROW_COUNT,
                       TRY_TO_TIMESTAMP_NTZ(f.value:latest_load_ts::VARCHAR) AS LATEST_LOAD_TS,
                       TRY_TO_DATE(f.value:latest_business_date::VARCHAR) AS LATEST_BUSINESS_DATE
                FROM TABLE(FLATTEN(INPUT => PARSE_JSON(COALESCE(:facts_json, '[]')))) f
            ),
            dq AS (
                SELECT d.value:s::VARCHAR AS TABLE_SCHEMA, d.value:t::VARCHAR AS TABLE_NAME,
                       d.value:ms::VARCHAR AS METRIC_SCHEMA, d.value:m::VARCHAR AS METRIC_NAME,
                       d.value:a::VARCHAR AS ARGS, d.value:v::FLOAT AS VALUE, d.value:at::VARCHAR AS MEASURED_AT
                FROM TABLE(FLATTEN(INPUT => PARSE_JSON(COALESCE(:dq_json, '[]')))) d
            ),
            chk AS (
                -- Matched on table, DMF and the first column argument (argument_names holds the
                -- column names, the match works whether they're plain strings or objects).
                SELECT c.ENTITY, c.SORT_ORDER, c.CHECK_NAME, c.CODE, c.LAYER, c.SCHEMA_NAME, c.TABLE_NAME, c.DMF,
                       c.COLUMNS, c.EXPECT, c.THRESHOLD_RATE, c.HANDLED_BY,
                       r.VALUE, r.MEASURED_AT, rc.VALUE AS DENOM
                FROM SUPPLY_CHAIN_FORGE.OPS.DQ_CHECKS c
                JOIN wanted w ON w.ENTITY = c.ENTITY
                LEFT JOIN dq r
                  ON r.TABLE_SCHEMA = c.SCHEMA_NAME AND r.TABLE_NAME = c.TABLE_NAME
                 AND r.METRIC_SCHEMA = SPLIT_PART(c.DMF, '.', -2) AND r.METRIC_NAME = SPLIT_PART(c.DMF, '.', -1)
                 AND CONTAINS(r.ARGS, '"' || UPPER(TRIM(SPLIT_PART(c.COLUMNS, ',', 1))) || '"')
                LEFT JOIN dq rc
                  ON rc.TABLE_SCHEMA = c.SCHEMA_NAME AND rc.TABLE_NAME = c.TABLE_NAME
                 AND rc.METRIC_SCHEMA = 'CORE' AND rc.METRIC_NAME = 'ROW_COUNT'
                WHERE c.EXPECT IN ('ZERO', 'MAX_RATE', 'INFO')
            ),
            scored AS (
                SELECT chk.*,
                       VALUE / NULLIFZERO(DENOM) AS RATE,
                       CASE WHEN VALUE IS NULL THEN 'UNKNOWN'
                            WHEN EXPECT = 'INFO' THEN 'OK'
                            WHEN EXPECT = 'ZERO' THEN IFF(VALUE = 0, 'OK', 'FAIL')
                            WHEN VALUE = 0 THEN 'OK'
                            WHEN DENOM IS NULL OR DENOM = 0 THEN 'UNKNOWN'
                            WHEN VALUE / DENOM <= THRESHOLD_RATE THEN 'OK'
                            ELSE 'WARN' END AS STATUS
                FROM chk
            ),
            objs AS (
                SELECT ENTITY, SORT_ORDER, STATUS, CODE, EXPECT, VALUE,
                       DECODE(STATUS, 'OK', 0, 'UNKNOWN', 1, 'WARN', 2, 3) AS SEV,
                       OBJECT_CONSTRUCT_KEEP_NULL(
                           'check', CHECK_NAME, 'code', CODE, 'layer', LAYER,
                           'dmf', IFF(STARTSWITH(DMF, 'OPS.'), 'SUPPLY_CHAIN_FORGE.' || DMF, DMF),
                           'table', 'SUPPLY_CHAIN_FORGE.' || SCHEMA_NAME || '.' || TABLE_NAME,
                           'columns', SPLIT(REPLACE(COLUMNS, ' ', ''), ','),
                           'value', VALUE::NUMBER(38, 0),
                           'rate', ROUND(RATE, 6),
                           'threshold_rate', THRESHOLD_RATE,
                           'status', STATUS,
                           'handled_by', HANDLED_BY,
                           'measured_at', MEASURED_AT) AS OBJ
                FROM scored
            ),
            ent_checks AS (
                SELECT ENTITY,
                       ARRAY_AGG(OBJ) WITHIN GROUP (ORDER BY SORT_ORDER) AS CHECKS,
                       ARRAY_AGG(IFF(STATUS = 'OK', NULL, OBJ)) WITHIN GROUP (ORDER BY SORT_ORDER) AS CHECKS_NOT_OK,
                       MAX(SEV) AS CHECK_SEV,
                       COUNT(DISTINCT IFF(CODE LIKE 'E%' AND VALUE > 0, CODE, NULL)) AS EDGE_CASES,
                       COUNT_IF(EXPECT = 'ZERO' AND STATUS = 'FAIL') AS REPAIRS_LEFT,
                       COUNT_IF(STATUS = 'WARN') AS WARNS,
                       COUNT_IF(STATUS = 'UNKNOWN') AS UNKNOWNS
                FROM objs
                GROUP BY ENTITY
            ),
            ents AS (
                SELECT w.ENTITY, w.ORD, w.LABEL, w.CONFORMED_TABLE, w.KIND,
                       f.ROW_COUNT, f.LATEST_LOAD_TS, f.LATEST_BUSINESS_DATE,
                       DATEDIFF(second, f.LATEST_LOAD_TS, :now_utc) / 3600 AS AGE_H,
                       CASE WHEN f.LATEST_LOAD_TS IS NULL THEN 'UNKNOWN'
                            WHEN w.KIND = 'REFERENCE' THEN 'REFERENCE'
                            WHEN DATEDIFF(second, f.LATEST_LOAD_TS, :now_utc) <= 36 * 3600 THEN 'OK'
                            WHEN DATEDIFF(second, f.LATEST_LOAD_TS, :now_utc) <= 72 * 3600 THEN 'WARN'
                            ELSE 'FAIL' END AS FRESH_STATUS,
                       COALESCE(c.CHECKS, ARRAY_CONSTRUCT()) AS CHECKS,
                       COALESCE(c.CHECKS_NOT_OK, ARRAY_CONSTRUCT()) AS CHECKS_NOT_OK,
                       -- no configured checks is not a clean bill of health (review #11): UNKNOWN
                       IFF(c.ENTITY IS NULL, 1, c.CHECK_SEV) AS CHECK_SEV,
                       COALESCE(c.EDGE_CASES, 0) AS EDGE_CASES,
                       COALESCE(c.REPAIRS_LEFT, 0) AS REPAIRS_LEFT,
                       COALESCE(c.WARNS, 0) AS WARNS,
                       COALESCE(c.UNKNOWNS, 0) AS UNKNOWNS
                FROM wanted w
                LEFT JOIN facts f ON f.ENTITY = w.ENTITY
                LEFT JOIN ent_checks c ON c.ENTITY = w.ENTITY
            ),
            judged AS (
                SELECT e.*,
                       GREATEST(CHECK_SEV, DECODE(FRESH_STATUS, 'OK', 0, 'REFERENCE', 0, 'UNKNOWN', 1, 'WARN', 2, 3)) AS SEV
                FROM ents e
            ),
            final_ents AS (
                SELECT j.*,
                       DECODE(SEV, 0, 'OK', 1, 'UNKNOWN', 2, 'WARN', 'FAIL') AS STATUS,
                       LABEL
                       || CASE FRESH_STATUS
                              WHEN 'UNKNOWN' THEN ': the cleaned table is not available yet'
                              WHEN 'REFERENCE' THEN ' are reference data, which changes rarely, so not judged on age (last loaded '
                                   || IFF(AGE_H >= 48, ROUND(AGE_H / 24)::VARCHAR || ' days', ROUND(GREATEST(AGE_H, 0))::VARCHAR || ' h')
                                   || ' ago)'
                              WHEN 'OK' THEN ' are fresh (loaded ' || ROUND(GREATEST(AGE_H, 0))::VARCHAR || ' h ago)'
                              ELSE ' are ' || IFF(FRESH_STATUS = 'WARN', 'getting stale', 'stale') || ' (last loaded '
                                   || IFF(AGE_H >= 48, ROUND(AGE_H / 24, 1)::VARCHAR || ' days', ROUND(AGE_H)::VARCHAR || ' h')
                                   || ' ago)' END
                       || '. '
                       || CASE EDGE_CASES WHEN 0 THEN 'No edge cases found' WHEN 1 THEN '1 edge case handled'
                                          ELSE EDGE_CASES::VARCHAR || ' edge cases handled' END
                       || '; '
                       || CASE WHEN REPAIRS_LEFT > 0
                                    THEN REPAIRS_LEFT::VARCHAR || ' repairable defect check' || IFF(REPAIRS_LEFT = 1, '', 's')
                                         || ' failing in the cleaned data'
                               WHEN UNKNOWNS > 0
                                    THEN UNKNOWNS::VARCHAR || ' check' || IFF(UNKNOWNS = 1, '', 's') || ' not measured yet'
                               ELSE 'no repairable defects left' END
                       || IFF(WARNS > 0, '; ' || WARNS::VARCHAR || ' above the expected rate', '')
                       || '.' AS SENTENCE,
                       OBJECT_CONSTRUCT_KEEP_NULL(
                           'entity', ENTITY,
                           'table', 'SUPPLY_CHAIN_FORGE.CONFORMED.' || CONFORMED_TABLE,
                           'row_count', ROW_COUNT,
                           'latest_business_date', TO_CHAR(LATEST_BUSINESS_DATE, 'YYYY-MM-DD'),
                           'latest_load_ts', TO_CHAR(LATEST_LOAD_TS, 'YYYY-MM-DD"T"HH24:MI:SS'),
                           'freshness_hours', ROUND(AGE_H, 1),
                           'freshness_status', FRESH_STATUS,
                           'status', DECODE(SEV, 0, 'OK', 1, 'UNKNOWN', 2, 'WARN', 'FAIL')) AS BASE
                FROM judged j
            )
            SELECT DECODE(MAX(SEV), 0, 'OK', 1, 'UNKNOWN', 2, 'WARN', 'FAIL') AS TOP_STATUS,
                   TO_CHAR(MAX(IFF(:ent = 'all', IFF(ENTITY = 'shipments', LATEST_BUSINESS_DATE, NULL), LATEST_BUSINESS_DATE)),
                           'YYYY-MM-DD') AS AS_OF,
                   IFF(:ent = 'all',
                       'Data is as of '
                       || COALESCE(TO_CHAR(MAX(IFF(ENTITY = 'shipments', LATEST_BUSINESS_DATE, NULL)), 'YYYY-MM-DD'), 'an unknown date')
                       || '. ' || COUNT_IF(STATUS = 'OK')::VARCHAR || ' of ' || COUNT(*)::VARCHAR || ' entities OK'
                       || COALESCE('; ' || NULLIF(LISTAGG(IFF(STATUS = 'OK', NULL, ENTITY || ' ' || STATUS), ', ')
                                                  WITHIN GROUP (ORDER BY ORD), ''), '')
                       || '.'
                       || IFF(COUNT_IF(FRESH_STATUS = 'REFERENCE') > 0,
                              ' ' || COUNT_IF(FRESH_STATUS = 'REFERENCE')::VARCHAR
                              || ' reference tables change rarely and are not judged on age.', ''),
                       MAX(SENTENCE)) AS SUMMARY,
                   TO_JSON(ARRAY_AGG(OBJECT_INSERT(BASE, 'checks', CHECKS)) WITHIN GROUP (ORDER BY ORD)) AS ENT_FULL,
                   TO_JSON(ARRAY_AGG(OBJECT_INSERT(BASE, 'checks', CHECKS_NOT_OK)) WITHIN GROUP (ORDER BY ORD)) AS ENT_SLIM,
                   TO_JSON(ARRAY_AGG(OBJECT_INSERT(BASE, 'checks', ARRAY_CONSTRUCT())) WITHIN GROUP (ORDER BY ORD)) AS ENT_BARE
            FROM final_ents
        );
        FOR rec IN rs DO
            top_status := rec.TOP_STATUS;
            as_of := rec.AS_OF;
            summary_text := rec.SUMMARY;
            ent_full := rec.ENT_FULL;
            ent_slim := rec.ENT_SLIM;
            ent_bare := rec.ENT_BARE;
        END FOR;
    EXCEPTION
        WHEN OTHER THEN
            RETURN OBJECT_CONSTRUCT_KEEP_NULL(
                'entity', ent_out, 'generated_at', generated, 'as_of_date', NULL, 'status', 'ERROR',
                'summary', 'Data health could not be computed: ' || SQLERRM, 'entities', ARRAY_CONSTRUCT());
    END;

    answer := OBJECT_CONSTRUCT_KEEP_NULL(
        'entity', ent_out, 'generated_at', generated, 'as_of_date', as_of, 'status', top_status,
        'summary', summary_text || notes, 'entities', PARSE_JSON(ent_full));
    IF (LENGTH(TO_JSON(answer)) > 16000) THEN
        answer := OBJECT_CONSTRUCT_KEEP_NULL(
            'entity', ent_out, 'generated_at', generated, 'as_of_date', as_of, 'status', top_status,
            'summary', summary_text || notes || ' Only the checks that are not OK are listed; ask for one entity to see all of its checks.',
            'entities', PARSE_JSON(ent_slim));
    END IF;
    IF (LENGTH(TO_JSON(answer)) > 16000) THEN
        answer := OBJECT_CONSTRUCT_KEEP_NULL(
            'entity', ent_out, 'generated_at', generated, 'as_of_date', as_of, 'status', top_status,
            'summary', summary_text || notes || ' Checks are left out to keep this answer short; ask for one entity to see its checks.',
            'entities', PARSE_JSON(ent_bare));
    END IF;
    RETURN answer;
END;
$$;

-- The agent runs the tool as the calling user's role, the app calls it as FORGE_ADMIN (owner).
GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH(VARCHAR) TO ROLE PLANNER_ROLE;
GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH(VARCHAR) TO ROLE BUYER_ROLE;
GRANT USAGE ON PROCEDURE SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH(VARCHAR) TO ROLE LOGISTICS_ROLE;
