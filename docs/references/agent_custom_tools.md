# Reference — Cortex Agent custom tools

| | |
|---|---|
| **Sources** | <https://docs.snowflake.com/en/sql-reference/sql/create-agent> |
| | <https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents> |
| | <https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage> |
| | <https://docs.snowflake.com/en/sql-reference/functions/data_agent_run-snowflake-cortex> |
| **Fetched** | 2026-09-29 (raw `.md` versions) |
| **Written by** | CoCo for Claude Code (B08b); Claude Code owns this file afterwards. |

> Everything below is transcribed from the fetched pages unless marked **INFERRED**.

---

## 1. CREATE AGENT syntax

```sql
CREATE [ OR REPLACE ] [ { TEMP | TEMPORARY } ] [ SECURE ] AGENT [ IF NOT EXISTS ] <name>
  [ COPY GRANTS ]
  [ COMMENT = '<comment>' ]
  [ PROFILE = '<profile_object>' ]
  FROM SPECIFICATION $$ <yaml_spec> $$;
```

The YAML specification is a VARCHAR (max 100,000 bytes). Successful creation does not
guarantee valid tool specs; test the agent before deploying.

Privilege: `CREATE AGENT ON SCHEMA` (not required for temporary agents).

---

## 2. Specification YAML structure

```yaml
models:
  orchestration: <model_name>          # e.g. "auto", "claude-sonnet-4-6"

orchestration:
  capabilities:
    analytical_search: true            # default false
  tool_not_accessible: accept | reject | legacy   # default "accept"
  budget:
    seconds: <n>
    tokens: <n>                        # orchestration tokens only

instructions:
  response: '<response_instructions>'
  orchestration: '<orchestration_instructions>'
  sample_questions:
    - question: '<sample_question>'

tools:
  - tool_spec:
      type: '<tool_type>'
      name: '<tool_name>'              # 1-64 characters
      description: '<tool_description>'
      input_schema:                    # optional; for custom tools
        type: 'object'
        properties:
          <param_name>:
            type: '<json_type>'
            description: '<param_description>'
        required: [<param_names>]

tool_resources:
  <tool_name>:
    <resource_key>: '<resource_value>'
```

---

## 3. Built-in tool types

### 3.1 `cortex_analyst_text_to_sql`

Generates SQL from natural language using a semantic view.

```yaml
tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "Analyst1"
      description: "Financial analysis"

tool_resources:
  Analyst1:
    semantic_view: "db.schema.semantic_view"
    execution_environment:
      type: "warehouse"
      warehouse: "my_wh"
```

The `execution_environment` is optional. If omitted, the caller's default warehouse is used.

### 3.2 `cortex_search`

Retrieves from unstructured data via a Cortex Search service.

```yaml
tools:
  - tool_spec:
      type: "cortex_search"
      name: "Search1"
      description: "Searches policy docs"

tool_resources:
  Search1:
    search_service: "db.schema.service_name"
    max_results: "5"
    filter:
      "@eq":
        region: "North America"
    title_column: "TITLE"
    id_column: "DOC_ID"
    stage_path: "@db.schema.stage_name"
    relative_path_column: "RELATIVE_PATH"
    columns_and_descriptions:
      TEXT:
        description: "Main document text"
        type: "string"
        searchable: true
        filterable: false
```

### 3.3 `data_to_chart`

Generates Vega-Lite chart specs from data. No tool_resources needed.

```yaml
tools:
  - tool_spec:
      type: "data_to_chart"
      name: "data_to_chart"
      description: "Generates visualizations from data"
```

### 3.4 `web_search`

Retrieves real-time information from the public internet (Brave API).
Must be enabled at the account level first.

```yaml
tools:
  - tool_spec:
      type: "web_search"
      name: "Web Search"
```

---

## 4. Custom tools (stored procedures and UDFs)

Custom tools let the agent call your own stored procedures or UDFs.
The tool type in the YAML spec is `"generic"`.

### 4.1 tool_spec for a custom tool

```yaml
tools:
  - tool_spec:
      type: "generic"
      name: "my_custom_tool"
      description: "Describe what this tool does and when to use it"
      input_schema:
        type: "object"
        properties:
          city:
            type: "string"
            description: "The city name"
          date:
            type: "string"
            description: "The date in YYYY-MM-DD format"
        required:
          - city
```

The `input_schema` uses JSON Schema syntax. The agent maps these properties to the
procedure/function parameters when calling the tool.

**Limitation:** parameters of type `object` are not supported.

### 4.2 tool_resources for a custom tool

The docs show the REST API form:

```json
{
  "tool_resources": {
    "my_custom_tool": {
      "type": "function",
      "identifier": "db.schema.my_udf(VARCHAR, VARCHAR)",
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "my_wh",
        "query_timeout": 60
      }
    }
  }
}
```

In YAML (for CREATE AGENT):

```yaml
tool_resources:
  my_custom_tool:
    type: "function"                  # or "procedure"
    identifier: "db.schema.my_udf(VARCHAR, VARCHAR)"
    execution_environment:
      type: "warehouse"
      warehouse: "my_wh"
      query_timeout: 60              # seconds; optional
```

