# Claude Code Task Queue

> **Progress (2026-09-24):** C1 ✅ · C2 ✅ · C3 ✅ · next: C4. Live status is in
> `.agents/NEXT.md`, and each track's detail (including what changed from the spec below)
> is in its card under `.agents/tasks/claude/`. C3 was built as a guided four-step story
> plus Explore and Data health screens, replacing the five tabs described below
> (user-approved design).
>
> Owner: Claude Code (application layer + references + docs)
> **You are NOT blocked.** Start at C1 immediately.
>
> Read `docs/CONTRACT.md` first — it is frozen and it is your spec. Build against it,
> not against live Snowflake objects. A mock layer lets you finish the entire app before
> CoCo's Snowflake work lands.

---

## Ownership

| You own | You must NOT touch |
|---------|-------------------|
| `app/**` | `sql/**` |
| `tests/**` | `semantic/**` |
| `demo/**` | `agent/**` |
| `docs/references/**` | `docs/HLD.md`, `docs/LLD.md`, `docs/CONTRACT.md` |
| `README.md` | `.agents/tasks/COCO_TASKS.md` |

**You may never execute DDL or DML against Snowflake.** CoCo owns every Snowflake
object. If you need one, file a request in `.agents/HANDOFF.md` under `## Blocked`.

---

## Track C1 — API Reference Library  ⬅ START HERE

Build a local reference folder so you are not guessing at APIs later. Fetch the real
docs; do not write these from memory.

- [ ] Create `docs/references/`
- [ ] `streamlit_in_snowflake.md` — SiS specifics: `get_active_session()`, supported
      widgets, what differs from local Streamlit, deployment via `CREATE STREAMLIT`
      <https://docs.snowflake.com/en/developer-guide/streamlit/about-streamlit>
- [ ] `snowpark_session.md` — `Session.sql()`, `.collect()`, `.to_pandas()`, parameter
      binding, error handling
      <https://docs.snowflake.com/en/developer-guide/snowpark/reference/python/latest/index>
- [ ] `semantic_view_query.md` — the `SEMANTIC_VIEW()` construct: clause order, output
      column naming, `METRICS` vs `FACTS` vs `DIMENSIONS` rules, granularity constraints
      <https://docs.snowflake.com/en/sql-reference/constructs/semantic_view>
- [ ] `data_agent_run.md` — `SNOWFLAKE.CORTEX.DATA_AGENT_RUN()` signature, request JSON
      shape, **response JSON shape** (you must parse this — capture the event/content
      structure precisely)
      <https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-run>
- [ ] `mcp_client_setup.md` — how to connect an MCP client to a Snowflake-managed MCP
      server: OAuth vs PAT, hostname rules (**hyphens not underscores**), tool discovery
      <https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp>
- [ ] `plotly_streamlit.md` — chart patterns you will actually use

**Gate**: each file contains real fetched content with a source URL and a date, not
paraphrase from memory. The `DATA_AGENT_RUN` response shape is the critical one — the
app cannot render answers without it.

---

## Track C2 — Data Access Layer (mock-backed)

One module is the only thing that ever touches Snowflake. Every UI component calls it.
Flipping one flag switches mock → live and the UI code never changes.

- [ ] `app/utils/config.py`
  - `USE_MOCK_DATA = True`
  - All FQNs, `PERSONA_ROLES`, `METRICS`, `MOCK_METRICS`, `MOCK_BY_REGION` copied
    verbatim from `docs/CONTRACT.md`
- [ ] `app/utils/forge_data.py` — every function has a mock branch and a live branch:
  - [ ] `get_session()`
  - [ ] `get_metric(metric_key, dimension=None, role=None) -> DataFrame`
  - [ ] `get_all_metrics(role=None) -> DataFrame`
  - [ ] `compare_across_personas(metric_key) -> DataFrame`
  - [ ] `get_masking_divergence(role) -> DataFrame`
  - [ ] `ask_agent(question, role=None) -> dict` → `{answer, sql, metric_used, raw}`
  - [ ] `get_naive_otd() -> float` (ERP-promised-date version, for Tab 3)
  - [ ] `get_governed_otd() -> float`
  - [ ] `get_source_schema_summary() -> DataFrame` (the four messy schemas)
  - [ ] `get_quality_results() -> DataFrame`
