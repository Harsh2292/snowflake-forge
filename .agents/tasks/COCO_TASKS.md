# CoCo Task Queue

> Owner: CoCo (Snowflake layer)
>
> **`docs/CONTRACT.md` is frozen and binding.** Every metric identifier, dimension
> identifier, view column name, role name, and FQN you create must match it exactly.
> If reality forces a deviation, file a Change Request in `CONTRACT.md` §11 and tell
> the user — do not silently rename anything. Claude Code is building against it in
> parallel right now.
>
> `docs/LLD.md` = exact specs. `docs/MILESTONES.md` = exit criteria.
> Mark `[x]` when the build step's **gate** passes, not when the SQL merely runs.
>
> **Replanned 2026-09-29 (user-approved).** Goal: finish in 3 days, production-ready and
> deployed. The core system must stay correct, fast and cheap from thousands to billions
> of rows, and while the data keeps changing. Only the infrastructure knobs change with
> scale. B01–B08 are unchanged history. Everything from B08b on is the new sequence.
> What comes after the hackathon, gated on customer demand, is in `docs/ROADMAP.md`.

---

## Core system rules (every card must keep these)

1. **Contract names are the fixed interface.** Whatever sits under the `GOVERNED` views
   (views, dynamic tables, materializations) can be swapped. The semantic view, agent and
   app must not notice.
2. **Clean data once, where it lands.** Dedupe, standardize codes, convert currency and
   apply the edge-case rules in the `CONFORMED` schema (incremental dynamic tables). Never
   clean at query time. When data changes, only the changed rows are refreshed.
3. **Masking lives only in the `GOVERNED` views** (§7 names and columns), keyed on
   `CURRENT_ROLE()`. Persona roles can't read `SOURCE` or `CONFORMED`.
4. **One semantic view is the only definition of every metric.** App, procedures and agent
   all read it. No metric uses a masked column (§6).
5. **Time is explicit.** One as-of rule and one default-window rule, identical for the app
   and the agent, so one question can't get two numbers.
6. **Results are bounded.** The agent uses top-N and limits; the app handles `NULL` values
   and pages long results.
7. **Paths are either deterministic or measured.** Metric and procedure paths are exact.
   The agent path is bounded by instructions, verified queries and a standing evaluation
   set with a recorded pass rate.
8. **Scale knobs change only speed and cost**: warehouse size, multi-cluster, clustering,
   materialization, caching. B13 proves it.
9. **Cost is controlled by design**: auto-suspend, result cache, a resource monitor and
   query tags. Known KPIs are answered without the LLM.

---

## Plan at a glance (3 days)

**Deadline: submission 4 Oct 2026; everything done by end of 2 Oct.** Day 1 = 29 Sep,
Day 2 = 30 Sep, Day 3 = 1 Oct, 2 Oct = buffer, fixes, rehearsal and the video.

Split re-done on 2026-09-29 (user-approved): **Claude Code writes everything that can be
written offline, including Snowflake SQL. CoCo runs it, owns the core design, and does
everything that needs live Snowflake.** Claude Code's queue is
`.agents/tasks/CLAUDE_TASKS.md` (C08–C14).

| Day | CoCo | Claude Code |
|---|---|---|
| **1** | **B08b** data spec + CR-006 + context pack (reference files) | **C09** app production pass (starts now) |
| 1 | **B09** semantic view v2, by hand, on today's data | **C08** data generator (as soon as `docs/DATA_SPEC.md` lands) |
| 1 | **B09a** metadata-driven generator + name search | **C10** data-quality SQL + `SP_DATA_HEALTH`; **C11** evaluation set + runner |
| **2** | **B08c** run C08; `CONFORMED` layer; re-point the governed views (with role tags); regenerate the view; art 03/04 again | C09 (continued) |
| 2 | **B09 captures**: art 05, 06, 09 | **C6b** (after art 05/06) |
| 2 | **B12** run C10 → art 10 | **C12** scale-test harness |
| 2 | **B10** agent (Analyst + chart + data-health tool); run C11 → art 07, 08 | **C6c** (after art 07–09); **C13** live-test refresh |
| 2 | **B08m trial move**: baseline replay in the new event account | — |
| **3** | **B13** run C12 on a clone → art 12 (old account) | **C05** demo, README, core-scalability doc |
| 3 (end) | **B08m cutover** to the new account | fixes from the run reports |
| **2 Oct** | **B14** run C13 (`pytest -m live`) + security review → art 11 (new account) | fixes from the run reports |
| 2 Oct | **B15** cost controls + deploy (new account) | **C14** stretch: parallel router + KPI shortcut |

