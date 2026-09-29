# Reference — Cortex Agent evaluations

| | |
|---|---|
| **Sources** | <https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations> |
| | <https://docs.snowflake.com/en/sql-reference/functions/execute_ai_evaluation> |
| | <https://docs.snowflake.com/en/sql-reference/functions/system_create_evaluation_dataset> |
| | <https://docs.snowflake.com/en/sql-reference/functions/get_ai_evaluation_data-snowflake-local> |
| | <https://docs.snowflake.com/en/sql-reference/functions/get_ai_record_trace-snowflake-local> |
| **Fetched** | 2026-09-29 (raw `.md` versions) |
| **Written by** | CoCo for Claude Code (B08b); Claude Code owns this file afterwards. |

> Everything below is transcribed from the fetched pages unless marked **INFERRED**.

---

## 1. Dataset format

The evaluation dataset table has two columns:

| Column | Type | Description |
|--------|------|-------------|
| Input query | VARCHAR | The user query to evaluate. |
| Ground truth | VARIANT | JSON describing expected behavior. |

### Ground truth VARIANT structure

```json
{
  "ground_truth_output": "<rubric for answer correctness>",
  "ground_truth_invocations": [
    {
      "tool_name": "<tool_name>",
      "tool_input": "<expected input description>",
      "tool_output": "<expected output description>"
    }
  ]
}
```

| Key | Used by | Notes |
|-----|---------|-------|
| `ground_truth_output` | Answer correctness | Plain-language rubric with literal numbers, tolerances, and scope. |
| `ground_truth_invocations` | Tool selection accuracy (TSA), Tool execution accuracy (TEA) | Array of expected tool calls. Use `[]` when no tools expected. |

Both keys can coexist in one VARIANT. Keys not consumed by selected metrics are ignored.
Logical consistency is reference-free and needs no ground truth.

### Writing good `ground_truth_output`

Treat it as a **rubric**, not a single value:

- **Static factual:** State the value, tolerance, units, and exclusions.
  `"There are 1,000 active customers as of Dec 31, 2025. Within ±1% is acceptable."`
- **Dynamic/live:** Describe what a correct response should and shouldn't contain.
- **Out-of-scope:** State the agent should refuse and not fabricate.
- **Multi-fact:** List each fact the response must cover and explanations to avoid.

### `ground_truth_invocations` entry keys

| Key | Description | Used by |
|-----|-------------|---------|
| `tool_name` | Tool name as exposed to the agent. | TSA (required), TEA (required) |
| `tool_input` | Optional. Expected input description. | TEA only |
| `tool_output` | Optional. Expected output description. | TEA only |

`tool_input` and `tool_output` are VARCHAR-style strings (plain text, not rigid JSON).
The LLM judge interprets them semantically.

### Inserting a row

```sql
CREATE OR REPLACE TABLE agent_eval_data (
  input_query VARCHAR,
  ground_truth VARIANT
);

INSERT INTO agent_eval_data
  SELECT
    'What is our on-time delivery rate?',
    PARSE_JSON('{
      "ground_truth_output": "The OTD rate should be around 85-90%. Response must reference shipments data.",
      "ground_truth_invocations": [
        {
          "tool_name": "SupplyChainAnalyst",
          "tool_input": "on-time delivery rate",
          "tool_output": "SQL querying the shipments semantic view, returning a percentage."
        }
      ]
    }');
```

Use `PARSE_JSON()` — not `OBJECT_CONSTRUCT()` — to guarantee VARIANT type.

---

## 2. SYSTEM$CREATE_EVALUATION_DATASET

```sql
CALL SYSTEM$CREATE_EVALUATION_DATASET(
  'Cortex Agent',                          -- dataset type (case-insensitive)
  'DB.SCHEMA.SOURCE_TABLE',               -- source table FQN
  'DB.SCHEMA.MY_EVAL_DATASET',            -- dataset name FQN
  OBJECT_CONSTRUCT(
    'query_text', 'INPUT_QUERY',           -- column with the user query
    'expected_tools', 'GROUND_TRUTH'       -- column with the ground truth VARIANT
  )
);
```