- [ ] Live branches build SQL strictly from `docs/CONTRACT.md` §5 patterns
- [ ] Every live branch wrapped so a failure degrades to mock with a visible warning,
      never a stack trace on stage

**Gate**: `get_all_metrics()` returns contract-shaped data in mock mode, and every
live-branch SQL string is present and syntactically correct even though unexercised.

---

## Track C3 — Streamlit App

Build the full UI against `forge_data.py`. It must be fully demoable in mock mode.

- [ ] `app/streamlit_app.py` — sidebar persona selector + 5 tabs

- [ ] **Tab 1 · Ask**
  - [ ] Free-text input plus 8 suggested-question chips from `CONTRACT.md` §9
  - [ ] Call `ask_agent()`, render the answer prominently
  - [ ] Expanders: generated SQL, metric definition applied, raw agent response
  - [ ] Caption naming the semantic view FQN that grounded the answer

- [ ] **Tab 2 · Consistency Proof**  ← the core claim, make it unmistakable
  - [ ] 4 metrics × 3 personas grid
  - [ ] Green check when all three match to 6 dp, red when not
  - [ ] Second table showing *expected divergence* — which columns each persona sees masked
  - [ ] One-line explanation: same metric definition, different data visibility

- [ ] **Tab 3 · The Problem**
  - [ ] Four source schemas with their cryptic column names side by side
  - [ ] Highlight `ERP.VBAK.ERDAT` vs `TMS.VTTK.PROM_DLV_DT` — both claim "promised date"
  - [ ] Naive OTD vs governed OTD, two different numbers, then the resolution
  - [ ] This tab earns the Real World Relevance score

- [ ] **Tab 4 · Metrics**
  - [ ] OTD by region, fill rate by category, DOI by plant, landed cost by region
  - [ ] Plotly charts, all sourced through `forge_data.get_metric()`
  - [ ] Respect the valid metric × dimension pairings in `CONTRACT.md` §4

- [ ] **Tab 5 · Data Quality**
  - [ ] Render `get_quality_results()`; show a neutral placeholder if DMFs aren't live yet

- [ ] Mock-mode banner so nobody mistakes mock numbers for real ones

**Gate**: app runs locally end to end in mock mode, all 5 tabs render, persona selector
changes the divergence table.

---

## Track C4 — Test Suite

Write the tests now. They are the executable form of the contract. They will fail until
CoCo delivers — that is correct and expected.

- [ ] `tests/consistency/test_cross_persona.py`
  - [ ] `test_otd_identical_across_personas`
  - [ ] `test_fill_rate_identical_across_personas`
  - [ ] `test_doi_identical_across_personas`
  - [ ] `test_landed_cost_identical_across_personas`
  - [ ] Compare at 6 decimal places
- [ ] `tests/governance/test_masking.py` — one test per row of `CONTRACT.md` §6
- [ ] `tests/semantic/test_metric_ranges.py` — each metric inside `CONTRACT.md` §3 range
- [ ] `tests/semantic/test_dimension_pairings.py` — every valid pairing returns rows;
      `days_of_inventory` × `orders.*` fails as expected
- [ ] `tests/conftest.py` — session fixture, role-switch fixture, skip-if-mock marker
- [ ] `pytest.ini` — markers `live` and `mock`

**Gate**: `pytest -m mock` green. `pytest -m live` collects without import errors and
skips cleanly while Snowflake objects are absent.

---

## Track C5 — Demo & Submission Docs

- [ ] `demo/demo_script.md` — rewrite to a timed 5-minute run, tab by tab, with the
      exact questions to type and the exact numbers to point at
- [ ] `demo/talking_points.md` — one crisp answer per judging criterion
- [ ] `README.md` — architecture diagram, what it does, how to run it, tech stack,
      the four-source-system story. Written for a judge skimming for 90 seconds.

