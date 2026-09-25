# C01 — API Reference Library

| | |
|---|---|
| **Owner** | Claude Code |
| **Milestone** | M1 (parallel with CoCo's B01) |
| **Prerequisite** | None — you are not blocked |
| **Est. effort** | One session |
| **Writes** | `docs/references/*.md` |

---

## Goal

Build a local reference library of **real, fetched** Snowflake API documentation so later
cards are not written against stale recollection.

---

## Why this is first

The single most important unknown is the **`DATA_AGENT_RUN` response JSON shape**. The
app's entire "Ask" tab depends on parsing it: the answer text, the generated SQL, the tool
calls, the citations. Guessing that structure and discovering the mistake at C06 would
waste the most expensive part of the schedule.

---

## Steps

Fetch each page and write a distilled reference. **Do not write these from memory.**
Each file must carry its source URL and the date fetched.

### 1. `docs/references/data_agent_run.md` — HIGHEST PRIORITY

Source: <https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-run>

Must capture:
- Exact function signature of `SNOWFLAKE.CORTEX.DATA_AGENT_RUN()`
- Request JSON structure
- **Response JSON structure** — every field needed to extract: final answer text,
  generated SQL, which tool was used, any citations
- Error shapes and how failures present

### 2. `docs/references/semantic_view_query.md`

Source: <https://docs.snowflake.com/en/sql-reference/constructs/semantic_view>

Must capture:
- Clause ordering rules in a `SEMANTIC_VIEW()` query
- How output column names are derived (unqualified, uppercased)
- Granularity constraints — which dimension/metric combinations are legal
- That `FACTS` and `METRICS` cannot appear in the same clause

### 3. `docs/references/streamlit_in_snowflake.md`

Source: <https://docs.snowflake.com/en/developer-guide/streamlit/about-streamlit>
Also: <https://docs.snowflake.com/en/developer-guide/streamlit/object-management/owners-rights>

Must capture:
- `get_active_session()` usage
- **Owner's rights model** — why `CURRENT_ROLE()` returns the app owner
  (this is exactly why `docs/CONTRACT.md` §6a exists; confirm the mechanism)
- Warehouse runtime vs container runtime differences
- `CREATE STREAMLIT` deployment syntax
- Restrictions inherited from owner's-rights stored procedures

### 4. `docs/references/snowpark_session.md`

Source: <https://docs.snowflake.com/en/developer-guide/snowpark/reference/python/latest/index>

Must capture: `Session.sql()`, `.collect()`, `.to_pandas()`, parameter binding, `CALL`
for stored procedures, error handling.

### 5. `docs/references/mcp_client_setup.md`

Source: <https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp>

Must capture: client connection steps, OAuth vs PAT, **hostnames use hyphens not
underscores**, tool discovery, that `USAGE` on a server does not grant tool access.

### 6. `docs/references/plotly_streamlit.md`

Only the chart patterns actually needed: grouped bar, line over time, horizontal bar.

---

## Tip

`cortex search docs "<query>"` returns Snowflake docs with a Markdown URL. When a result
is truncated, `web_fetch` the `.md` URL for the full page.

---

## Gate

- All six files exist under `docs/references/`
- Each carries a source URL and fetch date
- `data_agent_run.md` documents the response JSON well enough to write a parser without
  opening a browser again
- `streamlit_in_snowflake.md` independently confirms the owner's-rights behaviour that
  `docs/CONTRACT.md` §6a depends on

---

## On completion

1. Tick C01 as ✅ in `.agents/NEXT.md` and set C02 as NEXT
2. Update `.agents/HANDOFF.md` → Latest from Claude Code
3. If `streamlit_in_snowflake.md` **contradicts** contract §6a, stop and file a Change
   Request in `docs/CONTRACT.md` §11 — do not proceed on a broken assumption