| Key | Required | Description |
|-----|----------|-------------|
| `type` | Yes | `"function"` (UDF) or `"procedure"` (stored procedure). |
| `identifier` | Yes | FQN of the function/procedure, including the argument type signature. |
| `execution_environment` | Yes | Must specify `type: "warehouse"` and the `warehouse` name. |
| `query_timeout` | No | Timeout in seconds for the tool call. |

**INFERRED**: In Snowsight, the warehouse must be manually selected. The REST API and SQL
paths also require it explicitly — there is no automatic warehouse fallback for custom tools.

### 4.3 How arguments map

The agent takes the `input_schema` properties and passes them as arguments to the
procedure/function in the order defined by the function signature. The `input_schema`
property names should match the parameter names of the procedure/function.

### 4.4 What the procedure should return

The docs do not specify an explicit return-type requirement for custom tool procedures/UDFs.
The Snowsight UI auto-detects the parameters from the function signature.

**INFERRED**: The procedure can return a scalar (VARCHAR, VARIANT) or a table. The result
is serialized to JSON and passed to the LLM as the tool result. For large results, keep the
output concise — the result must fit within the agent's context window. The docs do not
state an explicit size limit for custom tool results, but the orchestration budget
(`tokens`) and the model's context window are the practical constraints.

### 4.5 Owner's rights vs caller's rights

From the docs: "When using stored procedures, agents maintain whether the procedure runs
with owner's or caller's rights." The agent executes the procedure under the role of the
**calling user's default role** (for caller's rights procedures) or the **owner role**
(for owner's rights procedures), same as a direct `CALL`.

### 4.6 Privileges

The calling user's role needs `USAGE` on the procedure/function. The agent doesn't
automatically grant access — you must explicitly `GRANT USAGE ON FUNCTION/PROCEDURE` to
the roles that will call the agent.

---

## 5. Tool calls and results in the response

When the agent calls a tool, the response `content[]` array contains `tool_use` and
`tool_result` items. See `docs/references/data_agent_run.md` §4 for the full schema.

### tool_use item

```json
{
  "type": "tool_use",
  "tool_use": {
    "tool_use_id": "<id>",
    "type": "<tool_type>",
    "name": "<tool_name>",
    "input": { ... },
    "client_side_execute": false,
    "permission": null
  }
}
```

For custom tools, `name` is the tool name from the spec, `type` is `"generic"`,
and `input` contains the argument values the agent chose.

### tool_result item

```json
{
  "type": "tool_result",
  "tool_result": {
    "tool_use_id": "<id>",
    "type": "<tool_type>",
    "name": "<tool_name>",
    "content": [
      { "type": "json", "json": { ... } }
    ],
    "status": "success"
  }
}
```

For Analyst tools, the `json` payload includes `sql`, `result_set`, `query_id`,
`verified_query_used`, etc. For custom tools, the `json` payload contains whatever
the procedure/function returned, serialized.

---

## 6. ALTER AGENT, DESCRIBE AGENT, SHOW AGENTS

### ALTER AGENT

```sql
ALTER AGENT <name> MODIFY LIVE VERSION SET SPECIFICATION = $$ <new_yaml> $$;
```

The new specification **completely replaces** the existing one. Fields not included
are removed. Use `COPY GRANTS` on replacement to preserve access.

### DESCRIBE AGENT

```sql
DESCRIBE AGENT <name>;
```

For secure agents, the full specification is visible only to the owner role.

### SHOW AGENTS

```sql
SHOW AGENTS [ IN SCHEMA <schema> ];
```

---

## 7. Access control summary

| Privilege | Object | Notes |
|-----------|--------|-------|
| `CREATE AGENT` | Schema | Create a permanent agent. Not needed for temp agents. |
| `OWNERSHIP` | Agent | Replace an existing agent with `CREATE OR REPLACE`. |
| `USAGE` | Agent | Required to call the agent. |
| `USAGE` | Cortex Search service | If the agent uses Cortex Search. |
| `USAGE` | Database, schema, table | For objects referenced by the semantic view. |
| `USAGE` | Function/Procedure | For custom tools: the caller's role needs this. |
| `SNOWFLAKE.CORTEX_USER` | Database role | Required to call any agent. |

---

## Gotchas

1. **Custom tool type is `"generic"`, not `"custom"` or `"procedure"`.** The Snowsight UI
   labels them "Custom tools" but the YAML spec type is `"generic"`.
2. **Stored procedures with `object`-type parameters are not supported** by Cortex Agents.
3. **The `execution_environment` with a warehouse is required for custom tools.** There is
   no serverless fallback.
4. **`tool_not_accessible: accept`** (the default) lets the agent run even if a tool's
   privileges are missing — it issues a warning (`399569`) but doesn't abort.
5. **The new specification in ALTER AGENT replaces the old one entirely.** Omitting a tool
   from the new spec removes it.
6. **Spec max size is 100,000 bytes.** Plan accordingly for agents with many tools.
7. **INFERRED**: The docs do not explicitly document the `tool_resources` YAML shape for
   custom tools in the CREATE AGENT SQL page. The REST API page shows JSON with keys
   `type`, `identifier`, `execution_environment`. The YAML equivalent is shown above
   based on the JSON structure. The Snowsight UI auto-populates parameters from the
   function signature, which suggests the mapping is by parameter name/position.
8. **INFERRED**: No explicit result-size limit is documented for custom tool returns.
   The practical limit is the orchestration model's context window.