**Gate**: a stranger can follow `demo_script.md` and reproduce the demo.

---

## Track C6 — Artifact-Based Verification  ⬅ three staged unlocks, no credentials needed

You have **no Snowflake access** and do not need any. CoCo runs the live queries and
commits the **real output** to `docs/artifacts/`. You verify against those files.

Read `docs/artifacts/README.md` for the full schedule. Watch `.agents/HANDOFF.md` — it
marks each artifact as it lands.

**You never edit files in `docs/artifacts/`.** CoCo owns them.

### C6a — Governed layer  (artifacts from CoCo **B7**, **B7b**)

| Artifact | Verify |
|----------|--------|
| `03_governed_columns.json` | All 9 views' real column names match `CONTRACT.md` §7 |
| `04_persona_outputs.json` | Real masked values match `CONTRACT.md` §6 exactly |

- [ ] Compare artifact contents against the contract, field by field
- [ ] Wire `get_masking_divergence()` to parse the real shape from `04_persona_outputs.json`
- [ ] Use the artifact as the fixture for `tests/governance/test_masking.py`
- [ ] Any mismatch → **Change Request** in `CONTRACT.md` §11. Never adapt silently.

### C6b — Semantic layer  (artifacts from CoCo **B8**)

| Artifact | Verify |
|----------|--------|
| `05_metric_values.json` | All 4 metric values present and inside `CONTRACT.md` §3 ranges |
| `06_dimension_matrix.md` | Every valid metric × dimension pairing passed; `days_of_inventory` × `orders.*` failed as documented |

- [ ] Replace `MOCK_METRICS` and `MOCK_BY_REGION` with the **real** captured values
      — the demo then shows genuine numbers even in mock mode
- [ ] Confirm output column naming (unqualified, uppercased) matches what your live
      branches expect
- [ ] Use `05_metric_values.json` as the fixture for `tests/semantic/`

### C6c — Agent layer  (artifacts from CoCo **B10**, **B11**)

| Artifact | Verify |
|----------|--------|
| `07_agent_response.json` | ⭐ **The critical one.** A real, complete `DATA_AGENT_RUN` response. |
| `08_agent_answers.md` | All 8 canonical questions with actual answers and generated SQL |
| `09_consistency_proof.json` | 4 metrics × 3 personas, real values to 6 dp |
| `02_raw_metrics.md` | The two divergent OTD numbers for Tab 3 |

- [ ] Write the `ask_agent()` response parser against `07_agent_response.json`
      — extract answer text, generated SQL, tool used, citations
- [ ] Compare the real JSON against what you predicted in
      `docs/references/data_agent_run.md`. If they differ, **correct the reference file** —
      the artifact is ground truth.
- [ ] Use `09_consistency_proof.json` as the fixture for the Tab 2 proof grid
- [ ] Use `02_raw_metrics.md` for the Tab 3 naive-vs-governed comparison

**Gate for C6**: every artifact reconciled against the contract, all parsers written
against real data, `pytest -m mock` green using artifacts as fixtures, zero unexplained
mismatches.

### Deployment

Deploying to Streamlit in Snowflake requires Snowflake write access, which you do not have.
CoCo deploys the app at **B15**. Your job is to make `app/streamlit_app.py` correct and
deployable. Flag it as ready in `.agents/HANDOFF.md`.

### If artifacts prove insufficient

If you genuinely cannot verify something from a file — say the agent response varies in a
way one capture does not reveal — say so explicitly in `.agents/HANDOFF.md` under
`## Blocked`, naming exactly what you need. Options are then: CoCo captures more artifacts,
or the user provisions a read-only PAT (CoCo's deferred B7c). Do not guess.

---

## Protocol

1. Update `.agents/HANDOFF.md` under `## Latest from Claude Code` when you finish a track
2. Append to `docs/SESSION_LOG.md` when you stop work
3. Never edit `docs/CONTRACT.md` except to append a Change Request
4. Never run DDL/DML against Snowflake
5. Do not commit or push — the user does that
