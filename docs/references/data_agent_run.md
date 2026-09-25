# Reference — `SNOWFLAKE.CORTEX.DATA_AGENT_RUN()`

| | |
|---|---|
| **Sources** | <https://docs.snowflake.com/en/sql-reference/functions/data_agent_run-snowflake-cortex> |
| | <https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-run> (schemas) |
| **Fetched** | 2026-09-24 (raw `.md` versions of both pages) |
| **Used by** | `forge_data.ask_agent()` (C02), Tab 1 · Ask (C03), parser verification (C6c) |

> Everything below is transcribed from the fetched pages unless marked **INFERRED**.
> The one real gap in the docs is flagged in §6. Artifact `07_agent_response.json` (B10)
> closes it.

---

## 1. Signature

```sql
SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  '<agent_name>[!<version>]',
  <request_body>
  [, <create_thread_if_not_present> ]
)
```

| Arg | Type | Notes |
|-----|------|-------|
| `agent_name` | string | FQN `db.schema.agent`. Optional `!LIVE`, `!DEFAULT`, `!VERSION$N`, `!LAST`, `!FIRST`. No suffix → DEFAULT version (falls back to LIVE if no default set). |
| `request_body` | **string** | JSON text, e.g. a `$$...$$` literal. Must be a string, not a VARIANT. |
| `create_thread_if_not_present` | BOOLEAN | Default `FALSE`. If `TRUE` and body has no `thread_id`, a thread is created and its id is returned in `metadata.thread_id`. |

**Returns**: a JSON **string** — the *final aggregated* response, not SSE events.
Wrap in `TRY_PARSE_JSON()` to get a VARIANT.

### Hard rules from the docs
- `"stream": true` in the body → **error**. The function is always non-streaming.
- `"background": true` requires a `thread_id`; returns immediately with
  `"status": "in_progress"` and a `run_id`; poll `SNOWFLAKE.CORTEX.THREAD_MESSAGES`.
  **We do not use background runs.**
- Synchronous runs time out after **15 minutes**.
- Caller's role needs access to Cortex Agents **and** the agent object.

---

## 2. Request body

| Field | Type | Notes |
|-------|------|-------|
| `messages` | array of `Message` | Without threads: full history + current message. With threads: current message only. |
| `thread_id` | integer | If set, `parent_message_id` is required too. |
| `parent_message_id` | integer | `0` for the first message in a thread. |
| `background` | boolean | See above. |
| `stream` | boolean | Must be absent or `false` for this function. |
| `tool_choice` | `{type: auto\|required\|tool, name: [..]}` | `auto` is the default. |

`Message` = `{ "role": "user"|"assistant", "content": [ {"type":"text","text":"..."} ] }`

### Our call (contract §5.3), checked against the docs

```sql
SELECT TRY_PARSE_JSON(
  SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT',
    OBJECT_CONSTRUCT('messages', ARRAY_CONSTRUCT(
      OBJECT_CONSTRUCT('role', 'user', 'content',
        ARRAY_CONSTRUCT(OBJECT_CONSTRUCT('type', 'text', 'text', ?)))))::VARCHAR,
    TRUE
  )
) AS response;
```

- `::VARCHAR` on the OBJECT satisfies "request_body must be a string". ✅
- The third arg `TRUE` creates a **new thread on every call** (no `thread_id` is sent).
  Harmless for single-turn Q&A; the response carries `metadata.thread_id` if we later want
  follow-up questions. ✅
- Binding the question with `?` keeps user text out of the SQL string (no injection). ✅

---

## 3. Response — top level

```jsonc
{
  "role": "assistant",                 // always "assistant"
  "content": [ MessageContentItem … ], // ordered; see §4
  "warnings": [ { "code": "399569", "message": "TOOL_NOT_ACCESSIBLE: …" } ], // optional
  "metadata": {
    "run_id": "4264-83472",
    "thread_id": 4264,                 // present when a thread was used/created
    "user_message_id": 83472,
    "assistant_message_id": 83473,     // use as parent_message_id for a follow-up
    "usage": { "tokens_consumed": [ { "model_name": "…",
                 "input_tokens": {"total":175,"cache_read":50,"cache_write":25,"uncached":100},
                 "output_tokens": {"total":75}, "context_window": 128000 } ] }
  },
  "status": "completed"                // or "cancelled" / "timed_out"
}
```

