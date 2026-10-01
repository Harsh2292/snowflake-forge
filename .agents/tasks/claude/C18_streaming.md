# C18 — Stream the agent's answer (CR-008, contract v1.7 §5.3b)

| | |
|---|---|
| **Owner** | Claude Code (app only); CoCo checks it live |
| **Milestone** | 1 Oct, before C05 (the user: "do streaming first, after that we will do C05") |
| **Prerequisite** | CR-008 accepted (v1.7); C6c (parser), C14 (router, limits) |
| **Writes** | `docs/references/agent_run_rest.md`, `app/utils/forge_data.py`, `app/ui/screens/ask.py`, `app/ui/theme.py`, `app/utils/config.py`, `.streamlit/secrets.toml.example`, `tests/unit/test_streaming.py` |
| **Status** | ✅ DONE 2026-10-01 (offline gate). Live gate: CoCo |

## Goal
The agent's answer appears as it's written, instead of after ~10 s of silence. The final
answer is the same as `DATA_AGENT_RUN`'s, and anything that fails falls back to it.

## Why
CR-008: p50 12.3 s, almost all of it LLM time (writing 5.1 s, suggestions 3.7 s, planning
2.0 s; SQL 0.07 s). Streaming doesn't shorten the total, but the first words show in a second
or two.

## As built
- **Reference first:** `docs/references/agent_run_rest.md`, fetched from the official pages:
  - the endpoint, the body (`stream` defaults to true)
  - the 16 SSE event names and their data shapes, and the final `response` event
  - the auth methods
  - the connector session-token header Snowflake's own Streamlit examples use
- **`forge_data`:**
  - `sse_events` (the wire format)
  - `assemble_stream`: deltas go to `on_text`; the final `response` event is the whole
    answer, else it's rebuilt from the completed blocks; an `error` event raises
  - `_stream_live`: `POST …/agents/SUPPLY_CHAIN_AGENT:run` with
    `Authorization: Snowflake Token="<session.connection.rest.token>"`, i.e. the app's
    key-pair session, no second login
  - `ask_agent_stream`: parses with the same `parse_agent_response`. Any failure (no token, an
    HTTP error, an error event, the network) falls back to `ask_agent` (§5.3); "does not
    exist or not authorized" is "Ask is paused"; mock mode doesn't stream
- **Ask:**
  - a single agent part streams on the main thread into the thinking card ("Writing the
    answer", redrawn at most every 80 ms), then the full answer card replaces it
  - several agent parts still run in parallel, unstreamed
  - limits: one reservation per part, so the fallback stays inside it, counted once
  - cache, router and "paused" are unchanged
- **Off switch:** `[forge] stream = false`.
- **Tests (14):**
  - the SSE parser
  - an event fixture built from the real art 07 response: same answer, SQL, tools, tables and
    suggestions as §5.3; the deltas join to the text
  - a rebuild when the final event is missing
  - error and empty streams
  - the request (URL, token header, body)
  - three fallbacks, paused, no token, mock
  - the Ask flow: one part streamed and counted once; two parts parallel; the switch

## Added the same day (the user: "we can do both")
- **A "Stream answers" switch on the Ask screen** (per visitor, default on). It shows only when
  live and not switched off in secrets.
- **A Stop button under a streaming answer.**
  - The click ends the run: Streamlit's rerun is a `BaseException`, so it isn't caught by
    the fallback, and a test guards that.
  - What was written so far is kept as a "Stopped before the answer was finished." answer.
  - The question was already counted against the limits.
  - The agent may finish server-side; that cost can't be recalled.
- **The agent's progress messages** (`response.status`, e.g. "Planning the next steps…") replace
  the generic thinking line until the text starts.
- **Asked CoCo (HANDOFF) for response-format instructions:** plain sentences, **bold** numbers,
  no headings, links, code or pipe tables, the first sentence complete on its own, no tool
  names.
- 19 streaming tests.

## Gate
- [x] `pytest -q` 0 failures (19 streaming tests); Ask browser tests 10/10; the streaming card and
      the Stop button checked in screenshots
- [ ] Live (CoCo): the session-token header is accepted under `FORGE_APP_SVC_AUTH`; time to
      first text; the final answer equals `DATA_AGENT_RUN`'s on the 8 canonical questions. If
      the token is refused, the log shows
      `forge[…]: streaming the agent failed, using DATA_AGENT_RUN: HTTP 401…` and CoCo adjusts
      the policy (CR-008)

## Notes
- The 8 suggested questions take the instant path (C14), so they never reach the agent or the
  stream. CoCo's live check needs the shortcut off for those (`[forge] shortcut = false`), or
  free-text questions.
- SiS (warehouse runtime) can't reach the agents REST API, so it always uses §5.3.
