# Reference — Snowflake-managed MCP server (client side)

| | |
|---|---|
| **Source** | <https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp> |
| **Fetched** | 2026-09-24 (raw `.md` version) |
| **Used by** | B14 (CoCo builds the server), C05 (demo/README story), deferred B07c |

> **Status in this project**: the MCP server is a **product feature shown to judges**
> (B14), not Claude Code's development channel. Artifacts in `docs/artifacts/` replace
> live access (see `.agents/NEXT.md`). This file exists so the README/demo describe
> it accurately, and so B07c can be done correctly if it's ever needed.

---

## 1. Facts that matter

- Snowflake supports MCP spec revision **`2025-11-25`**.
- The server supports **tools only**. No resources, prompts, roots, notifications,
  version negotiation, lifecycle phases, or sampling.
- Max **50 tools** per server.
- Generic and SQL-execution tool responses are **truncated at 250 KB**.
- **Since 2026-08-20, `tools/call` responses are an SSE stream.** Clients must send
  `Accept: application/json, text/event-stream`. The stream ends with `data: [DONE]`.
- Agent-tool responses include all intermediate steps (reasoning, tool calls, citations)
  and can be **200 KB+**.
- MCP server objects **aren't replicated** in failover groups.
- Max recursion depth of **10** invocations. Avoid agent → MCP → agent loops.

---

## 2. Endpoint

```
https://<account_url>/api/v2/databases/{database}/schemas/{schema}/mcp-servers/{name}
```

Ours: `…/api/v2/databases/SUPPLY_CHAIN_FORGE/schemas/SEMANTIC/mcp-servers/SUPPLY_CHAIN_MCP`

### ⚠ Hyphens, not underscores

> "When you configure hostnames for MCP server connections, use hyphens (`-`) instead of
> underscores (`_`). MCP servers have connection issues with hostnames containing
> underscores."

This applies to the **account hostname** (e.g. an org/account name with `_`), not the
database/schema/server path segments. Troubleshooting row: *"The client reports a
hostname-related connection failure → The account hostname contains underscores →
Replace `_` with `-`."*

---

## 3. Authentication

| Method | Doc position |
|--------|-------------|
| **Snowflake OAuth** | **Default and recommended.** Needs a `SECURITY INTEGRATION` (`TYPE = OAUTH`, `OAUTH_CLIENT = CUSTOM`, `OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'`, `OAUTH_REDIRECT_URI = '<client callback>'`, `OAUTH_USE_SECONDARY_ROLES = NONE`). **No dynamic client registration.** Client id and secret come from `SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('<integration>')`. |
| External OAuth | Optional. Okta, Entra ID, etc. |
| **PAT** (Programmatic Access Token) | Allowed but discouraged ("hardcoded tokens can lead to token leakage"). If used, bind it to the **least-privileged role** that can use MCP. |

**INFERRED** (not on this page): a PAT is sent as `Authorization: Bearer <PAT>`, the
standard for Snowflake REST APIs. Verify before B07c.

### Which role the session uses
- OAuth sessions use the connecting user's **`DEFAULT_ROLE`** as primary role (servers
  advertise `session:role:all`).
