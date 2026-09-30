# C6c — Ask works live: the CR-007 call and the parser checked against the real agent

| | |
|---|---|
| **Owner** | Claude Code (offline, no Snowflake); the live proof is CoCo's B15a |
| **Milestone** | Replan Day 2 (30 Sep). **Needed before B15a** (the gate: "Ask returns an agent answer") |
| **Prerequisite** | B10 ✅ (art 07 real response, art 08 all 30 evaluation answers), CR-007 ✅ accepted by the user 30 Sep, C6b ✅ |
| **Writes** | `app/utils/forge_data.py` (`build_agent_sql`, `ask_agent`), `app/utils/agent_response.py`, `app/ui/payloads.py` / `app/ui/screens/ask.py` (suggested follow-ups), `app/utils/mock_data.py` (mock agent in the real shape), `docs/references/data_agent_run.md`, `tests/conftest.py` (replay the agent), tests |
| **Status** | ✅ **DONE (offline gate)** 2026-09-30: approved by the user and built. `pytest -q` 487 passed (only the 3 queued C16 failures left), `pytest -m ui` 20/20. The live gate is CoCo's B15a |

---

## Goal

A question typed on the public link reaches the real Cortex Agent, and the answer card
shows exactly what the agent returned:
- a clean answer
- the SQL it ran, and whether a verified query was used
- the metric definition
- the result table and chart
- the agent's own follow-up suggestions

## Why

- **CR-007:** the app's current call is rejected by Snowflake, so every live question falls
  back to a saved answer. B15a would fail.
- **The parser was written from the docs, before any real response existed.** Checked
  against art 07 (30 Sep), it gets three things wrong:
  1. The answer text ends with the agent's SQL as a code block, so the card shows the SQL
     twice, once as raw markdown.
  2. "Tools used" shows Snowflake's internal `system_execute_sql`, not what happened: a
     verified query answered it.
  3. The result table is counted twice (once from the `table` item, once from the
     `tool_result`).
- The agent returns `suggested_queries`; the app ignores them today.

## Design

1. **CR-007 call:**
   - `build_agent_sql()` → `SELECT TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('<agent>', ?, TRUE)) AS response`
   - `ask_agent()` binds `json.dumps({"messages": [{"role": "user", "content": [{"type": "text", "text": question}]}]})`.
     `json.dumps` escapes quotes and newlines, so a question can't break out of the JSON.
   - The contract test compares with CR-007's block until CoCo moves §5.3 to v1.6, then
     with §5.3.
2. **Parser (`agent_response.py`)**, built from art 07 and the 30 answers in art 08:
   - answer = the text items, with fenced code blocks removed (the SQL is shown in its own
     panel), whitespace tidied
   - tables: prefer the `table` item, and don't count a `tool_result` result set with the
     same `query_id` again
   - tools: user-facing names. A verified query → "Verified query"; Analyst → "Cortex
     Analyst"; `data_health` → "Data health"; chart. Internal `system_*` tools are kept in
     the raw view only.
   - `suggested_queries` → a new `suggestions` list
   - the data-health tool's output (when the agent calls it) → shown as the answer's source
   - never raises: unknown items are skipped, as today
3. **Ask screen:** after a live answer, the "Try another" pills offer the agent's
   suggestions first, then the remaining suggested questions (at most 4). Each suggestion
   is a new agent call, so the C15 limits apply.
4. **Mock agent** (`mock_data.agent_response`) produces the real art 07 shape: a `table`
   item, the SQL in a trailing code block, `system_execute_sql`, `suggested_queries`. Mock
   mode then exercises the same parser paths as live.
5. **Replay tests:**
   - `ReplaySession` answers `DATA_AGENT_RUN` with art 07 and **checks the bound value is
     the CR-007 JSON**, so the whole live Ask path runs offline
   - art 08's 30 answers each parse and render an answer card with no error
   - refusals (Q30 etc.) render as text only, with no chart
6. **`docs/references/data_agent_run.md`:** replace the inferred field names with the real
   ones from art 07, and add the CR-007 constant-argument rule.

## Not in C6c
- The master-data freshness FAILs in `SP_DATA_HEALTH`, and Q30 / Q17 / E04 → the C10 / C11
  follow-up card (next).