---

## 4. `content[]` item types

Every item has a `type` discriminator and a **same-named key** holding the payload
(except `text`, whose fields are inline).

| `type` | Payload key | Payload fields |
|--------|-------------|----------------|
| `text` | *(inline)* | `text`, `annotations[]`, `is_elicitation` |
| `thinking` | `thinking` | `text`, `signature` |
| `tool_use` | `tool_use` | `tool_use_id`, `type`, `name`, `input` (object), `client_side_execute`, `permission` |
| `tool_result` | `tool_result` | `tool_use_id`, `type`, `name`, `content[]` (ToolResultContent), `status` |
| `table` | `table` | `tool_use_id`, `query_id`, `result_set` (ResultSet), `title` |
| `chart` | `chart` | `tool_use_id`, `chart_spec` (**vega-lite JSON as a string**) |
| `permission_decision` | `permission_decision` | client → server only; ignore |

The docs say: **"Make sure your application can handle unknown event types."**
The parser must skip unknown `type`s, not crash.

### `ToolResultContent` (inside `tool_result.content[]`)

| `type` | Fields |
|--------|--------|
| `json` | `json` — object, **"schema varies depending on the tool type"** |
| `text` | `text` — string |

### `ResultSet` (used by `table` and tool results) — SQL API shape

```jsonc
{
  "statementHandle": "<query id>",
  "resultSetMetaData": {
    "partition": 0, "numRows": 2, "format": "jsonv2",
    "rowType": [ { "name": "MY_COLUMN", "type": "VARCHAR",
                   "length": 0, "precision": 0, "scale": 0, "nullable": false } ]
  },
  "data": [ ["row1 col1", "row1 col2"], ["row2 col1", "row2 col2"] ]
}
```