**Important:** The column-mapping keys differ between SQL and YAML:
- SQL (`SYSTEM$CREATE_EVALUATION_DATASET`): `query_text` + `expected_tools`
- YAML (`dataset.column_mapping`): `query_text` + `ground_truth`

Privilege: `CREATE DATASET ON SCHEMA`.

---

## 3. Evaluation YAML configuration

Three top-level keys: `dataset` (optional), `evaluation`, `metrics`.

```yaml
# Optional: create dataset before running
dataset:
  dataset_type: "CORTEX AGENT"
  table_name: "EVALS_DB.EVALS_SCHEMA.EVAL_DATA"
  dataset_name: "MY_EVAL_DATASET"
  column_mapping:
    query_text: "INPUT_QUERY"
    ground_truth: "GROUND_TRUTH"

evaluation:
  agent_params:
    agent_name: "SUPPLY_CHAIN_AGENT"
    agent_type: "CORTEX AGENT"
    agent_version: "production"           # or VERSION$N, LIVE, DEFAULT, FIRST, LAST
  run_params:
    label: "Baseline v1"
    description: "First evaluation run"
  source_metadata:
    type: "dataset"
    dataset_name: "MY_EVAL_DATASET"

metrics:
  # Built-in, pinned to version:
  - name: "answer_correctness"
    version: "v3"
  # Built-in, default version:
  - "logical_consistency"
  # Tool metrics (Public Preview):
  - "tool_selection_accuracy"
  - "tool_execution_accuracy"
  # Custom metric:
  - name: "sql_quality"
    model: "claude-sonnet-4-6"
    score_ranges:
      min_score: [1, 3]
      median_score: [4, 6]
      max_score: [7, 10]
    prompt: |
      Evaluate whether the SQL generated is correct.
      Compare {{output}} with {{ground_truth}}.
      Rate 1-10.
```

### Dataset block caveat

If `dataset:` is present, `EXECUTE_AI_EVALUATION('START', ...)` tries to create the dataset
on every run. If the dataset already exists, the run fails. For repeated runs on the same
dataset, **remove the `dataset:` block** and keep only `evaluation:` + `metrics:`.

### Metric versions

| Version | Judge models | Notes |
|---------|-------------|-------|
| `v1` | `claude-4-sonnet` (200K) | Current default. Legacy model — new accounts may not have access. |
| `v2` | `claude-sonnet-4-5` (200K), `openai-gpt-5.2` (400K) | Adds GPT judge. |
| `v3` | `claude-sonnet-4-6` (1M), `openai-gpt-5.4` (1.05M) | Largest context; recommended for long traces. |

Use `v3` for agents with many tool calls (logical consistency sends the full trace).

### Custom metric prompt replacements

| Placeholder | GET_AI_RECORD_TRACE column |
|------------|---------------------------|
| `{{input}}` | INPUT |
| `{{output}}` | OUTPUT |
| `{{ground_truth}}` | GROUND_TRUTH |
| `{{tool_info}}` | TOOL |
| `{{duration}}` | DURATION_MS |
| `{{error}}` | ERROR |
| `{{status}}` | STATUS |

---

## 4. EXECUTE_AI_EVALUATION

```sql
CALL EXECUTE_AI_EVALUATION(
  '<job>',                                -- 'START', 'STATUS', 'CANCEL', 'DELETE'
  OBJECT_CONSTRUCT('run_name', '<name>'),
  '@stage/path/config.yaml'
);
```

- `'START'` returns a string (success/failure).
- `'STATUS'` returns a table: `RUN_NAME`, `AGENT_NAME`, `AGENT_TYPE`, `STATUS`, `STATUS_DETAILS`.

Status values: `CREATED`, `INVOCATION_IN_PROGRESS`, `INVOCATION_COMPLETED`,
`INVOCATION_PARTIALLY_COMPLETED`, `COMPUTATION_IN_PROGRESS`, `COMPLETED`,
`PARTIALLY_COMPLETED`, `CANCELLED`.

### Upload YAML to a stage