- The proof grid already uses art 09 (done in C6b).

## As built (30 Sep)

**CR-007**
- `build_agent_sql()` = `DATA_AGENT_RUN('<agent>', ?, TRUE)`, and the new
  `agent_request(question)` builds the bound JSON with `json.dumps`.
- The contract test compares with CR-007's block now, and with §5.3 once CoCo moves it to
  v1.6. Comments are ignored in the comparison.
- `tests/scale/10_scale_queries.sql` was regenerated. **Only its 5 inactive AGENT rows
  changed** (now a string literal of the request JSON, which CoCo proved works). The file
  is in the handoff lock for B13; CoCo is told.

**Parser** (`agent_response.py`, header documents the real shape)
- **The answer:** prose only (the fenced ` ```sql ` block is removed; blank and whitespace
  lines collapsed; paragraphs kept).
- **The SQL:** the first distinct statement, whitespace-insensitive, also taken from the
  fenced block if no tool carried it.
- **Tables:** one per `query_id` (the `table` item wins and brings its `title`).
- **Tools:**
  - `tools_used` in words: "Verified query", "Cortex Analyst", "Chart", "Data health check"
  - internal `system_*` / `server_*` / `generic` are hidden
  - `tools_raw` keeps the originals
- **New fields:** `suggestions` (the agent's follow-ups), `data_health` (the tool's
  output), `table_titles`.

**Answer card**
- Light markdown (paragraphs, line breaks, `**bold**`; everything escaped first).
- The agent's chart title; tool chips; a data-health line when that tool ran.
- The height accounts for paragraphs.

**Ask screen:** "Try another" = the agent's suggestions first, then the canonical
questions not yet asked (at most 6). Each suggestion goes through the C15 limits.

**Mock agent:** now emits art 07's exact shape (system_execute_sql, a `table` item with a
title, a trailing ` ```sql ` block, `suggested_queries`), so mock mode runs the same parser
paths as live.

**Replay** (`tests/conftest.py`): `ReplaySession` now also answers:
- the agent call with art 07 (the bound value must parse as the CR-007 JSON; each request
  is recorded)
- `SP_DATA_HEALTH('ALL' | 'shipments')` and the DMF results from art 10

So the Data health screen replays **Live** too (`test_whole_app_runs_live…`: all three
screens Live, no banner).

**Tests:** `tests/artifacts/test_replay_agent.py` (35):
- the bound request is exactly `agent_request(question)`
- the card shows art 07's clean answer, SQL, "Verified query", one table titled by the
  agent, and 3 suggestions
- the Ask screen in live replay has no fallback banner, and the pills lead with the agent's
  follow-ups
- all 30 art 08 answers parse, stay JSON-safe and keep code blocks out of the answer; the
  refusals and clarifications render text only
- Q29 → "Data health check"

Also a test that `agent_request` survives quotes, newlines and backslashes.

**Deliberate break:** binding the bare question again (the pre-CR-007 form) made 3 replay
tests fail; restoring it gave 35 passed.

**Screenshot checked:** the answer card in mock mode shows real art 05 numbers, clean prose,
the "Verified query" chip and the suggestions pills.

## Steps
1. Tests first: the CR-007 SQL and the bound JSON; parser cases from art 07 / art 08.
2. `forge_data` CR-007; parser fixes; suggestions; the mock agent in the real shape.
3. Replay the whole live Ask path through AppTest; `pytest -m ui` (the answer card in both
   themes, suggestions pills).
4. Update the reference doc, then the records (card, NEXT, HANDOFF, SESSION_LOG).

## Gate
- [ ] The live Ask path, replayed with art 07: the bound request is the CR-007 JSON, the
      card shows a clean answer + SQL + "Verified query" + one table + chart +
      suggestions, and nothing falls back
- [ ] All 30 art 08 answers parse and render without error; the 3 refusals render text only
- [ ] `pytest -q` (only the 3 queued C10/C11 failures remain) and `pytest -m ui` green
- [ ] **Live (B15a, CoCo + user):** Ask on the public link returns an agent answer, with
      no banner