Critical path: **B08b → C08 → B08c → regenerate → B09 captures → B10 → B15**. C08 must be
READY by the end of Day 1.

**Account switch (user-approved 2026-09-29; detail in `COCO.md`, "Account switch plan").**
- Build in the old account (`DA53081`) until the end of Day 3 (1 Oct), including the B13
  scale proof (its art 12 doesn't depend on the account).
- **B08m trial move on Day 2** (30 Sep): replay the v1 baseline in the new event account.
- **B08m cutover at the end of Day 3**, or sooner if the old balance drops below ~$60.
- **2 Oct runs in the new account only:** B14 and B15 (moved from Day 3), an eval smoke run,
  final artifacts.
- Until then every object must be a re-runnable repo script. Nothing is built by hand.

---

## Working with Claude Code (no collisions)

**1. One owner per file or folder.** Neither agent edits the other's files.

| Owner | Files and folders |
|---|---|
| **CoCo** | `sql/`, `semantic/`, `agent/`, `docs/artifacts/` (incl. `runs/`), `docs/CONTRACT.md` (Claude Code may only append a CR in §11), `docs/DATA_SPEC.md`, `docs/HLD.md`, `docs/LLD.md`, `docs/ROADMAP.md`, `docs/MILESTONES.md`, `.agents/tasks/COCO_TASKS.md`, `.agents/tasks/coco/`, `COCO.md` |
| **Claude Code** | `app/`, `tests/` (incl. `tests/scale/`), `demo/`, `deploy/`, `.github/`, `docs/references/`, `README.md`, **`data_gen/`**, **`quality/`**, **`eval/`**, `.agents/tasks/CLAUDE_TASKS.md`, `.agents/tasks/claude/`, `CLAUDE.md` |
| Shared, own section only | `.agents/NEXT.md`, `.agents/HANDOFF.md`, `docs/SESSION_LOG.md` (own entries), `.agents/DECISIONS.md` |

**2. Handoff lock for Claude Code's Snowflake SQL.**
1. Claude Code adds the file to the **"Ready for CoCo to run"** table in `.agents/HANDOFF.md`,
   with the expected results, and stops editing it.
2. CoCo compiles it (`only_compile`), runs it with the role and warehouse the card names, and
   writes `docs/artifacts/runs/<card>_run.md`: the outcome of every statement, verbatim
   errors, row counts and timings.
3. CoCo may fix **only what blocks the run** (a few lines), shown as a diff in the run
   report. Anything bigger goes back to Claude Code.
4. CoCo marks the row DONE or RETURNED. Either way, the file is Claude Code's again.

**3. Interfaces are fixed before code.** `docs/DATA_SPEC.md` and CR-006 fix the source
tables, the mess catalogue, the rules, and the names and signatures of every new object.
Claude Code builds to them; CoCo doesn't change them without telling Claude Code in HANDOFF.

**4. Context for Claude Code.** At B08b, CoCo writes reference files into
`docs/references/`, fetched from Snowflake docs, dated and with sources. Claude Code owns
them afterwards. They cover data generation, DMFs, scripting procedures, agent custom tools,
agent evaluations, Snowpark async, plus CoCo's live-verified execution notes.

---

## M1 — Data Foundation

### B1 — Database & Schemas
- [x] Write `sql/01_setup/01_database.sql`
- [x] Create `SUPPLY_CHAIN_FORGE` database
- [x] Create 7 schemas: `ERP_SOURCE`, `WMS_SOURCE`, `TMS_SOURCE`, `SRM_SOURCE`, `GOVERNED`, `SEMANTIC`, `APP`
- [x] Create `FORGE_WH` — XSMALL, auto-suspend 60s, auto-resume true
- [x] **Gate**: `SHOW SCHEMAS IN DATABASE SUPPLY_CHAIN_FORGE` returns 7 (+ INFORMATION_SCHEMA)

### B2 — Roles & Grants
- [x] Write `sql/01_setup/02_roles_grants.sql`
- [x] Create `FORGE_ADMIN`, `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE`
- [x] Grant usage on database + schemas + warehouse to each role
- [x] Grant `SNOWFLAKE.CORTEX_AGENT_USER` to roles that will call the agent
- [x] **Grant to the current user's DEFAULT role** — agents use default role, not session role
- [x] Grant `CREATE SEMANTIC VIEW` and `CREATE AGENT` on `SEMANTIC` schema
- [x] **Capture artifact** `docs/artifacts/01_default_role.md` — default role + warehouse
- [x] **Gate**: `SHOW GRANTS TO ROLE <each>` shows expected privileges

### B3 — Source Tables
- [x] Write `sql/02_tables/01_srm_source.sql` — `LFA1`, `MARA`, `SOURCING`
- [x] Write `sql/02_tables/02_wms_source.sql` — `T001W`, `MARD`
- [x] Write `sql/02_tables/03_erp_source.sql` — `KNA1`, `VBAK`, `VBAP`
- [x] Write `sql/02_tables/04_tms_source.sql` — `VTTK`
- [x] Delete superseded placeholder files (`suppliers.sql`, `parts.sql`, etc.)
- [x] **Gate**: 9 tables exist, column names match LLD §2 exactly

### B4 — Data Generation
- [x] Write `sql/03_sample_data/01_generate_masters.sql` — suppliers, parts, sourcing, plants, customers
- [x] Write `sql/03_sample_data/02_generate_transactions.sql` — orders, lines, shipments, inventory
- [x] Load in FK order
- [x] Ensure ERP `ERDAT` disagrees with TMS `PROM_DLV_DT` on 15–25% of orders
- [x] **Gate**: row counts within 10% of LLD §3 targets

### B5 — Distribution Verification
- [x] Write `sql/03_sample_data/03_verify_distributions.sql`
- [x] Compute raw OTD, fill rate, DOI, landed cost premium — **before** any semantic layer
- [x] **Capture artifact** `docs/artifacts/02_raw_metrics.md` — naive ERP-date OTD vs
      governed-date OTD, fill rate, DOI, landed cost premium
- [x] **Gate**: OTD 0.84–0.90, fill 0.90–0.95, DOI 15–45
- [x] Update `docs/SESSION_LOG.md`

---

## M2 — Governance Layer

### B6 — Tags & Policies
- [x] Write `sql/04_governance/01_tags.sql` — 5 tags, applied to tables and columns
- [x] Write `sql/04_governance/02_masking_policies.sql` — 4 masking policies
- [x] Write `sql/04_governance/03_row_access_policies.sql` — `RAP_PLANT_REGION`
      **DROPPED from MVP** per `docs/GAPS_RESOLVED.md` GAP-4. M6 stretch item only.
      Do not build this now — it is the component most likely to accidentally change
      metric aggregates across personas, which would break the core claim.
- [x] **Gate**: 5 tags and 4 masking policies exist in GOVERNED schema

### B7 — Governed Views
- [x] Write `sql/04_governance/03_governed_views.sql` — 9 conformed views, masking + tags inline
- [x] Rename all cryptic columns per LLD §4 and contract §7 (65/65 columns match)
- [x] Derived time dimensions per `docs/GAPS_RESOLVED.md` GAP-2 → **moved to B08** as
      semantic-view dimension expressions, so `V_ORDER` stays exactly contract §7
- [x] Expose only `shipments.promised_delivery_date` as authoritative; do NOT expose ERP `ERDAT` as a promised date
- [x] **Capture artifact** `docs/artifacts/03_governed_columns.json` — real
      INFORMATION_SCHEMA.COLUMNS dump for all 9 views (+ POLICY_REFERENCES)
- [x] **Gate**: all 3 roles can `SELECT` every view; masking behaves per matrix
- Found: fill rate per §3 wording = 0.787449 (all lines) → **CR-005 ACCEPTED (v1.4)**, applied at B8

### B7b — Persona Procedures  ⬅ added by CR-001
Required because `USE ROLE` does not work inside Streamlit in Snowflake.
See `docs/GAPS_RESOLVED.md` GAP-1 and contract §6a.
- [x] Write `sql/04_governance/04_persona_procedures.sql`
- [x] Create `GOVERNED.SP_SAMPLE_AS_PLANNER()`, `..._AS_BUYER()`, `..._AS_LOGISTICS()`
- [x] All three `EXECUTE AS OWNER`, returning the column shape in contract §5.4
- [x] `GRANT OWNERSHIP` of each procedure to its corresponding persona role
- [x] `GRANT USAGE` on each to `FORGE_ADMIN` (the app owner)
- `SP_METRICS_AS_*` (CR-002) moved to the **end of B8**: they need `SUPPLY_CHAIN_SV`
- [x] **Capture artifact** `docs/artifacts/04_persona_outputs.json` — actual output of
      all three procedures, with real masked values
- [x] **Gate**: calling all three as `FORGE_ADMIN` returns three genuinely different
      masked result sets matching contract §6 exactly
- [x] Update `docs/SESSION_LOG.md`

### B7c — MCP Read-Only Server  ❌ DROPPED 2026-09-29
The MCP server is removed from the plan (user decision): it doesn't help the core system
deliver correct answers. Artifact handoff stays the way Claude Code verifies.

---

## M3 — Semantic Layer and Realistic Data

### B8 — Semantic View (incremental)  ✅ done 2026-09-28 (card `coco/B08_semantic_view.md`)
- [x] Write `semantic/01_semantic_view.sql`
- [x] **Start with 2 tables only**: `shipments` + `orders`. Validate.
- [x] Add one metric (`on_time_delivery_rate`). Validate with a `SEMANTIC_VIEW()` query.
- [x] Grow to all 9 tables + 10 relationships, validating after each addition
- [x] Add all facts, dimensions, 4 metrics with `WITH SYNONYMS` + `COMMENT`
- [x] **Capture artifact** `docs/artifacts/05_metric_values.json` — all 4 metrics, plus
      each broken out by every valid dimension
- [x] **Capture artifact** `docs/artifacts/06_dimension_matrix.md` — every metric ×
      dimension pairing tested, pass/fail plus error text for failures
- [x] **Gate**: all 4 metrics return values; at least one metric × dimension combo works
- **Carried in from B07 / B07b** (2026-09-27):
  - [x] `order_lines.fill_rate` excludes OPEN and CANCELLED orders (**CR-005, v1.4**), via
        the `order_lines → orders` relationship. Expected live value 0.926485.
  - [x] `inventory.days_of_inventory` = AVG(on_hand) / AVG(daily_usage), as §3 words it.
        Expected 28.499215 (art 02's 28.51 was an average of per-row ratios).
  - [x] `orders.order_year/quarter/month` (and `order_week`) as dimension expressions per
        GAP-2; `V_ORDER` deliberately does not carry them.
  - [x] `GRANT SELECT ON SEMANTIC VIEW` to the 3 persona roles.
  - [x] **Then build `GOVERNED.SP_METRICS_AS_{PLANNER,BUYER,LOGISTICS}()`** (CR-002): the
        same pattern as `sql/04_governance/04_persona_procedures.sql` (owner's rights,
        `PERSONA` from `CURRENT_ROLE()`, ownership to the persona role, `USAGE` to
        `FORGE_ADMIN`). Gate: all 4 metrics identical across the three to 6 dp, and equal
        to the semantic view. → `sql/04_governance/05_persona_metric_procedures.sql`

### B8b — Data spec v2 + context pack  📝 delivered 2026-09-29 (CR-006 ✅ accepted → contract v1.5; gate: Claude Code's confirmation)
Card `coco/B08b_data_spec.md`. Writes `docs/DATA_SPEC.md`, CR-006 in `CONTRACT.md` §11, and
the reference files for Claude Code. **Claude Code's C08, C10, C11 and C12 are built from
this, so it has to be exact and it goes first.**
- [x] **`docs/DATA_SPEC.md`**:
  - the exact source DDL: today's 9 tables (LLD §2) plus the changes (currency columns on
    money-bearing tables, SAP-style names; an FX rates table in `ERP_SOURCE`; a load
    timestamp on every source table)
  - FK load order and target volumes per table at `SCALE_FACTOR = 1` (about 1–3M order
    lines over 10 years ending today; inventory weekly plus the last 90 days daily)
  - realism: seasonality, growth over the years, carrier and supplier churn, regional mix
  - **mess catalogue**: each defect with its table, target rate, how `CONFORMED` handles it,
    and whether it moves a metric
    - repairable: re-sent duplicates, code variants (case, spaces, aliases), test/dummy
      records, non-USD amounts, late-arriving rows
    - business-rule edge cases: missing promised date, cancelled after shipping, returns,
      over-shipment, negative on-hand, zero daily usage, `NULL` cost parts, cost outliers,
      orphan lines and shipments
  - the metric and time rules; what "clean" means (the `CONFORMED` contract)
  - the seed strategy and what `SCALE_FACTOR` means
  - constraints: §3 ranges hold after cleaning; cleaned codes equal the §4 values; the
    ERP/TMS date conflict is preserved
  - **how CoCo runs the scripts**: role, warehouse, one statement per call, runtime budget
- [x] **Interfaces Claude Code builds to**:
  - `SEMANTIC.SP_DATA_HEALTH(entity VARCHAR)`: signature and return shape (C10)
  - the evaluation-set file format and ground-truth rule (C11)
  - the scale-harness inputs and outputs (C12)
- [x] **Context pack** in `docs/references/` (fetched docs, dated, with sources):
  `snowflake_data_generation.md`, `data_metric_functions.md`,
  `snowflake_scripting_procedures.md`, `agent_custom_tools.md`, `agent_evaluations.md`,
  `snowpark_async.md`, `snowflake_execution_notes.md` (CoCo's live-verified notes)
- [x] **CR-006** (filed PROPOSED 2026-09-29):
  - the metric and time rules
  - new objects: `CONFORMED` schema, `GOVERNED.SEMANTIC_ROLE` tag, the registry tables and
    `SEMANTIC.SP_BUILD_SEMANTIC_VIEW`, `SEMANTIC.SUPPLY_CHAIN_NAME_SEARCH`,
    `SEMANTIC.SP_DATA_HEALTH`
  - MCP removed from §1; source table count 9 → 10; the extra semantic-view content recorded
    as additive
- [ ] **Gate**: the user approves CR-006; Claude Code confirms in HANDOFF that the spec is
      implementable

### B8c — Load + cleansing layer (Day 2)
Card `coco/B08c_conformed_layer.md`.
- [ ] Apply the B8b source DDL changes
- [ ] **Run C08** under the handoff lock: compile check, a dry run at a small scale factor,
      then the main DB at `SCALE_FACTOR = 1` → `docs/artifacts/runs/C08_run.md`
- [ ] Create schema `CONFORMED`: one dynamic table per entity that dedupes, standardizes
      codes, converts to USD and applies the B8b rules. Cluster the big tables by date.
      Set a target lag, and check that each table refreshes incrementally; if one can't,
      record the fallback.
- [ ] Point the 9 `GOVERNED` views at `CONFORMED`: same names, columns and order;
      masking and tags inline, unchanged, **plus the `SEMANTIC_ROLE` tag on every column**
      (used by B09a)
- [ ] **Regenerate the semantic view** with `SP_BUILD_SEMANTIC_VIEW` (B09a)
- [ ] Re-capture art 03 and art 04
- [ ] **Gate**:
  - §7 columns identical to the previous art 03
  - each repairable defect present in `SOURCE` at the spec rate, and absent in `CONFORMED`
  - each edge-case rule applied as specified
  - the 4 metrics inside the §3 ranges, identical across personas
  - the §8 naive OTD further from the governed OTD than before
  - persona roles can't read `SOURCE` or `CONFORMED`

### B9 — Semantic view v2 (build Day 1, capture Day 2)
Card `coco/B09_semantic_view_v2.md`. Built by hand first in `semantic/01_semantic_view.sql`
(still `CREATE OR REPLACE … COPY GRANTS`); B09a then generates the same view from metadata.
- **Carried in from B08** (2026-09-28):
  - [ ] The supplier fan-out: fixed by a primary-sourcing logical table (one supplier per
        part), with the `AI_SQL_GENERATION` ban as the fallback if that table can't be built
  - [ ] After each re-run, re-check persona `SELECT` and `SP_METRICS_AS_*`
- [ ] **Expose every business column** of the governed views once:
  - IDs (order, shipment, part, supplier, customer, plant) for record lookups
  - every descriptive column; every number as a fact (quantities, prices, lead time,
    reliability, on-hand, reserved, reorder point, daily usage, freight, duty, handling,
    capacity, weight)
  - derived: days late, transit days, is-late, below-reorder-point; year, quarter and month
    for every date
  - **never** the 4 masked money columns. Customer name is a label only; group by customer ID.
- [ ] **Named metrics**: the 4 canonical ones unchanged, plus about 10 common ones (counts,
      late and delayed shipments, revenue, units, total landed cost, average days late and
      transit time, average lead time and reliability, parts below reorder point). Analyst
      aggregates every other exposed fact on its own (verified live 2026-09-29).
- [ ] **Named filters**: late, delivered, critical parts, open orders
- [ ] A business description for every table and column; synonyms trimmed to trade terms
- [ ] `AI_SQL_GENERATION`: canonical metrics only, never the ERP promised date, the B8b
      time rule, top-N and limits, amounts in USD, group by IDs not masked labels, numbered
      multi-part questions answered in order
- [ ] `AI_QUESTION_CATEGORIZATION`: the view's scope; refuse out-of-scope questions; ask when
      ambiguous
- [ ] Verified queries: the 8 §9 questions (Q8 = `vq_worst_plants_otd`, CR-003) plus about
      4 cross-functional ones
- [ ] **Captures on the B8c data**: art 05, art 06, and **art 09** (B11 merged in):
      `SP_METRICS_AS_*` × 3 plus the masking divergence from `SP_SAMPLE_AS_*`
- [ ] **Gate (build, on today's data)**:
  - the canonical values identical to B08 (the expansion changed no numbers)
  - the §4 matrix passes; every verified query runs
  - **fast**: the view stays under a 25K-token estimate, and Analyst latency on 5 test
    questions is no worse than with v1
- [ ] **Gate (captures)**: art 05/06/09 re-captured; art 09 identical across personas to 6 dp

### B9a — Metadata-driven generator + name search (Day 1)
Card `coco/B09a_sv_generator.md`. Makes adding tables near-automatic.
- [ ] Tag `GOVERNED.SEMANTIC_ROLE` (`KEY` / `DIMENSION` / `FACT` / `EXCLUDE`) on every
      governed-view column; masked columns are always `EXCLUDE`. Column comments become the
      descriptions.
- [ ] Small registry tables in `SEMANTIC`: tables, relationships, derived columns, metrics
      (with a version and an owner), filters, verified queries, instructions
- [ ] `SEMANTIC.SP_BUILD_SEMANTIC_VIEW(apply BOOLEAN)`: reads the tags, comments and
      registries; returns the DDL; applies it with `COPY GRANTS` when `apply` is true
- [ ] `SEMANTIC.SUPPLY_CHAIN_NAME_SEARCH`: a Cortex Search service over supplier, part, plant
      and carrier names only (**no masked columns**), attached to those dimensions, refreshed
      daily
- [ ] **Gate**:
  - the generated view reproduces B09 and passes the same checks
  - a new column tagged on a governed view appears after one regeneration
  - name search matches a misspelled plant name
- If it slips, the hand-written B09 view ships and the generator moves to `docs/ROADMAP.md`.

### B8m — Move to the event account (trial Day 2, cutover end of Day 3)
Plan: `COCO.md`, "Account switch plan". Needs the user to claim the event account and add a
VS Code connection first.
- [ ] **Account setup** (new account):
  - `CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION'`
  - FORGE_WH (XS, 60 s auto-suspend); COMPUTE_WH auto-suspend 60 s
  - a warehouse resource monitor, and an account budget alert
  - check that the edition is Enterprise
- [ ] **Trial move (Day 2):**
  - replay `sql/01_setup` → `02_tables` → `03_sample_data` → `04_governance`, then
    `semantic/01_semantic_view.sql`
  - check: 12,452 source rows; masking right for each persona; the semantic view answers
  - log every difference from the old account in `docs/artifacts/runs/B08m_run.md`
- [ ] **Cutover (end of Day 3):**
  - replay the full build from the repo: DDL v2, generator, `CONFORMED`, governed views,
    semantic view, name search, agent, DMFs, eval objects
  - regenerate at SF 1 with the same seed. The row-count checksum and the art 03–10 numbers
    must match the old account.
- [ ] **Docs:**
  - `COCO.md` connection line
  - `snowflake_execution_notes.md` header
  - HANDOFF note to Claude Code: the account changed; no FQN changes
- [ ] **Gate:** the replay needs no hand fixes, or every fix is committed back to the repo
  script. The numbers match, and the old account is left idle.

---

## M4 — Conversational Layer

### B10 — Cortex Agent + evaluation set (Day 2)
Card `coco/B10_agent.md`. Absorbs old M6's edge-case and multilingual tests.
- [ ] `agent/01_agent.sql`: `SEMANTIC.SUPPLY_CHAIN_AGENT`
  - tools:
    - `cortex_analyst_text_to_sql` on `SUPPLY_CHAIN_SV` (`FORGE_WH`, a timeout); the name
      search works through the view's dimensions
    - `data_to_chart`
    - the custom tool `SP_DATA_HEALTH` (C10), so the agent can warn when data is stale or
      failing checks
  - orchestration and response instructions: which tool when; always show the SQL; state
    the time window; answer numbered parts in order
  - the §9 sample questions; a time and token budget; the model is chosen by the
    evaluation results
- [ ] Grants: `USAGE` on the agent to `FORGE_ADMIN` and the persona roles. Agents use the
      caller's **default** role and default warehouse (art 01); check which role applies
      when the app calls it.
- [ ] **Run C11** (the evaluation set and runner) under the handoff lock, with Snowflake's
      agent evaluations if privileges allow; otherwise the `DATA_AGENT_RUN` runner
- [ ] **Capture** art 07 (one complete, unmodified response) and art 08 (every evaluation
      question: answer, SQL, pass/fail, latency)
- [ ] **Gate**:
  - the 8 canonical answers match art 05
  - out-of-scope questions are refused; ambiguous ones get a clarifying question
  - the pass rate and latencies are recorded
  - no masked value leaks into an answer

### B11 — Cross-persona consistency  → merged into B9 (art 09), 2026-09-29

---

## M5 — Quality and Scale

### B12 — Data-quality checks (Day 2)
Card `coco/B12_dmfs.md`. Check Enterprise edition first. **Claude Code writes the SQL (C10,
in `quality/`); CoCo runs it and wires it up.**
- [ ] **Run C10** under the handoff lock:
  - system DMFs (nulls, duplicates, freshness, row count) and custom DMFs
    (`DMF_OVERSHIP_COUNT`, orphan lines, missing promised dates, negative on-hand, cost
    outliers), attached on `SOURCE` and `CONFORMED`, on a schedule
  - `SEMANTIC.SP_DATA_HEALTH` (the agent tool; B10 attaches it)
- [ ] Grant `SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER` to `FORGE_ADMIN`; `USAGE` on
      `SP_DATA_HEALTH` to the roles that call the agent
- [ ] **Capture** art 10
- [ ] **Gate**:
  - results land in `DATA_QUALITY_MONITORING_RESULTS`
  - `SOURCE` shows the injected defects at the spec rates; `CONFORMED` shows none of the
    repairable ones
  - `SP_DATA_HEALTH` returns the B8b shape for every entity

### B13 — Scale proof (Day 3)
Card `coco/B13_scale_proof.md`. **Claude Code writes the harness (C12, in `tests/scale/`);
CoCo runs it.**
- [ ] Zero-copy clone of the database, plus a temporary larger warehouse capped by a
      resource monitor
- [ ] Run C08 at a large scale factor (target 100M+ order lines, sized to the credit
      budget) into the clone, then refresh its `CONFORMED` layer
- [ ] **Run C12** on the clone: the 4 metrics, the 55 pairings, `SP_METRICS_AS_*`, and part
      of the evaluation set. The agent points at the original view, so use a clone-local
      agent or test the semantic view directly; check how the clone copies semantic views
      first.
- [ ] Record: timings on XS vs the larger warehouse, partitions scanned vs total, credits,
      and dynamic-table refresh time
- [ ] Confirm the semantic view definition and the generated SQL shape are unchanged, and
      personas are still identical
- [ ] **Capture** art 12 (scale report), then drop the clone and the warehouse
- [ ] **Gate**: every path returns; definitions unchanged; personas identical; cost recorded

---

## M6 — Production

### B14 — Contract audit + security review (Day 3)
Card `coco/B14_audit.md`. Old B13 + old B17. **Claude Code refreshes the live tests for the
new data and CR-006 (C13); CoCo runs them** (`pytest -m live`, with Snowpark installed in the
venv) as the contract check, then adds anything the tests don't cover:
- [ ] All metric identifiers resolve in `SEMANTIC_VIEW()` queries (§3)
- [ ] All dimension identifiers resolve (§4)
- [ ] Every valid metric × dimension pairing returns rows; `days_of_inventory` ×
      `orders.*` fails as documented (§4)
- [ ] Every governed view column name matches (§7)
- [ ] The masking matrix behaves exactly as specified, per role (§6)
- [ ] Metric values sit inside the documented ranges (§3)
- [ ] The divergence demo queries return two different numbers (§8)
- [ ] `sql-verify` sweep over all SQL files
- [ ] Grants review: least privilege; persona roles have no access to `SOURCE` or
      `CONFORMED`; no over-broad grants; all PII masked; no credentials in the repo
- [ ] **Capture** art 11
- [ ] **Gate**: zero deviations, or every deviation filed as a Change Request in
      `CONTRACT.md` §11 with the user notified

### B15 — Production hardening + deploy (Day 3)
Card `coco/B15_deploy.md`. **Deploy with Claude Code's script (C07). Do NOT use the old PUT
list in `docs/references/streamlit_in_snowflake.md` §7**: it missed `ui/` and `.streamlit/`.
```
set SNOWFLAKE_CONNECTION_NAME=<connection>
python deploy/deploy_app.py --dry-run     # files + SQL, no connection
python deploy/deploy_app.py               # deploy / redeploy, as FORGE_ADMIN (the app owner)
```
- [ ] Needs `snowflake-snowpark-python` in the venv (not installed as of 2026-09-27)
- [ ] Pre-req grants for `FORGE_ADMIN`: `CREATE STAGE` and `CREATE STREAMLIT` on `APP` (B02
      has both), `USAGE` on `FORGE_WH` (B02 has it)
- [ ] **Grant `SELECT` on `TMS_SOURCE.VTTK` and `ERP_SOURCE.VBAK` to `FORGE_ADMIN` only.**
      The §8 naive-OTD query (`forge_data.get_naive_otd()`) runs as the app owner, and
      `FORGE_ADMIN` alone is denied today (verified 2026-09-27). Persona roles don't
      inherit `FORGE_ADMIN`, so masking isn't bypassed.
- [ ] `FORGE_ADMIN` also needs `SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER` (B12) and `USAGE`
      on the agent (B10). It owns `SUPPLY_CHAIN_SV` already (B08).
- [ ] **Cost controls**: a resource monitor on `FORGE_WH`, the warehouse size decision
      (from B13), auto-suspend, and a query tag per path (app, agent, procedures) for cost
      attribution
- [ ] **Identity**: check in the docs whether SiS can run as each viewer (caller's rights).
      Write up the production identity path. The persona procedures stay the demo proof.
- [ ] A replaced app loses its grants: pass `--grant-usage <roles>` on every deploy if
      other roles should open it
- [ ] Verify in SiS: the HTML views render (inline `<script>` in Components v1 iframes);
      if blocked, tell Claude Code (a native fallback exists)
- [ ] Update `.agents/HANDOFF.md` with all deployed FQNs and role names
- [ ] Tell the user the app is live; update `docs/SESSION_LOG.md` and `docs/MILESTONES.md`

---

## Stretch (Day 3, only if time is left)

- [ ] **Parallel multi-part router**: a governed splitter function in `SEMANTIC` (fixed
      output format, via `AI_COMPLETE`) that returns ordered sub-questions, each tagged
      independent or dependent, KPI or free-form. Claude Code does the fan-out and ordered
      merge in the app. Measure it against a single agent call on the multi-part
      evaluation questions.
- [ ] **KPI shortcut** (with Claude Code): KPI sub-questions go straight to
      `SEMANTIC_VIEW`, with no LLM
- [ ] Lineage trace (`cortex lineage`) from a source column through `CONFORMED` and
      `GOVERNED` to the semantic view, for the README

---

## Removed on 2026-09-29

| Item | Why |
|---|---|
| B7c read-only MCP server | Dropped with MCP; artifact handoff works |
| Old B14 MCP server | The user dropped MCP: it doesn't help the core system deliver correct answers |
| Old B11 as a separate card | Art 09 is captured in B9 |
| Old B16 differentiation | Edge cases and multilingual go to B10; the lineage trace is a stretch item |
| Old B17 security review | Merged into B14 |
| Row access policy | Stays dropped (GAP-4): it could change aggregates across personas |