- **Claude clients request `session:role:all` and can't pick a role**, so the session
  is always the user's `DEFAULT_ROLE`. → The demo user's default role must be the MCP
  access role. (Matches artifact `01_default_role.md` at B02: "agents use default role,
  not session role.")
- Secondary roles: leave `OAUTH_USE_SECONDARY_ROLES = NONE`.
- The user **must have `DEFAULT_WAREHOUSE` set**, or the session fails to initialise.

---

## 4. Access control — `USAGE` on the server ≠ access to tools

> "Access to the MCP Server does not give access to the tools. Permission needs to be
> granted for each tool."

| Privilege | Object | Grants |
|-----------|--------|--------|
| `USAGE` | MCP SERVER | Connect + **discover** tools (`tools/list`) |
| `USAGE` | AGENT | Invoke a `CORTEX_AGENT_RUN` tool |
| `SELECT` | SEMANTIC VIEW | Invoke a `CORTEX_ANALYST_MESSAGE` tool |
| `USAGE` | CORTEX SEARCH SERVICE | Invoke a search tool |
| `USAGE` | FUNCTION / PROCEDURE | Invoke a `GENERIC` tool |
| `MODIFY` | MCP SERVER | Update/drop/describe + `tools/list` + `tools/call` |
| `OWNERSHIP` | MCP SERVER | Update config |

Documented grant set for an agent-backed server:

```sql
CREATE ROLE <mcp_access_role>;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE <mcp_access_role>;
GRANT USAGE ON WAREHOUSE <wh>                     TO ROLE <mcp_access_role>;
GRANT USAGE ON DATABASE <db>                      TO ROLE <mcp_access_role>;
GRANT USAGE ON SCHEMA <db>.<schema>               TO ROLE <mcp_access_role>;
GRANT USAGE ON MCP SERVER <db>.<schema>.<server>  TO ROLE <mcp_access_role>;
GRANT USAGE ON AGENT <db>.<schema>.<agent>        TO ROLE <mcp_access_role>;
GRANT SELECT ON SEMANTIC VIEW <db>.<schema>.<sv>  TO ROLE <mcp_access_role>;  -- agent's analyst tool
```

Troubleshooting: *tools not visible* → missing `USAGE` on the server. *Tool visible but
fails* → missing privilege on the underlying object.

---

## 5. Server definition (CoCo, B14)

```sql
CREATE OR REPLACE MCP SERVER SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_MCP
  FROM SPECIFICATION $$
  tools:
    - title: "Supply chain governed analytics"
      name: "supply-chain-agent"
      type: "CORTEX_AGENT_RUN"
      identifier: "SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT"
      description: "Answers supply chain KPI questions (OTD, fill rate, DOI, landed cost) using the governed semantic view."
  $$;
```

Tool types: `CORTEX_AGENT_RUN`, `CORTEX_ANALYST_MESSAGE` (semantic views only, not YAML
models), `CORTEX_SEARCH_SERVICE_QUERY`, `SYSTEM_EXECUTE_SQL` (`read_only` defaults to
`true`), `GENERIC` (UDF/proc).

### ✅ Docs back ADR-007 (two servers)

> "Snowflake generally recommends exposing a Cortex Agent as the **only** client-facing
> tool on a given MCP server used for governed business questions. Exposing
> `SYSTEM_EXECUTE_SQL` on the same server allows the MCP client to **bypass the agent's
> semantic views, verified queries, and orchestration**; if direct SQL is required,
> expose it through a **separate MCP server with a dedicated least-privileged role**."

That is ADR-007 almost word for word. Quote it in the README and talking points (C05).

---

## 6. Client wiring

Any client that supports remote HTTP MCP servers can connect using the URL above. Documented
clients: Claude.ai / Claude Desktop (Settings → Connectors → custom connector, client
id + secret, redirect `https://claude.ai/api/mcp/auth_callback`), ChatGPT (Developer
mode connector), Cursor (`mcp.json` with `CLIENT_ID` / `CLIENT_SECRET`).

Raw JSON-RPC:

```http
POST /api/v2/databases/SUPPLY_CHAIN_FORGE/schemas/SEMANTIC/mcp-servers/SUPPLY_CHAIN_MCP
Accept: application/json, text/event-stream

{"jsonrpc":"2.0","id":1,"method":"tools/list"}
{"jsonrpc":"2.0","id":2,"method":"tools/call",
 "params":{"name":"supply-chain-agent","arguments":{"message":"What is our fill rate?"}}}
```

**INFERRED**: the documented `arguments` shape (`{"message": "..."}`) is shown for the
Analyst tool. The Agent tool's argument name isn't shown on this page. Read it from the
`inputSchema` returned by `tools/list`.

### Network policies
If the account has network policies, allow the MCP client provider's **outbound IPs**
(the request comes from the provider's infrastructure, not the user's browser). A block
can show up as `invalid_client` from `/oauth/token-request`.

---

## 7. Rules carried over from the task queue

- Never ask the user to paste a token into chat. Store it via `/secrets`.
- Never bind a PAT to `ACCOUNTADMIN`. Use `FORGE_MCP_READER` (B07c) if it's ever built.
