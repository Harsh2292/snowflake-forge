# Claude Code Task Queue

> **Replanned 2026-09-29 (user-approved)** by CoCo, with the user's permission to edit this
> file once. Claude Code owns it from here on.
>
> **Progress:** C01 ✅ · C02 ✅ · C03 ✅ · C04 ✅ · C07 ✅ · C6a ✅ · C09 ✅ · C08 ✅
> DONE (B08c) · C6a re-checked after B08c · C10 ✅ READY (handoff lock, B12) · C11 ✅ READY (handoff lock, B10) · C12 ✅ READY (handoff lock, B13). Remaining, in order:
> **C6b ✅ → C6c ✅ → C13 ✅ → C14 ✅ → C05**. Live status is
> in `.agents/NEXT.md`; each track's detail goes in its card under `.agents/tasks/claude/`
> (write the card at planning time, before building, as always).
>
> **Goal of the replan:** finish in 3 days, production-ready and deployed. The core system
> (question → agent → semantic view → SQL → governed data → answer) must stay correct, fast
> and cheap from today's data to billions of rows, and while data changes.
>
> **What changed for you:** you now write **everything that can be written offline,
> including Snowflake SQL**: the realistic data generator, the data-quality SQL, the agent's
> data-health tool, the evaluation set, the scale harness. CoCo runs it and returns the
> results. You still have **no Snowflake access** and never need any.
>
> Read `docs/CONTRACT.md` (your spec), `docs/DATA_SPEC.md` (the spec for all your SQL,
> written by CoCo at B08b), and `docs/references/snowflake_execution_notes.md` (how CoCo
> runs your files) before starting any SQL track.

---

## Ownership

| You own | CoCo owns (read only for you) |
|---------|-------------------|
| `app/**`, `tests/**` (incl. `tests/scale/`), `demo/**`, `deploy/**`, `.github/**` | `sql/**`, `semantic/**`, `agent/**` |
| `docs/references/**`, `README.md` | `docs/artifacts/**` (incl. `runs/`) |
| **`data_gen/**`** (C08), **`quality/**`** (C10), **`eval/**`** (C11) | `docs/CONTRACT.md` (you may only append a Change Request in §11), `docs/DATA_SPEC.md`, `docs/HLD.md`, `docs/LLD.md`, `docs/ROADMAP.md`, `docs/MILESTONES.md` |
| `.agents/tasks/CLAUDE_TASKS.md`, `.agents/tasks/claude/**`, `CLAUDE.md` | `.agents/tasks/COCO_TASKS.md`, `.agents/tasks/coco/**`, `COCO.md` |

Shared, **your section only**: `.agents/NEXT.md`, `.agents/HANDOFF.md`,
`docs/SESSION_LOG.md` (your own entries), `.agents/DECISIONS.md`.

**You may never execute anything against Snowflake.** You write the SQL; CoCo runs it.

---

## How your Snowflake SQL gets run (the handoff lock)

1. **Write** the file in your folder, following `docs/DATA_SPEC.md` and
   `docs/references/snowflake_execution_notes.md`:
   - a header comment naming the card, the role and warehouse to run as, the parameters
     and the expected results
   - fully qualified names everywhere; idempotent (re-running gives the same result)
   - statements end with `;`; Snowflake Scripting blocks are fine
   - no `USE ROLE` outside a block: it doesn't carry over between statements in CoCo's tool
2. **Hand it over**: add a row to the **"Ready for CoCo to run"** table in
   `.agents/HANDOFF.md`: the file, the card, the order to run it in, and the expected results
   (row counts, rates, return shapes). From then on, **don't edit it**.
3. **CoCo runs it** and writes `docs/artifacts/runs/<card>_run.md`: each statement's
   outcome, verbatim errors, row counts, timings. CoCo may make **only run-blocking fixes of
   a few lines**, shown as a diff in that report.