```sql
CREATE OR REPLACE FILE FORMAT evals.yaml_ff
  TYPE = 'CSV' FIELD_DELIMITER = NONE RECORD_DELIMITER = '\n'
  SKIP_HEADER = 0 FIELD_OPTIONALLY_ENCLOSED_BY = NONE
  ESCAPE_UNENCLOSED_FIELD = NONE;

CREATE OR REPLACE STAGE evals.eval_config FILE_FORMAT = evals.yaml_ff;

PUT file:///path/to/config.yaml @evals.eval_config
  AUTO_COMPRESS='false' OVERWRITE=TRUE;
```

---

## 5. GET_AI_EVALUATION_DATA (SNOWFLAKE.LOCAL)

```sql
SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_EVALUATION_DATA(
  'EVAL_DB', 'EVAL_SCHEMA', 'MY_AGENT', 'CORTEX AGENT', 'run-1'));
```

Returns one row per (input × metric):

| Column | Type | Description |
|--------|------|-------------|
| `RECORD_ID` | VARCHAR | Unique record ID. |
| `INPUT_ID` | VARCHAR | Unique input ID. |
| `REQUEST_ID` | VARCHAR | Snowflake request ID. |
| `TIMESTAMP` | TIMESTAMP_TZ | When the request was made. |
| `DURATION_MS` | INT | Agent response time. |
| `INPUT` | VARCHAR | The user query. |
| `OUTPUT` | VARCHAR | The agent's response. |
| `ERROR` | VARCHAR | Error info if any. |
| `GROUND_TRUTH` | VARCHAR | Ground truth JSON (serialized as string). |
| `METRIC_NAME` | VARCHAR | Metric name. |
| `EVAL_AGG_SCORE` | NUMBER | The score (0.0–1.0 for system metrics). |
| `METRIC_TYPE` | VARCHAR | `system` or `custom`. |
| `METRIC_STATUS` | VARIANT | `{status, message}` from the agent HTTP response. |
| `METRIC_CALLS` | ARRAY | Array of `{criteria, explanation, full_metadata}`. |
| `TOTAL_INPUT_TOKENS` | INT | Total input tokens. |
| `TOTAL_OUTPUT_TOKENS` | INT | Total output tokens. |
| `LLM_CALL_COUNT` | INT | Total LLM calls (agent + judge). |

`full_metadata` includes `normalized_score`, `original_score`, `prompt_tokens`,
`completion_tokens`, `total_tokens`.

---

## 6. GET_AI_RECORD_TRACE (SNOWFLAKE.LOCAL)

```sql
SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_RECORD_TRACE(
  'EVAL_DB', 'EVAL_SCHEMA', 'MY_AGENT', 'CORTEX AGENT',
  '<record_id>'));
```

Returns trace spans for a single evaluation record. Same column structure as
`GET_AI_EVALUATION_DATA`.

---

## 7. System metrics summary

| Metric | What it measures | Ground truth key | Scoring |
|--------|-----------------|------------------|---------|
| **Answer correctness** | Final response vs expected answer. | `ground_truth_output` | LLM judge; 0.0–1.0. |
| **Logical consistency** | Consistency across instructions, planning, and tool calls. | None (reference-free). | LLM judge; 0.0–1.0. |
| **Tool selection accuracy** (TSA) | Whether the right tools were invoked. | `ground_truth_invocations[].tool_name` | Deterministic; `matched / max(expected, actual)`. |
| **Tool execution accuracy** (TEA) | Quality of tool inputs and outputs. | `ground_truth_invocations[].tool_input/output` | LLM judge; 0.0–1.0. |

TSA scoring is deterministic — no LLM judge. If TSA changes between runs,
the agent invoked different tools, not a scoring variance.

TSA and TEA currently score: Cortex Analyst, Cortex Search, web search, and custom tools.
Other tool types are skipped.

---

## 8. Access control requirements

