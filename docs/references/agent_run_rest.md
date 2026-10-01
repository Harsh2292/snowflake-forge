# Cortex Agents `agent:run` REST API: streaming (Server-Sent Events)

> **Fetched**: 2026-10-01, for CR-008 (contract v1.7 §5.3b, card C18).
> **Sources**:
> - <https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-run> (endpoint, body, events)
> - <https://docs.snowflake.com/en/developer-guide/snowflake-rest-api/authentication> (auth methods)
> - <https://www.snowflake.com/en/developers/guides/getting-started-with-cortex-analyst-in-snowflake/>
>   and <https://github.com/Snowflake-Labs/sfguide-getting-started-with-cortex-analyst/issues/4>
>   (the connector session-token header used by Snowflake's own Streamlit examples)
> - <https://medium.com/@contactrishu/streamlit-in-snowflake-on-container-runtime-building-streaming-multi-turn-cortex-agents-apps-06774adc1ee9>
>   (agents API not available from SiS on the warehouse runtime)

## 1. Endpoint

```
POST /api/v2/databases/{database}/schemas/{schema}/agents/{name}:run
```
For this project: `https://<account host>/api/v2/databases/SUPPLY_CHAIN_FORGE/schemas/SEMANTIC/agents/SUPPLY_CHAIN_AGENT:run`.
(`POST /api/v2/cortex/agent:run` runs without an agent object; not used.)

Headers: `Authorization` (below), `Content-Type: application/json`, `Accept: text/event-stream`
for streaming (or `application/json` for one response).

## 2. Body

| Field | |
|---|---|
| `messages` | array of Message: the same shape as `DATA_AGENT_RUN` (contract §5.3, CR-007) |
| `thread_id` | optional integer (threads) |
| `parent_message_id` | integer, 0 for the first message of a thread |
| `stream` | boolean, **defaults to `true`**; `false` returns one JSON response |
| `background` | boolean; asynchronous, 6-hour timeout (not used) |

`tool_choice`, `models`, `instructions`, `orchestration`, `tools`, `tool_resources` are for the
object-less endpoint only.

## 3. Server-Sent Event types

| Event | Meaning |
|---|---|
| `response` | **the final aggregated response, the last event** |
| `response.text` | a completed text block |
| `response.text.delta` | an incremental text token |
| `response.text.annotation` | a citation or annotation added to text |
| `response.thinking` | a completed reasoning block |
| `response.thinking.delta` | an incremental reasoning token |
| `response.tool_use` | a tool invocation |
| `response.tool_result` | a tool execution's result |
| `response.tool_result.status` | a status update for one tool |
| `response.tool_result.analyst.delta` | Cortex Analyst streaming delta |
| `response.table` | a table content block |
| `response.chart` | a chart content block |
| `response.status` | an agent status update |
| `response.warning` | a non-fatal warning |
| `error` | a fatal error |
| `metadata` | thread message metadata |

Event data shapes (as documented):

```json
// response.text.delta
{"content_index": 0, "text": "token", "is_elicitation": false}
// response.thinking.delta
{"content_index": 0, "text": "reasoning", "signature": "string"}
// response.tool_use
{"content_index": 0, "tool_use_id": "string", "type": "tool_type", "name": "tool_name", "input": {},
 "client_side_execute": true, "permission": {"options": ["Allow Once", "Deny"]}}
// response.tool_result
{"content_index": 0, "tool_use_id": "string", "type": "tool_type", "name": "tool_name",
 "content": [{"type": "json", "json": {}}], "status": "success"}
// response.status
{"status": "executing_tool", "message": "descriptive message"}
// response (final)
{"role": "assistant", "content": [/* content items */], "warnings": [{"message": "string", "code": "string"}],
 "metadata": {"usage": {"tokens_consumed": []}, "run_id": "string", "thread_id": 0,
              "user_message_id": 0, "assistant_message_id": 0},
 "status": "completed"}
// error
{"code": "error_code", "message": "error description", "request_id": "uuid"}
```

**Non-streaming:** with `stream: false` the API returns one JSON object shaped like the
`response` event. That is the same shape `DATA_AGENT_RUN` returns (art 07), so
`utils/agent_response.parse_agent_response` parses the final `response` event unchanged.

## 4. Authentication

Documented for REST APIs: key-pair JWT (`Authorization: Bearer <JWT>`, optional
`X-Snowflake-Authorization-Token-Type: KEYPAIR_JWT`), OAuth, programmatic access tokens and
workload identity federation.

**The connector session token (what the app uses, CR-008 "no second login"):** Snowflake's
own Cortex Analyst Streamlit example for apps outside Snowflake calls the REST API with the
Python connector's session token:

```python
headers = {"Authorization": f'Snowflake Token="{conn.rest.token}"', "Content-Type": "application/json"}
```

In Snowpark, `session.connection` is that connector connection (`.rest.token`, `.host`). The
REST authentication page doesn't list this form. **CoCo verifies it live**, under the
`FORGE_APP_SVC_AUTH` policy (KEYPAIR through DRIVERS). If it's refused, the app falls back to
`DATA_AGENT_RUN` (§5.3) and logs why, and CoCo adjusts the policy (CR-008).

**Streamlit in Snowflake (warehouse runtime):** the agents REST API isn't reachable from it, so
SiS always uses `DATA_AGENT_RUN`.

## 5. Parsing SSE (the wire format)

Lines `event: <name>` and `data: <json>` (data may span several `data:` lines, joined with
`\n`). A blank line dispatches the event; lines starting with `:` are comments. Implemented in
`forge_data.sse_events`.