4. **CoCo marks the row DONE or RETURNED.** The file is yours again: adopt any fix from the
   report, or fix what was returned and hand it over again.

---

## Remaining tracks, in order

### C09 — App production pass  ⬅ START NOW (Day 1–2)

The app has to survive realistic data and run live.
- [ ] `NULL` metric values render as "—" with a tooltip, never as `nan` or an error (fill
      rate for OPEN/CANCELLED orders is `NULL` by design, CR-005)
- [ ] Long results are limited or paged: dimensions like `orders.order_date` grow to about
      3,650 rows over 10 years. Charts show a sensible default window or grain.
- [ ] Show the **as-of date** of the data on every metric screen (the time rule comes in
      CR-006 at B08b)
- [ ] Remove `MCP_SERVER` from `app/utils/config.py` (MCP is dropped; CR-006 removes it
      from §1) and anything that refers to it
- [ ] Prepare `USE_MOCK_DATA = False`: every live branch works through the contract
      patterns, and mock fallback stays visible
- [ ] The Data health screen can show `SEMANTIC.SP_DATA_HEALTH` output (the shape is in
      `docs/DATA_SPEC.md` §Interfaces) next to the DMF results
- [ ] Keep `app/environment.yml` in step with `app/requirements.txt`
- **Gate**: `pytest -q` and `pytest -m ui` green; screenshots show `NULL` handling and the
  as-of date

### C08 — Realistic data generator  ⬅ CRITICAL PATH (Day 1, READY by end of day)

**Input:** `docs/DATA_SPEC.md` (B08b), `docs/references/snowflake_data_generation.md`,
`docs/references/snowflake_execution_notes.md`, LLD §2 (today's source columns).

- [ ] Seeded SQL scripts in `data_gen/` that fill the source tables (`ERP_SOURCE`,
      `WMS_SOURCE`, `TMS_SOURCE`, `SRM_SOURCE`) with **10 years of realistic data ending
      today**, as the spec describes:
  - `data_gen/00_params.sql`: `SCALE_FACTOR`, the seed, the end date (session variables)
  - one script per stage, in the spec's FK load order (masters → orders and lines →
    shipments → inventory → FX rates)
  - a **separate mess-injection script**, so clean vs messy is easy to check
  - `data_gen/90_self_checks.sql`: row counts per table, each injected defect's actual
    rate against its target, and the ERP/TMS date-conflict rate
- [ ] **Deterministic**: the same seed and scale factor give the same data, every run
- [ ] **Scales linearly**: `SCALE_FACTOR` multiplies transactional volumes, not master
      data counts, beyond what the spec says. It must run at 100M+ order lines on a larger
      warehouse (B13).
- [ ] **Realistic**: seasonality, growth, carrier and supplier churn, regional mix, as the
      spec describes. After CoCo's cleansing, the 4 canonical metrics must land inside the
      §3 ranges.
