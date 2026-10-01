-- ============================================================================
-- eval/99_run.sql — the calls CoCo runs at B10 (one statement per call)
-- Card:       C11 (.agents/tasks/claude/C11_eval_set.md)
-- Role:       FORGE_ADMIN for every step (00_setup.sql runs first, as ACCOUNTADMIN)
-- Warehouse:  FORGE_WH
-- Run order:  5 of 5, after 00_setup.sql (ACCOUNTADMIN), 10_questions.sql, 20_sp_run_eval.sql
--             and 30_sp_build_eval_dataset.sql (all FORGE_ADMIN), and after B10 has
--             created SEMANTIC.SUPPLY_CHAIN_AGENT on the B08c data and the B09 view.
-- Parameters: RUN_LABEL 'b10-baseline' (use a new label for each later run, e.g. after an
--             agent or view change: 'b10-v2', 'b15-final').
-- Expected:   see each step. Gate: all 30 questions have a result under the label, and
--             art 08 records the pass rate by category and the latencies.
-- Cost:       30 agent calls plus about 50 small queries on FORGE_WH (≈ 10–15 minutes
--             in all, in four batches that each stay under the 15-minute call budget).
-- ============================================================================

-- ── Step 1. Check the questions are ready (lookup IDs filled in) ─────────────────
-- Expected: 30 active questions, 0 still containing {{ORDER_ID}}.
SELECT COUNT(*) AS QUESTIONS, COUNT_IF(INPUT_QUERY LIKE '%{{%') AS UNFILLED
FROM SUPPLY_CHAIN_FORGE.OPS.EVAL_QUESTIONS WHERE ACTIVE;

-- ── Step 2. Ask the agent, in four batches ──────────────────────────────────────
-- Expected per call: a VARIANT summary {"run_label", "questions", "passed", "pass_rate",
-- "by_category", "latency_ms"}, cumulative for the label (9, 19, 29, then 30 questions).
CALL SUPPLY_CHAIN_FORGE.OPS.SP_RUN_EVAL('b10-baseline', 'Q0%');
CALL SUPPLY_CHAIN_FORGE.OPS.SP_RUN_EVAL('b10-baseline', 'Q1%');
CALL SUPPLY_CHAIN_FORGE.OPS.SP_RUN_EVAL('b10-baseline', 'Q2%');
CALL SUPPLY_CHAIN_FORGE.OPS.SP_RUN_EVAL('b10-baseline', 'Q3%');

-- ── Step 3. Art 08: every question, its answer, SQL, pass/fail and latency ───────
-- Expected: 30 rows. Paste into docs/artifacts/08_agent_answers.md with the step 2 summary.
SELECT QUESTION_ID, CATEGORY, EXPECTED_BEHAVIOUR, OBSERVED_BEHAVIOUR, PASSED, FAIL_REASON,
       LATENCY_MS, ARRAY_TO_STRING(TOOLS_USED, ', ') AS TOOLS, ANSWER_TEXT, AGENT_SQL
FROM SUPPLY_CHAIN_FORGE.OPS.EVAL_RESULTS
WHERE RUN_LABEL = 'b10-baseline'
QUALIFY ROW_NUMBER() OVER (PARTITION BY QUESTION_ID ORDER BY RUN_TS DESC) = 1
ORDER BY QUESTION_ID;

-- ── Step 4. Art 07 (optional helper): one complete, unmodified agent response ─────
SELECT RESPONSE FROM SUPPLY_CHAIN_FORGE.OPS.EVAL_RESULTS
WHERE RUN_LABEL = 'b10-baseline' AND QUESTION_ID = 'Q02'
QUALIFY ROW_NUMBER() OVER (ORDER BY RUN_TS DESC) = 1;

-- ── Step 5 (optional). Snowflake's native agent evaluation ───────────────────────
-- Only if the optional grants in 00_setup.sql were given. Pass the Analyst tool's NAME
-- from the B10 agent spec. Expected: {"rows": 29, "ground_truth_errors": []}.
-- CALL SUPPLY_CHAIN_FORGE.OPS.SP_BUILD_EVAL_DATASET('<analyst tool name>')
-- CALL SYSTEM$CREATE_EVALUATION_DATASET('Cortex Agent',
--        'SUPPLY_CHAIN_FORGE.OPS.EVAL_DATASET', 'SUPPLY_CHAIN_FORGE.OPS.FORGE_EVAL_DATASET',
--        OBJECT_CONSTRUCT('query_text', 'INPUT_QUERY', 'expected_tools', 'GROUND_TRUTH'))
-- CREATE FILE FORMAT IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS.YAML_FF TYPE = 'CSV'
--        FIELD_DELIMITER = NONE RECORD_DELIMITER = '\n' SKIP_HEADER = 0
--        FIELD_OPTIONALLY_ENCLOSED_BY = NONE ESCAPE_UNENCLOSED_FIELD = NONE
-- CREATE STAGE IF NOT EXISTS SUPPLY_CHAIN_FORGE.OPS.EVAL_CONFIG FILE_FORMAT = SUPPLY_CHAIN_FORGE.OPS.YAML_FF
-- PUT file://eval/agent_eval_config.yaml @SUPPLY_CHAIN_FORGE.OPS.EVAL_CONFIG AUTO_COMPRESS = FALSE OVERWRITE = TRUE
-- CALL EXECUTE_AI_EVALUATION('START', OBJECT_CONSTRUCT('run_name', 'b10-native-1'),
--        '@SUPPLY_CHAIN_FORGE.OPS.EVAL_CONFIG/agent_eval_config.yaml')
-- CALL EXECUTE_AI_EVALUATION('STATUS', OBJECT_CONSTRUCT('run_name', 'b10-native-1'),
--        '@SUPPLY_CHAIN_FORGE.OPS.EVAL_CONFIG/agent_eval_config.yaml')
-- SELECT METRIC_NAME, AVG(EVAL_AGG_SCORE) AS SCORE, COUNT(*) AS N
-- FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_EVALUATION_DATA('SUPPLY_CHAIN_FORGE', 'SEMANTIC',
--        'SUPPLY_CHAIN_AGENT', 'CORTEX AGENT', 'b10-native-1'))
-- GROUP BY METRIC_NAME

-- ── Step 5 (B14): the adversarial set, its own label ──────────────────────────────
-- After reloading 10_questions.sql (40 rows, A01-A10 added) and re-creating 20_sp_run_eval.sql.
-- Expected: {"questions": 10, "by_category": {"ADVERSARIAL": {"n": 10, ...}}}, about 3-5 minutes.
-- Every failure names its reason: SQL generated where a refusal was expected, an e-mail
-- address or a guard hit (instruction text, a restricted value, a false claim), a missing
-- "not found" or "no data", or SQL that writes.
CALL SUPPLY_CHAIN_FORGE.OPS.SP_RUN_EVAL('b14-adv', 'A%');

SELECT QUESTION_ID, EXPECTED_BEHAVIOUR, OBSERVED_BEHAVIOUR, PASSED, FAIL_REASON, LATENCY_MS, ANSWER_TEXT, AGENT_SQL
FROM SUPPLY_CHAIN_FORGE.OPS.EVAL_RESULTS
WHERE RUN_LABEL = 'b14-adv'
QUALIFY ROW_NUMBER() OVER (PARTITION BY QUESTION_ID ORDER BY RUN_TS DESC) = 1
ORDER BY QUESTION_ID;
