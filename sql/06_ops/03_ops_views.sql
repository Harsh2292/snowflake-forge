-- ============================================================
-- 03_ops_views.sql — "who asked what, what ran, what failed" in two views
-- Task: B14/B15 (observability), user-approved 2026-10-01
-- Owner: CoCo
-- Run as: ACCOUNTADMIN (owns the views; reads SNOWFLAKE.LOCAL agent traces and ACCOUNT_USAGE).
-- Re-runnable. Account-agnostic: names no account.
-- ============================================================
-- Sources (Snowflake records both automatically; nothing to switch on):
--   SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(...)  the agent's OpenTelemetry traces: one trace
--     per question (turn), spans for planning, each tool, SQL execution and the response
--     (docs: Monitor Cortex Agent requests). Near real time.
--   SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY  every SQL statement, 365 days, ~45 min latency. The
--     app tags each query with the function that ran it (QUERY_TAG 'forge_app:<function>').
-- "Who": the public link has no login, so every visitor is the service user FORGE_APP_SVC.
-- Telling visitors apart needs an anonymous session id in the app's QUERY_TAG (Claude Code).

USE ROLE ACCOUNTADMIN;

-- One row per agent question (turn). Spans of the same turn share TRACE:trace_id.
CREATE OR REPLACE VIEW SUPPLY_CHAIN_FORGE.OPS.V_AGENT_REQUESTS
  COMMENT = 'B14: one row per agent question: when, who (Snowflake user/role), question, answer, status, duration, tools, SQL query ids, tokens'
AS
WITH ev AS (
  SELECT TRACE:trace_id::STRING AS trace_id, RECORD:name::STRING AS span, RECORD:status AS span_status,
         START_TIMESTAMP, TIMESTAMP, RECORD_ATTRIBUTES AS a, RESOURCE_ATTRIBUTES AS r
  FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
         'SUPPLY_CHAIN_FORGE', 'SEMANTIC', 'SUPPLY_CHAIN_AGENT', 'CORTEX AGENT'))
),
turn AS (
  SELECT trace_id,
         START_TIMESTAMP                                                 AS started_at,
         TIMESTAMP                                                       AS ended_at,
         r:"snow.user.name"::STRING                                      AS user_name,
         r:"snow.session.role.primary.name"::STRING                      AS role_name,
         r:"snow.session.id"::NUMBER                                     AS session_id,
         a:"snow.ai.observability.agent.thread_id"::NUMBER               AS thread_id,
         a:"snow.ai.observability.agent.message_id"::NUMBER              AS message_id,
         a:"ai.observability.record_root.input"::STRING                  AS question,
         a:"ai.observability.record_root.output"::STRING                 AS answer,
         a:"snow.ai.observability.agent.status"::STRING                  AS status,
         a:"snow.ai.observability.agent.status.code"::STRING             AS status_code,
         a:"snow.ai.observability.agent.status.description"::STRING      AS status_description,
         a:"snow.ai.observability.agent.duration"::NUMBER                AS duration_ms
  FROM ev WHERE span = 'AgentV2RequestResponseInfo'
),
tools AS (
  SELECT trace_id,
         ARRAY_AGG(DISTINCT span) WITHIN GROUP (ORDER BY span)           AS spans,
         ARRAY_AGG(DISTINCT a:"snow.ai.observability.agent.tool.sql_execution.query_id"::STRING)
           AS sql_query_ids,
         COUNT_IF(a:"snow.ai.observability.agent.tool.sql_execution.status"::STRING NOT IN ('SUCCESS', 'success')
                  OR a:"snow.ai.observability.agent.tool.custom_tool.status"::STRING NOT IN ('SUCCESS', 'success'))
           AS failed_tool_calls
  FROM ev WHERE span <> 'AgentV2RequestResponseInfo' GROUP BY trace_id
),
-- The token counts arrive as a separate EVENT without the trace id: join it on the message id.
tokens AS (
  SELECT a:"snow.ai.observability.agent.message_id"::NUMBER AS message_id,
         MAX(a:"snow.ai.observability.token_count.total"::NUMBER) AS tokens_total
  FROM ev WHERE span = 'CORTEX_AGENT_REQUEST' GROUP BY 1
)
SELECT t.*, tl.spans, tl.sql_query_ids, tl.failed_tool_calls, k.tokens_total
FROM turn t LEFT JOIN tools tl USING (trace_id) LEFT JOIN tokens k USING (message_id);

-- Every failed SQL statement of the public app (its own queries and the agent's), newest first.
CREATE OR REPLACE VIEW SUPPLY_CHAIN_FORGE.OPS.V_APP_ERRORS
  COMMENT = 'B14: failed queries of the public app user FORGE_APP_SVC, with the app function (QUERY_TAG) that ran them; ACCOUNT_USAGE latency ~45 min'
AS
SELECT start_time, query_tag, role_name, error_code, error_message, query_id, session_id,
       total_elapsed_time AS elapsed_ms, LEFT(query_text, 2000) AS query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE user_name = 'FORGE_APP_SVC' AND execution_status <> 'SUCCESS';

-- Examples:
--   SELECT started_at, question, status, duration_ms, spans FROM SUPPLY_CHAIN_FORGE.OPS.V_AGENT_REQUESTS ORDER BY started_at DESC LIMIT 20;
--   SELECT * FROM SUPPLY_CHAIN_FORGE.OPS.V_APP_ERRORS WHERE start_time > DATEADD(day, -1, CURRENT_TIMESTAMP()) ORDER BY start_time DESC;