⚠ `data` values arrive as **strings** (the docs' own example has `"3"` for a count).
Cast numbers using `rowType[i].type` / `scale`. `rowType` may be **absent** (the
non-streaming example in the docs omits it), so fall back to positional column names.

### `Annotation` (citations on `text` items)

Only `cortex_search_citation` is documented: `type`, `index`, `search_result_id`,
`doc_id`, `doc_title`, `text`. Our agent has no Cortex Search tool, so expect none.

---

## 5. Official complete example (non-streaming)

Verbatim from the Run API page, "Non-streaming response":

```json
{
  "role": "assistant",
  "content": [
    { "thinking": { "text": "\nThe user is asking about types of products...\n" },
      "type": "thinking" },
    { "tool_use": {
        "client_side_execute": false,
        "input": { "sql": "WITH __table_a AS (...) SELECT ...",
                   "execution_environment": { "type": "warehouse", "warehouse": "my_warehouse" } },
        "name": "system_execute_sql",
        "tool_use_id": "<tool_use_id>",
        "type": "system_execute_sql" },
      "type": "tool_use" },
    { "tool_result": {
        "content": [ { "json": {
            "query_id": "<query_id>",
            "result_set": {
              "data": [ ["Electronics", "3", "3"], ["Furniture", "2", "2"] ],
              "resultSetMetaData": { "format": "jsonv2", "numRows": 2, "partition": 0 },
              "statementHandle": "<statement_handle>" },
            "sql": "WITH __table_a AS (...) SELECT ..." },
          "type": "json" } ],
        "name": "system_execute_sql",
        "status": "success",
        "tool_use_id": "<tool_use_id>",
        "type": "system_execute_sql" },
      "type": "tool_result" },
    { "text": "Based on the data available, there are 2 main types of products...",
      "type": "text" }
  ],
  "warnings": [ { "code": "399569",
    "message": "TOOL_NOT_ACCESSIBLE: Search1 (cortex_search) - The Cortex Search Service does not exist or access is not authorized for the current role: db.schema.css1" } ]
}
```

Note: in this example the SQL is executed by a **separate `system_execute_sql` tool**,
and the SQL appears in **both** `tool_use.input.sql` and `tool_result.content[].json.sql`.

---

## 6. ⚠ The documentation gap — Analyst tool result payload

For `cortex_analyst_text_to_sql` tool results, the docs give only a placeholder
(`"json": {"answer": 42}`). The **field names are not formally specified**.

**INFERRED** from the streaming `CortexAnalystToolResultDelta` schema (which *is*
documented and is what gets aggregated into the final tool result):

| Field | Meaning |
|-------|---------|
| `text` | Analyst's own interpretation text |
| `sql` | Generated SQL (arrives whole, not token-streamed) |
| `sql_explanation` | Plain-English explanation of the SQL |
| `query_id` | Query id once execution starts |
| `verified_query_used` | **boolean — true if a pinned verified query (VQR) answered it** |
| `result_set` | ResultSet |
| `suggestions` | Suggested questions when Analyst can't answer |

`verified_query_used` matters for us: it is direct evidence for "the answer came from a
canonical, human-verified definition" — worth surfacing in the Ask tab's lineage caption.

**Action**: confirm these names against `docs/artifacts/07_agent_response.json` at C6c.
If they differ, the parser follows the artifact and we note it here.

---

## 7. Errors and failure shapes

| Situation | How it presents |
|-----------|-----------------|
| Fatal error during the run | SQL statement fails / `error` object `{code, message, request_id}` (e.g. `399504` "Error during execution"). In threads, message `status: "error"` + `error: {code, message}`. |
| Unparseable return | `TRY_PARSE_JSON` returns `NULL` → treat as failure. |
| A tool the role can't access | **Not fatal.** Top-level `warnings[]`, code `399569`, `TOOL_NOT_ACCESSIBLE: …`. Surface it. |
| MCP tools unavailable | Warning code `003001`. |
| Run cancelled / too long | Top-level `status`: `"cancelled"` / `"timed_out"`. |
| Tool failed | `tool_result.status` ≠ `"success"`. |
| Analyst couldn't answer | **INFERRED**: no `sql`, populated `suggestions`; final `text` may be an elicitation (`is_elicitation: true`). |

---

## 8. Parser recipe (what `ask_agent()` extracts)

Target return shape from the task card: `{answer, sql, metric_used, raw}`.

```python
def parse_agent_response(resp: dict) -> dict:
    content = resp.get("content") or []
    texts, sqls, tables, tools, verified = [], [], [], [], None
    for item in content:
        t = item.get("type")
        if t == "text":
            texts.append(item.get("text", ""))
        elif t == "tool_use":
            tu = item.get("tool_use", {})
            tools.append(tu.get("name"))
            if (s := (tu.get("input") or {}).get("sql")):
                sqls.append(s)
        elif t == "tool_result":
            for c in item.get("tool_result", {}).get("content") or []:
                j = c.get("json") or {}
                if (s := j.get("sql")):
                    sqls.append(s)
                if "verified_query_used" in j:          # INFERRED field
                    verified = j["verified_query_used"]
                if (rs := j.get("result_set")):
                    tables.append(rs)
        elif t == "table":
            tables.append(item.get("table", {}).get("result_set"))
        # thinking / chart / unknown → ignore (docs: tolerate unknown types)
    return {
        "answer": "\n\n".join(x for x in texts if x).strip(),
        "sql": sqls[-1] if sqls else None,     # dedupe: same SQL can appear twice
        "tools_used": [x for x in tools if x],
        "verified_query_used": verified,
        "tables": tables,
        "warnings": resp.get("warnings") or [],
        "status": resp.get("status", "completed"),
        "raw": resp,
    }
```

`metric_used` is **not** a field in the response. Derive it in the app by matching the
extracted SQL against the contract §3 metric identifiers (e.g. the SQL contains
`on_time_delivery_rate`) and then showing that metric's contract definition.

Rules for the parser:
1. Never index blindly: `.get()` everywhere, tolerate missing `rowType`, missing `content`.
2. Skip unknown `type`s.
3. The final answer is the `text` item(s), normally the **last** content item.
4. Always keep `raw` — the Ask tab shows it in an expander, and it's our debugging lifeline.
