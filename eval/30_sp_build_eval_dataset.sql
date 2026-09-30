-- ============================================================================
-- eval/30_sp_build_eval_dataset.sql — OPS.SP_BUILD_EVAL_DATASET (optional native path)
-- Card:       C11 (.agents/tasks/claude/C11_eval_set.md)
-- Spec:       docs/DATA_SPEC.md §7.3 ("Native Snowflake evaluations")
--             docs/references/agent_evaluations.md §1–4
-- Role:       FORGE_ADMIN        Warehouse: FORGE_WH
-- Run order:  4 of 5 (00 → 10 → 20 → 30 → 99). Re-runnable: CREATE OR REPLACE.
--             Optional: only needed for Snowflake's native agent evaluation (99_run.sql
--             step 5). The deterministic runner (20) doesn't use it.
-- Parameters: ANALYST_TOOL_NAME  the Analyst tool's name in the agent spec (B10), e.g.
--             'supply_chain_analyst'. Native tool-selection accuracy matches tool NAMES,
--             while EVAL_QUESTIONS lists the tool TYPE cortex_analyst_text_to_sql.
-- Returns:    VARIANT {"rows": n, "ground_truth_errors": [question ids]}
-- Expected:   {"rows": 29, "ground_truth_errors": []}, OPS.EVAL_DATASET has 29 rows, each
--             GROUND_TRUTH = {"ground_truth_output": <rubric with {{GT}} filled in>,
--             "ground_truth_invocations": [{"tool_name": ...}]} (reference §1).
-- ============================================================================

CREATE OR REPLACE PROCEDURE SUPPLY_CHAIN_FORGE.OPS.SP_BUILD_EVAL_DATASET(ANALYST_TOOL_NAME VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
COMMENT = 'C11: builds OPS.EVAL_DATASET (INPUT_QUERY, GROUND_TRUTH) for SYSTEM$CREATE_EVALUATION_DATASET.'
EXECUTE AS CALLER
AS
$$
DECLARE
    question    VARCHAR;
    gt_sql      VARCHAR;
    gt_text     VARCHAR;
    rubric      VARCHAR;
    tools_json  VARCHAR;
    gt_variant  VARCHAR;
    n           INTEGER DEFAULT 0;
    errors      ARRAY DEFAULT ARRAY_CONSTRUCT();
    rs          RESULTSET;
BEGIN
    CREATE OR REPLACE TABLE SUPPLY_CHAIN_FORGE.OPS.EVAL_DATASET (
        INPUT_QUERY   VARCHAR,
        GROUND_TRUTH  VARIANT
    ) COMMENT = 'C11: evaluation dataset for Snowflake native agent evaluation (built by SP_BUILD_EVAL_DATASET)';

    rs := (SELECT QUESTION_ID, INPUT_QUERY, GROUND_TRUTH_SQL, RUBRIC,
                  TO_JSON(COALESCE(EXPECTED_TOOLS, ARRAY_CONSTRUCT())) AS TOOLS_JSON
           FROM SUPPLY_CHAIN_FORGE.OPS.EVAL_QUESTIONS
           WHERE ACTIVE
           ORDER BY QUESTION_ID);
    FOR rec IN rs DO
        question := rec.INPUT_QUERY;
        gt_sql := rec.GROUND_TRUTH_SQL;
        rubric := rec.RUBRIC;
        tools_json := rec.TOOLS_JSON;
        gt_text := '';
        IF (gt_sql IS NOT NULL) THEN
            BEGIN
                EXECUTE IMMEDIATE :gt_sql;
                SELECT TO_JSON(COALESCE(ARRAY_AGG(o.ROW_OBJ), ARRAY_CONSTRUCT()))
                  INTO :gt_text
                  FROM (SELECT OBJECT_CONSTRUCT_KEEP_NULL(*) AS ROW_OBJ
                          FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) LIMIT 50) o;
            EXCEPTION
                WHEN OTHER THEN
                    gt_text := '(ground truth unavailable)';
                    errors := ARRAY_APPEND(errors, rec.QUESTION_ID);
            END;
        END IF;
        -- PARSE_JSON (not OBJECT_CONSTRUCT) guarantees a VARIANT (reference §1). Assignment form:
        -- SELECT … INTO fails on a scalar subquery without FROM (C08_run.md, fix 2).
        gt_variant := (SELECT TO_JSON(OBJECT_CONSTRUCT(
                   'ground_truth_output', REPLACE(:rubric, '{{GT}}', :gt_text),
                   'ground_truth_invocations',
                   (SELECT COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT('tool_name',
                               IFF(t.value::VARCHAR = 'cortex_analyst_text_to_sql', :ANALYST_TOOL_NAME, t.value::VARCHAR)))
                                    WITHIN GROUP (ORDER BY t.index), ARRAY_CONSTRUCT())
                      FROM TABLE(FLATTEN(INPUT => PARSE_JSON(:tools_json))) t))));
        INSERT INTO SUPPLY_CHAIN_FORGE.OPS.EVAL_DATASET (INPUT_QUERY, GROUND_TRUTH)
            SELECT :question, PARSE_JSON(:gt_variant);
        n := n + 1;
    END FOR;
    RETURN OBJECT_CONSTRUCT('rows', n, 'ground_truth_errors', errors);
END;
$$;