| Requirement | Notes |
|-------------|-------|
| `SNOWFLAKE.CORTEX_USER` database role | Required. |
| `USE AI FUNCTIONS` on account | Evaluation judges use Cortex LLM inference. Granted to PUBLIC by default. |
| `EXECUTE TASK ON ACCOUNT` | Evaluations run as tasks. |
| `USAGE` on agent's database and schema | — |
| `USAGE` or `OWNERSHIP` on agent | — |
| `MONITOR` or `OWNERSHIP` on agent | Required for `GET_AI_EVALUATION_DATA` and `GET_AI_RECORD_TRACE`. |
| `CREATE TABLE ON SCHEMA` | If creating the input table. |
| `CREATE DATASET ON SCHEMA` | If creating a dataset. |
| `CREATE FILE FORMAT ON SCHEMA` | For the evaluation's current db/schema. |
| `CREATE TASK` | For the evaluation's current db/schema. |
| `CREATE STAGE ON SCHEMA` | If creating the stage for the config file. |
| `READ` on stage | For the config file stage. |
| Access to all agent tools | The role running the evaluation needs the same tool access as production. |

---

## 9. Alternative: a DATA_AGENT_RUN-based runner

For cases where the built-in evaluation framework is not suitable (e.g., you need
deterministic SQL comparison rather than LLM-judged answer correctness), you can build
a custom runner using `SNOWFLAKE.CORTEX.DATA_AGENT_RUN()`.

See `docs/references/data_agent_run.md` for the full function reference.

### Approach

1. Call `DATA_AGENT_RUN(agent_fqn, request_json)` from SQL for each test query.
2. Parse the response to extract the generated SQL from
   `content[].tool_result.content[].json.sql`.
3. Re-execute the extracted SQL in a controlled environment.
4. Compare the result set against expected values deterministically
   (exact match, within-tolerance, etc.).

### Advantages over the built-in evaluation

- **Deterministic comparison:** You control the comparison logic — no LLM judge variance.
- **SQL-level testing:** You verify the generated SQL produces correct results, not just
  that the natural-language answer is similar.
- **No task/dataset infrastructure:** Runs as plain SQL; no stages, YAML configs, or
  dataset objects needed.
- **Per-query cost control:** You pay only for the agent call + the re-execution query.

### Limitations

- No built-in scoring, trending, or Snowsight UI integration.
- You must implement your own comparison logic and reporting.
- Synchronous `DATA_AGENT_RUN` has a 15-minute timeout.

### Skeleton

```sql
-- For each test query:
SET query = 'What is the on-time delivery rate by region?';
SET response = (
  SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT',
    OBJECT_CONSTRUCT('messages', ARRAY_CONSTRUCT(
      OBJECT_CONSTRUCT('role', 'user', 'content',
        ARRAY_CONSTRUCT(OBJECT_CONSTRUCT('type', 'text', 'text', $query)))))::VARCHAR
  )
);

-- Extract the generated SQL (see data_agent_run.md §4 for the path):
SET generated_sql = (
  SELECT TRY_PARSE_JSON($response):content[1]:tool_result:content[0]:json:sql::VARCHAR
);

-- Re-execute and compare against expected results...
```

---

## Gotchas

1. **Column-mapping key mismatch:** `SYSTEM$CREATE_EVALUATION_DATASET` uses `expected_tools`
   for the ground truth column. The YAML `dataset.column_mapping` uses `ground_truth`.
   Mixing them up causes silent failures.
2. **Dataset creation is not idempotent.** If the `dataset:` block is in the YAML, every
   `START` tries to create the dataset. Remove it after the first run to avoid errors.
3. **Agent version pinning:** Omitting `agent_version` targets the live/default version,
   which is mutable. Pin a committed version (e.g., `VERSION$3`) for reproducible evaluations.
4. **TSA is deterministic but TEA and answer correctness are not.** Run the same dataset
   several times to learn the normal score range before gating CI/CD on a threshold.
5. **Metric versions are not interchangeable.** Scores from `v1` and `v3` are not comparable.
   Stick to one version across runs.
6. **`v1` default judge (`claude-4-sonnet`) is legacy.** Accounts that never used it before
   its legacy date (2026-08-12) must pin `v2` or `v3`.
7. **Evaluations do not support MCP tools.** The run proceeds but MCP tools are not called.
8. **Session attributes and row access policies are not supported.** Evaluation runs don't
   pass session attributes, so results won't match production for multi-tenant agents.
9. **INFERRED**: The docs do not mention a maximum dataset size, but note that agent response
   times constrain throughput. Large datasets may need to be split.