- [ ] Hand over under the lock; CoCo runs it at B08c
- **Gate** (checked in CoCo's run report): every script runs; the self-checks match the
  spec's volumes and defect rates within the stated tolerance; a second run gives the same
  counts and checksums

### C10 — Data-quality SQL + the agent's data-health tool (Day 1–2)

**Input:** `docs/DATA_SPEC.md` (mess catalogue, §Interfaces),
`docs/references/data_metric_functions.md`, `docs/references/snowflake_scripting_procedures.md`,
`docs/references/agent_custom_tools.md`.

**✅ READY 2026-09-29** (card `.agents/tasks/claude/C10_data_quality.md`; the files are
`quality/00`–`40` + `99_run.sql`, driven by one check catalogue, `OPS.DQ_CHECKS`).
- [x] custom DMFs (`quality/10_custom_dmfs.sql`), including `DMF_OVERSHIP_COUNT` (the name
      the app expects), orphan lines, negative on-hand, test records, non-contract codes,
      cost outliers; missing promised dates use the system `NULL_COUNT`
- [x] system and custom DMFs attached to the right `SOURCE` and `CONFORMED` tables on a
      schedule (`quality/20_sp_attach_dmfs.sql`, `OPS.SP_ATTACH_DMFS`)
- [x] `SEMANTIC.SP_DATA_HEALTH(entity VARCHAR)`, exactly the signature and return shape in
      the spec (`quality/30_sp_data_health.sql`), plus the gate as a procedure
      (`quality/40_sp_dq_self_checks.sql`)
- [x] Handed over under the lock; CoCo runs it at B12 and attaches the tool at B10
- **Gate** (CoCo's run report): the DMFs attach; results appear; `SOURCE` shows the
  injected defects and `CONFORMED` doesn't; `SP_DATA_HEALTH` returns the spec shape for
  every entity

### C11 — Evaluation set + runner (Day 1–2)

**Input:** `docs/DATA_SPEC.md` §Interfaces (the file format), `docs/references/agent_evaluations.md`,
`docs/references/data_agent_run.md`, contract §3, §4, §9.

- [ ] `eval/questions.*` (format per the spec), about 25–30 questions, each with a category,
      the expected behaviour (answer / refuse / clarify), a **ground-truth `SEMANTIC_VIEW`
      query** (not a hard-coded number, so it stays right when the data changes) and a
      tolerance. Cover:
  - the 8 §9 canonical questions
  - record lookups, counts and totals, supplier performance, inventory health, cost
    breakdown, cross-system, revenue
  - numbered multi-part questions
  - out-of-scope (must refuse), ambiguous (must clarify), and Hindi (GAP-5)
- [ ] `eval/run_eval.sql`: runs every question through `DATA_AGENT_RUN`, runs its ground
      truth, and returns one row per question (answer, generated SQL, pass/fail, latency)
- [ ] Optionally, `eval/agent_eval_config.*` for Snowflake's agent evaluations
      (`EXECUTE_AI_EVALUATION`), if the reference shows it fits
- [ ] Hand over under the lock; CoCo runs it at B10 → art 08
- **Gate**: CoCo runs it end to end and art 08 records a pass rate

### C6b — Reconcile the semantic layer (Day 2)

Unchanged in purpose, but **wait for the re-captured art 05/06** (B09, on the new data).
- [ ] Replace `MOCK_METRICS` and `MOCK_BY_REGION` with the real captured values
- [ ] Confirm output column naming matches your live branches
- [ ] Use `05_metric_values.json` as the fixture for `tests/semantic/`; rows inside each
      pairing aren't sorted, so sort by the dimension first
- **Gate**: `pytest -q` green on the new fixtures; zero unexplained mismatches

### C12 — Scale-test harness (Day 2)

**Input:** `docs/DATA_SPEC.md` §Interfaces (harness inputs and outputs), contract §3–§5.

- [ ] `tests/scale/scale_queries.sql`: the 4 metrics, the 55 valid pairings, the
      `SP_METRICS_AS_*` calls, and a few evaluation questions, parameterised by the database
      name (CoCo runs it on a zero-copy clone)
- [ ] Timing and pruning capture (elapsed time, partitions scanned vs total) from query
      history for those queries
- [ ] `tests/scale/report_template.md`: what art 12 should contain
- [ ] Hand over under the lock; CoCo runs it at B13 → art 12
- **Gate**: CoCo runs it on the clone and art 12 is filled

### C6c — Agent parser + proof grid (Day 2)

- [ ] Write the `ask_agent()` response parser against `07_agent_response.json`: answer
      text, generated SQL, tool used, citations, and the data-health tool output when present
- [ ] Correct `docs/references/data_agent_run.md` if the real JSON differs (the artifact is
      ground truth)
- [ ] Use `09_consistency_proof.json` (now from B09) for the proof grid
- [ ] Use `08_agent_answers.md` (the whole evaluation set) for Ask-screen tests
- [ ] Flip `USE_MOCK_DATA = False` for the deployed app (CoCo deploys at B15)
- **Gate**: parsers written against real data; `pytest -q` green with artifacts as fixtures

### C13 — Live-test refresh for the audit (Day 2–3)

CoCo runs `pytest -m live` at B14 as the contract audit.
- [ ] Update the live tests for the new data and CR-006: new §3 texts, value ranges, the
      new objects (`SP_DATA_HEALTH` shape; the extra semantic-view content being additive)
- [ ] Make sure it runs with only `SNOWFLAKE_CONNECTION_NAME` set and Snowpark installed;
      document the exact command in `tests/README` or the card
- [ ] Hand over under the lock
- **Gate**: CoCo's run gives a clear pass/fail per contract section; failures name the object

### C05 — Demo script, talking points, README, core-scalability doc (Day 3)

The card is already written (`.agents/tasks/claude/C05_demo_readme.md`); update it for the
replan.
- [ ] `demo/demo_script.md`: a timed 5-minute run over the real app screens, with the
      exact questions and the real numbers from the final artifacts
- [ ] `demo/talking_points.md`: one crisp answer per judging criterion
- [ ] `README.md`: architecture, how it runs, the four-source-system story, the core
      scalability design (art 12), the evaluation pass rate (art 08)
- [ ] The core-scalability doc (the prompt the user gave you)
- **Gate**: a stranger can follow `demo_script.md` and reproduce the demo on the deployed app

### C14 — Parallel multi-part router + KPI shortcut ✅ DONE 2026-09-30 (offline gate)

- [x] Multi-part questions split on clear boundaries (`app/utils/router.py`); agent parts
      run at once (a thread pool on the thread-safe Snowpark session), one card per part, in
      the order asked
- [x] KPI questions and sub-questions go straight to `SEMANTIC_VIEW`, with no LLM
- [x] CoCo's ask: "Ask is paused" when the Cortex budget revokes USAGE on the agent
- **Gate**: the card's gate (0 false shortcuts on art 08's 30; parallel ≈ the slowest part).
  The live timing is at B15a. Detail: `claude/C14_router_kpi_shortcut.md`

---

## Done tracks (history)

### Track C1 — API Reference Library ✅

Built a local reference folder of fetched docs (`docs/references/`): SiS, Snowpark
session, `SEMANTIC_VIEW`, `DATA_AGENT_RUN`, MCP client setup (now obsolete: MCP is
dropped), Plotly. Each file carries its source URL and date. Findings are in
`docs/references/README.md`.

### Track C2 — Data Access Layer ✅

`app/utils/config.py` (contract copied verbatim, `USE_MOCK_DATA`) and
`app/utils/forge_data.py` (the only module that talks to Snowflake; every function has a
mock and a live branch, and live failures degrade to mock with a visible warning).

### Track C3 — Streamlit App ✅

Built as a guided four-step story plus Explore and Data health screens (user-approved
design, replacing the five tabs of the original spec). Detail in
`.agents/tasks/claude/C03_streamlit_app.md`.

### Track C4 — Test Suite ✅

Unit and contract tests on mock data, `[live]` variants that skip without Snowflake, and a
browser suite (`pytest -m ui`). Detail in `.agents/tasks/claude/C04_tests.md`.

### Track C6a — Governed layer ✅

Art 03/04 reconciled with 0 mismatches. **Re-check after B08c** (art 03/04 are re-captured
on the new data; the columns and masking must not change).

### Track C07 — CI + one-command deploy ✅

`.github/workflows/tests.yml` and `deploy/deploy_app.py`. CoCo deploys with it at B15.

---

## Protocol

1. Update `.agents/HANDOFF.md` under `## Latest from Claude Code` when you finish a track
2. Append to `docs/SESSION_LOG.md` when you stop work
3. Never edit `docs/CONTRACT.md` except to append a Change Request
4. Never run anything against Snowflake; hand SQL over through the lock
5. Do not commit or push — the user does that
