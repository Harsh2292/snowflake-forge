# API Reference Library

> Owner: Claude Code (Track C1)
>
> Fetch real documentation into this folder. Do not write these from memory — stale API
> knowledge is the main source of wasted cycles later.
>
> Each file must carry its source URL and the date fetched.

## Required files

| File | Covers | Priority |
|------|--------|----------|
| `data_agent_run.md` | `SNOWFLAKE.CORTEX.DATA_AGENT_RUN()` — signature, request JSON, **response JSON shape** | **HIGHEST** — the app cannot render answers without the response structure |
| `semantic_view_query.md` | `SEMANTIC_VIEW()` construct: clause order, output column naming, granularity rules | HIGH |
| `streamlit_in_snowflake.md` | SiS specifics: `get_active_session()`, supported widgets, `CREATE STREAMLIT` | HIGH |
| `snowpark_session.md` | `Session.sql()`, `.collect()`, `.to_pandas()`, parameter binding | MEDIUM |
| `mcp_client_setup.md` | Connecting an MCP client to a Snowflake-managed MCP server | OBSOLETE (MCP dropped 2026-09-29, ADR-008) |
| `plotly_streamlit.md` | Chart patterns actually used in the app | LOW |

### Context pack for the SQL tracks (added by CoCo at B08b, 2026-09-29; Claude Code owns them now)

| File | Covers | Used by |
|------|--------|---------|
| `snowflake_execution_notes.md` | **How CoCo runs your SQL**, live-verified: session state not kept between calls, compile-only doesn't check procedure bodies, the determinism recipe, the time-window patterns, query history and pruning | C08, C10, C11, C12 (read first) |
| `snowflake_data_generation.md` | `GENERATOR`, `SEQ*` (gaps), `RANDOM`/`UNIFORM` (not reproducible), `HASH`, the deterministic recipe, bulk inserts, constraint enforcement | C08 |
| `snowflake_scripting_procedures.md` | Blocks, binding, `IDENTIFIER`, `EXECUTE IMMEDIATE`, `RESULTSET`, cursors, `RETURNS TABLE` vs `VARIANT`, owner's vs caller's rights, exceptions | C08, C10, C11, C12 |
| `data_metric_functions.md` | System and custom DMFs, schedules, attaching to tables/views/dynamic tables, `DATA_QUALITY_MONITORING_RESULTS`, privileges | C10 |
| `agent_custom_tools.md` | `CREATE AGENT` spec, tool types, a stored procedure as a `generic` tool (`tool_resources`: `type: procedure`, `identifier` with argument types) | C10 (`SP_DATA_HEALTH`), C6c |
| `agent_evaluations.md` | Native agent evaluations (dataset format, `EXECUTE_AI_EVALUATION`, metrics) and a `DATA_AGENT_RUN`-based runner | C11 |
| `snowpark_async.md` | `collect_nowait`, `AsyncJob`, running N queries concurrently and merging in order | C14 |

The spec these serve is `docs/DATA_SPEC.md` (CoCo-owned).

## Status — C01 complete (2026-09-24)

All six files written from docs fetched on 2026-09-24 (raw `.md` pages from
docs.snowflake.com, HTML for Snowpark API / Streamlit / Plotly). Anything not stated in
the docs is marked **INFERRED** in the file.

### Findings that change downstream work

| # | Finding | File | Affects |
|---|---------|------|---------|
| 1 | **Contract §6a confirmed.** SiS `CURRENT_ROLE()` = app owner; owner's-rights procs run as their owner wherever they're called from. No Change Request. | `streamlit_in_snowflake.md` §1 | — |
| 2 | §6a only holds if masking policies use `CURRENT_ROLE()` / `IS_ROLE_IN_SESSION()`, **not `INVOKER_ROLE()`** (through a view it returns the view owner). Persona roles must not inherit each other. | `streamlit_in_snowflake.md` §1 | CoCo B06 |
| 3 | The Analyst `tool_result` JSON fields are **not formally documented**. Field names inferred from the streaming delta schema; `verified_query_used` is a lineage signal worth showing. | `data_agent_run.md` §6 | C6c (artifact 07) |
| 4 | `to_pandas()` after `session.sql()` only works for `SELECT`. Persona `CALL`s must use `.collect()`. | `snowpark_session.md` §3–4 | C02 |
| 5 | SiS warehouse runtime needs **`environment.yml`** (Conda) at the source root, not `requirements.txt`. Entrypoint must be at the root. | `streamlit_in_snowflake.md` §6 | C03, B15 |
| 6 | Pin **Streamlit 1.52.2** (newest supported in SiS). Use `st.plotly_chart(width="stretch")`; `use_container_width` is deprecated. | `plotly_streamlit.md` §1–2 | C03 |
| 7 | Snowflake's MCP docs recommend a separate MCP server for `SYSTEM_EXECUTE_SQL`, which is what ADR-007 says. Quote it in the README. | `mcp_client_setup.md` §5 | C05 |
| 8 | Semantic-view granularity error is `010234`. Use it as the assertion in the `days_of_inventory × orders.*` test. | `semantic_view_query.md` §3 | C04 |

## Source URLs

- DATA_AGENT_RUN — <https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-run>
- SEMANTIC_VIEW — <https://docs.snowflake.com/en/sql-reference/constructs/semantic_view>
- Streamlit in Snowflake — <https://docs.snowflake.com/en/developer-guide/streamlit/about-streamlit>
- Snowpark Python — <https://docs.snowflake.com/en/developer-guide/snowpark/reference/python/latest/index>
- Managed MCP server — <https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp>

## Tip

`cortex search docs "<query>"` returns Snowflake documentation with Markdown URLs. Use
`web_fetch` on the `.md` URL to get the full page when a result is truncated.
