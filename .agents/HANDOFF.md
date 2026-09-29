# Agent Handoff Log

> Both agents read this at session start. Each updates **only its own section**.
> The user mediates — agents do not talk to each other directly.
>
> **`docs/CONTRACT.md` is the frozen interface.** Neither agent may change it
> unilaterally. Both build to it in parallel. That is what prevents collision.

---

## Current State

| | |
|---|---|
| **Milestone** | M3: B08 done; **B08b delivered 2026-09-29** (DATA_SPEC + CR-006 + references). CoCo: B09 next. Claude Code: C08 data generator (unblocked) |
| **Branch** | `development` |
| **Contract version** | **v1.5** (CR-006 accepted by the user 2026-09-29 and applied in the body; §10 values re-captured at B09) |
| **Blocking issues** | None. **User action:** claim the new event account by 3 Oct UTC (plan: `COCO.md`, "Account switch plan") |
| **Deadline** | Submission **4 Oct 2026**; all work done by **end of 2 Oct**. Day 1 = 29 Sep, Day 2 = 30 Sep, Day 3 = 1 Oct, 2 Oct = buffer, rehearsal, video |
| **Last updated** | 2026-09-29 |

### Parallel tracks

```
CoCo   (Snowflake)  B08b spec → B08c load + CONFORMED → B09 → B10 → B12 → B13 ─► B08m cutover (end 1 Oct) ─► B14 → B15 (new account)
Claude (app, data)  C08 generator → C09 app pass → C6b → C6c → C05
```

Claude Code is **not blocked**: `docs/DATA_SPEC.md` has landed, so C08, C10, C11 and C12 can start.

---

## Latest from CoCo

### ✅ CR-006 accepted, 2026-09-29 — contract is now v1.5

The user approved CR-006. It is applied in the body of `docs/CONTRACT.md`:
- §1: MCP removed, 6 rows added
- §3: new definition strings, verbatim
- new §3a: the time rule
- §4: `orders.order_year_quarter`
- §5: windowed patterns; one `SEMANTIC_VIEW` call per window
- §5.4: `SP_METRICS_AS_*` apply §3a
- §7: `CONFORMED` note
- §8: windowed naive and governed queries
- §10: values replaced at B09

**Unblocked for Claude Code:** C09 part B:
- the `config.py` definition strings
- the §3a `WHERE` in `forge_data.py`
- the as-of date from `SP_DATA_HEALTH`
- MCP removal

`CLAUDE.md` still says "v1.4; CR-006 pending"; please update it, since it's your entry point.

### ⚠ Account switch, 2026-09-29 (user-approved) — affects Claude Code's SQL and deploy

The organisers issued a new event account (the old one can't be topped up). Plan (full
detail in `COCO.md`, "Account switch plan"):
- **Old account until the end of 1 Oct**: B09, B09a, B08c, B10, B12, B13.
- **B08m**: trial move on 30 Sep, cutover at the end of 1 Oct.
- **2 Oct in the new account**: B14 (`pytest -m live`), B15 deploy (the submitted app link),
  final artifacts.

**What this asks of Claude Code:**
1. **Every SQL file must be re-runnable on an empty account:**
   - `CREATE OR REPLACE` / `IF NOT EXISTS`
   - no reliance on objects created by hand
   - grants inside the scripts
2. **Never name the account** (locator, org, URL) in `app/`, `deploy/`, `data_gen/`,
   `quality/` or `eval/`. Take it from the connection.
3. **No FQN changes.** The database, schemas and object names stay the same, so the contract
   is unaffected.
4. Artifacts captured in the old account stay valid, because the generator is deterministic.
   CoCo re-checks that the numbers match at cutover.

### ✅ B08b landed, 2026-09-29: `docs/DATA_SPEC.md` + CR-006 + references (read this first)

**What landed:**
- **`docs/DATA_SPEC.md`**: the spec for C08, C10, C11 and C12. Read §0 first.
- **CR-006 (PROPOSED)**: in `docs/CONTRACT.md` §11, awaiting the user's approval.
- **The context pack** in `docs/references/`. Start with `snowflake_execution_notes.md`,
  then `snowflake_data_generation.md`, `snowflake_scripting_procedures.md`,
  `data_metric_functions.md`, `agent_custom_tools.md`, `agent_evaluations.md` and
  `snowpark_async.md`. You own all seven from now on. I added their rows to
  `docs/references/README.md`, marked `mcp_client_setup.md` obsolete, and changed nothing
  else there.

**Please confirm in your section that the spec is implementable, or list questions.**
That's half of B08b's gate.

**What matters most for each track:**
- **C08 (critical path)**:
  - **Hash-based randomness only** (§6). `RANDOM(seed)` is not reproducible across runs;
    the recipe in §6 was checked live (same checksum on 5M rows, on 2 warehouses).
  - **The generator is procedures in `OPS`, with the parameters as arguments**
    (`SP_GENERATE_DATA(TARGET_DB, SCALE_FACTOR, SEED, END_DATE)`, `SP_INJECT_MESS`,
    `SP_GEN_SELF_CHECKS`; §7.1).
  - **Not session variables.** My SQL tool doesn't keep session state between calls
    (verified), so this replaces the `00_params.sql` idea in CLAUDE_TASKS.
  - Procedures are `EXECUTE AS CALLER` and start with `USE DATABASE :TARGET_DB`, so B13
    can point them at a clone.
  - Source DDL v2 (§1): 10 tables (new `ERP_SOURCE.TCURR`), `LOAD_TS` everywhere, keys
    only `NOT NULL`, wider IDs (`ORD000000001`), currencies. **I create these tables at
    B08c**; you write into them.
  - The mess (§4): inject only the listed variants and rates, in a separate procedure.
    Each defect has a self-check.
  - **Include a small dry-run `CALL`** (e.g. SF 0.01) in the hand-over: compile-only
    doesn't check procedure bodies (verified), so the dry run is where body errors show.
- **C10**:
  - `SP_DATA_HEALTH(ENTITY VARCHAR) RETURNS VARIANT`, with the exact JSON shape in §7.2.
  - DMFs attach to **both** `SOURCE` (defects expected) and `CONFORMED` (repairable ones
    must be 0).
  - **The app's `_QUALITY_EXPECT_ZERO` must judge by layer.** On the new data,
    `DMF_OVERSHIP_COUNT` on `ERP_SOURCE.VBAP` is non-zero on purpose.
- **C11**:
  - `OPS.EVAL_QUESTIONS` (the columns are in §7.3). Ground truth is `SEMANTIC_VIEW` SQL
    that applies the time rule.
  - The runner `OPS.SP_RUN_EVAL` re-runs the agent's SQL and compares it with a tolerance.
    That comparison is deterministic.
- **C12**:
  - `OPS.SP_SCALE_RUN(TARGET_DB, RUN_LABEL, RESULTS_TABLE)`.
  - Pruning comes from `GET_QUERY_OPERATOR_STATS` (verified; `INFORMATION_SCHEMA` query
    history has no partition counts).
  - `SQL_HASH` proves the SQL shape is the same at every scale.
- **C09 part B and CR-006**: nothing changes until the user approves. Then:
  - the time rule (**trailing 12 months** for OTD, fill rate and landed cost; **the latest
    snapshot** for DOI; anchor `CURRENT_DATE()`) goes into every metric query, and into
    `get_naive_otd()`
  - the four §3 definition strings change (verbatim in CR-006)
  - `MCP_SERVER` goes
  - the as-of date comes from `SP_DATA_HEALTH('shipments'):as_of_date`
  - `SP_METRICS_AS_*` keep their shape and apply the window from B09.

**Also found:**
- Every v1 source column is `NOT NULL`, which is why DDL v2 relaxes it.
- In v1, `DELAYED` meant delivered late; v2 keeps that and adds "in transit past the
  promise" (§3.2).

### ⚠ Replan, 2026-09-29 (user-approved)

The user replanned the rest of the project. Goal: **finish in 3 days, production-ready and
deployed**. The core system must stay correct, fast and cheap from today's small data to
billions of rows, and while the data changes. Only infrastructure knobs (warehouse size,
clustering, materialization) change with scale. Full queue:
`.agents/tasks/COCO_TASKS.md` (it starts with the 9 core system rules). Sequence and
progress: `.agents/NEXT.md`. Post-hackathon backlog: `docs/ROADMAP.md`.

**What changes for Claude Code:**
- **The data becomes realistic, and you generate it** (the user's decision):
  - 10 years of history, moderate volume in the main DB (about 1–3M order lines)
  - real-world mess: duplicates, code variants, currencies, test records, plus
    business-rule edge cases
  - you write **seeded SQL generator scripts** in a new folder **`data_gen/`**; CoCo
    reviews and runs them (you still have no Snowflake access)
  - the exact spec will be in **`docs/DATA_SPEC.md`**, written by CoCo at B08b (Day 1)
- **A cleansing layer** (new schema `CONFORMED`, dynamic tables) sits under the governed
  views. The `GOVERNED` view names and columns (§7) and the masking (§6) don't change, so
  the app's queries don't change.
- **All metric values will change** with the new data, although the §3 ranges are designed
  to hold. So art 03–06 get re-captured.
- **The MCP server is dropped**, and the `MCP_SERVER` constant in `app/utils/config.py` can
  go. CR-006 removes it from contract §1.
- **CR-006** (coming at B08b) will add edge-case rules to the §3 metric definitions and one
  time rule. `config.py` copies §3 verbatim, so those strings will change.

**Update, same day: the work split is re-done (user-approved).** Claude Code now writes
**everything that can be written offline, including Snowflake SQL**, and CoCo runs it.
With the user's permission I rewrote your queue once, and you own it again from here:
- **`.agents/tasks/CLAUDE_TASKS.md`**: C09 → C08 → C10 → C11 → C6b → C12 → C6c → C13 → C05
  → C14, each with inputs, outputs, acceptance checks and the references to read
- **`CLAUDE.md` Boundaries**: your new folders `data_gen/`, `quality/`, `eval/` (plus
  `tests/scale/`); "you write SQL, you never run it"; the handoff lock

**Start now:** C09 (app production pass) doesn't need anything from me. C08, C10, C11 and
C12 need **`docs/DATA_SPEC.md`**, which I write first (B08b), together with reference files
in `docs/references/`: data generation, DMFs, scripting procedures, agent custom tools,
agent evaluations, Snowpark async, and my live-verified execution notes. I'll post here
when they land.

**Found today, useful for C11 and C6c:** Cortex Analyst aggregates any exposed fact
without a named metric (live test: it summed landed cost by carrier and counted shipments
per carrier on its own). So the evaluation set can include ad-hoc totals and counts, not
only the named metrics.

**How your SQL gets run**: the handoff lock. Add the file to **"Ready for CoCo to run"**
(below), stop editing it, and read the result in `docs/artifacts/runs/<card>_run.md`.

### Answers to Claude Code's questions (2026-09-29, relayed by the user)

**Deadline:** submission **4 Oct 2026**; everything done by **end of 2 Oct**. Day 1 = 29 Sep,
Day 2 = 30 Sep, Day 3 = 1 Oct, 2 Oct = buffer, fixes, rehearsal, video. Same dates for both
of us.

**Q1 — the core-scalability doc prompt (for C05, Day 3).** The prompt the user was given,
verbatim:

```text
Read CLAUDE.md, then docs/CONTRACT.md (v1.4), docs/HLD.md, docs/LLD.md,
.agents/tasks/coco/B08_semantic_view.md, semantic/01_semantic_view.sql,
sql/04_governance/05_persona_metric_procedures.sql, docs/artifacts/05_metric_values.json
and docs/artifacts/06_dimension_matrix.md, and app/utils/forge_data.py.

Task: plan, then (after my approval) write a new document docs/CORE_SYSTEM_SCALABILITY.md.
Write a task card for it first, as CLAUDE.md requires.

Framing: we are designing for a real business with 10+ years of data and hundreds of
thousands of requests, not just the hackathon. Separate two things strictly:
- CORE SYSTEM: question -> Cortex Agent -> Cortex Analyst -> semantic view
  (relationships, metrics, dimensions, instructions, verified queries) -> generated SQL
  -> governed views + masking policies -> source tables -> answer. This must be
  scale-invariant: same question, same definitions, same SQL shape, same governance,
  whether the data is 12K rows or billions.
- INFRASTRUCTURE KNOBS: warehouse size, multi-cluster, clustering keys, materialization /
  dynamic tables, caching. These may change speed and cost, never answers or behaviour.

The document must contain:
1. An end-to-end flow diagram (ASCII) of every request path: KPI/Explore
   (SEMANTIC_VIEW), persona procedures (SP_METRICS_AS_*, SP_SAMPLE_AS_*), Ask
   (DATA_AGENT_RUN -> agent -> Cortex Analyst -> semantic view), and the one naive source
   query (contract §8). Show what happens inside Snowflake: name resolution, join-path
   validation, metric expansion, view expansion, masking by CURRENT_ROLE(), warehouse
   execution, result cache. Mark each part as built, planned (B09/B10) or deploy (B15).
2. For each core component, the invariants it guarantees at any scale, and why.
3. A gap list: core design decisions that are NOT yet scale-invariant, each with its
   risk, proposed rule, and owner (CoCo or Claude Code). At minimum:
   - no default time window
   - no result-size / top-N rule (agent) or paging (app)
   - fan-out joins, e.g. suppliers.* through sourcing (see art 06)
   - the agent not yet bound to the canonical metrics (AI_SQL_GENERATION, B09)
   - identity: owner's-rights app vs running as each real user's role
   - the anchor for relative dates ("last quarter": today, or the latest data loaded)
   - semantic view breadth vs per-question token cost and accuracy
   - the accuracy model: deterministic paths (metrics, procedures) vs the probabilistic
     agent path; how verified queries, guardrails and a standing eval set bound the error
4. The infrastructure knobs, listed separately, with when each would be turned.
   Explain why none of them changes the core.

Rules:
- Documentation only. Do not change app/, tests/ or any CoCo-owned file (sql/, semantic/,
  agent/, docs/HLD.md, docs/LLD.md, docs/artifacts/).
- Use only facts from the repo, the artifacts and docs/references/. If you state a
  Snowflake capability not covered there, mark it "to verify".
- If any gap needs a contract change, draft it as a Change Request in CONTRACT.md §11 and
  tell me. Don't change anything else in the contract.
- Update NEXT.md, HANDOFF.md ("Latest from Claude Code" only) and SESSION_LOG.md as usual.
```

What has changed since that prompt:
- MCP is dropped.
- Most listed gaps now have planned fixes. Describe them as designed, and as built once
  they are: time rule, top-N, fan-out, canonical-metric binding (B09, CR-006); the
  `CONFORMED` layer (B08c); the metadata generator and name search (B09a); the data-health
  tool and evaluation set (B10, C10, C11).
- Also read `docs/DATA_SPEC.md`, ADR-008, the core system rules at the top of
  `COCO_TASKS.md`, and art 08 and art 12 when they exist.

**Q2 — C6b vs contract §10 practice values: agreed, it goes through CR-006.** CR-006
(B08b) will say that §10's practice values are replaced by the values in the re-captured
art 05. I'll write the numbers into §10 (contract v1.5) when art 05 is re-captured at B09.
Then you update `config.py` and the practice data in C6b, and the contract test keeps them
in sync. Until then, change nothing.

**Q3 — your defaults are all fine:**
- start C09 with the parts that don't need the spec; test missing values against the
  current art 05 (fill rate for OPEN and CANCELLED is `NULL`)
- the as-of date waits for `DATA_SPEC.md`
- remove `MCP_SERVER` only after CR-006 is approved
- commit separately first (the user is doing it)

<details><summary>Earlier requests from this morning (superseded by CLAUDE_TASKS.md)</summary>

**Requests for Claude Code** (please write the cards and update `CLAUDE_TASKS.md`; I don't
edit your files):
1. **Take ownership of `data_gen/`**: add it to your boundaries in `CLAUDE.md`.
2. **C08 data generator (Day 1, on the critical path)**: build it from `docs/DATA_SPEC.md`
   as soon as it lands. Scripts must be:
   - seeded, so every run gives the same data
   - parameterised by `SCALE_FACTOR` (B13 runs it at 100M+ order lines on a clone)
   - written into the source tables in FK order, plus self-check queries for the injected
     defect rates
   - I need it by the **end of Day 1**, because B08c loads it on Day 2
3. **C09 app production pass (Day 1–2)**:
   - handle `NULL` metric values (fill rate for OPEN/CANCELLED is `NULL` by design)
   - page or limit long results (dimensions like `orders.order_date` grow with 10 years)
   - show the as-of date
   - remove the MCP constant
   - prepare the switch to `USE_MOCK_DATA = False`
4. **C6b**: wait for the **re-captured** art 05/06 (B09, Day 2). Reconciling the current
   ones would be redone.
5. **C6c** after art 07–09 (Day 2). **C05** on Day 3: demo, README, and the
   core-scalability doc.
6. **Stretch, Day 3, only if time is left**: parallel fan-out and ordered merge for numbered
   multi-part questions in `ask_agent()`, plus a KPI shortcut straight to `SEMANTIC_VIEW`.
   CoCo would supply a governed splitter function.

</details>

### B08 (2026-09-28)

**Status**: B08 complete (2026-09-28). The semantic layer is live: `SEMANTIC.SUPPLY_CHAIN_SV` (9 tables, 10 relationships, 24 dimensions, 4 metrics) plus the 3 owner's-rights metric procedures. **Art 05 and art 06 were captured on the v1 data; they're re-captured at B9 after the replan.**

**B08 gate results (live, secondary roles off)**:
- **4 metrics, all equal to the B07 values to 6 dp**: OTD **0.873973**, fill rate **0.926485** (CR-005 filter on), DOI **28.499215** (§3 formula), landed cost **518.971250**.
- **55/55 valid §4 pairings pass**, and output headers are the unqualified names (`PLANT_REGION`, `ORDER_QUARTER`, …), as §5.2 says.
- **DOI × `orders.*` / `shipments.*` are rejected by Snowflake itself** (9/9): "The entities 'ORDERS' and 'INVENTORY' are not related…".
- **Same values everywhere**: the view queried as `FORGE_ADMIN`, and as `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE` each on its own; and the three `SP_METRICS_AS_*` called as `FORGE_ADMIN`.
- `SP_METRICS_AS_*` are owned by their persona roles, use `EXECUTE AS OWNER`, have identical bodies, and derive `PERSONA` from `CURRENT_ROLE()`.

**For Claude Code**:
- **C6b: see the replan above.** The files below are the v1 captures; wait for the B9 re-capture on the new data. Their structure stays the same:
  - `docs/artifacts/05_metric_values.json`:
    - `payload.overall` holds the 4 metrics, keyed by the §5.1 column names.
    - `payload.by_dimension.<metric id>.<dimension id>` is the full result for each of the 55 pairings.
    - SHA-256 `02eb2c2e3fd7b10dfde6757973ed364c73c54e661985ea14792ac362b814b2a5`.
  - `docs/artifacts/06_dimension_matrix.md`: 96 cells (the 23 §4 dimensions plus `orders.order_week`), pass/fail, with the error text.
- **Rows inside each art 05 pairing are not sorted.** Sort by the dimension column before comparing.
- **Number types**: in the view, OTD has 6 decimals, fill rate 9, DOI 12 and landed cost 8. `SP_METRICS_AS_*` return all four as `NUMBER(38,6)`. So compare the view with the procedures at 6 dp (§6 already says so).
- **`compare_across_personas()` live mode no longer needs the mock fallback**: `SP_METRICS_AS_*` exist and return the §5.4 shape (`PERSONA`, `ON_TIME_DELIVERY_RATE`, `FILL_RATE`, `DAYS_OF_INVENTORY`, `AVG_LANDED_COST`), 1 row each.
- **Mock values vs real**:
  - All 4 real values are inside the §3 ranges.
  - Landed cost differs most from the mock: 518.97 real vs 412.67 mock.
  - By plant region, real OTD is APAC 0.880165, EMEA 0.870445, AMER 0.871369.
- **Data facts that affect charts**:
  - Shipments cover **6 of 12 plants**, so OTD and landed cost by plant give 6 rows, while fill rate and DOI give 12.
  - OTD by `orders.order_status` gives 2 rows (SHIPPED, DELIVERED).
  - Fill rate by `orders.order_status` gives 4 rows, and OPEN and CANCELLED are `NULL` (CR-005).
  - Fill rate by category is exactly 1.000 for CHEMICAL, ELECTRONICS and RAW_MATERIAL.
- **`suppliers.*` is not a contract pairing.** Snowflake accepts it for fill rate and DOI, but it fans out through `sourcing` (a part with several suppliers counts once per supplier). Keep it out of the app. B09 will tell the agent the same.
- **`orders.order_week` is an extra dimension** (GAP-2), not in §4, so no contract change is needed. It works for OTD, fill rate and landed cost.
- Still true from B07: a user session with **secondary roles = ALL** can read more than the primary role alone. Masking is unaffected. SiS calls the procedures under owner's rights, with no secondary roles.
- Still true for B15: I'll grant `SELECT` on `TMS_SOURCE.VTTK` and `ERP_SOURCE.VBAK` to `FORGE_ADMIN` only, for `get_naive_otd()` (§8). No app change is needed.

**Contract v1.3 Decisions (Resolved)**:
- **CR-002 ACCEPTED**: Persona metric procedures (`SP_METRICS_AS_{PLANNER,BUYER,LOGISTICS}()`) will be created in B07b / B11 to compute the 4 metrics under each persona role.
- **CR-003 ACCEPTED (Option B)**: Canonical question 8 reworded to *"Which plants have the worst on-time delivery?"* (valid pairing `shipments.on_time_delivery_rate` × `plants.plant_name`), verified query in B09 will be `vq_worst_plants_otd`.
- **CR-004 ACCEPTED**: `CONTRACT_PRICE` and `CUSTOMER_EMAIL` will be returned by `SP_SAMPLE_AS_*` at B07b, covering all 6 masked columns.
- **Source Table Count**: Confirmed **9 source tables** (`SRM_SOURCE.LFA1`, `MARA`, `SOURCING`; `WMS_SOURCE.T001W`, `MARD`; `ERP_SOURCE.KNA1`, `VBAK`, `VBAP`; `TMS_SOURCE.VTTK`), 1:1 with the 9 governed views.
- **DMF Name & Viewer Role**: Noted for B12 — `DMF_OVERSHIP_COUNT`, and granting `SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER`.

**Deployed objects**:

| Object | Status |
|--------|--------|
| Database `SUPPLY_CHAIN_FORGE` | DEPLOYED ✅ |
| 7 schemas (`ERP_SOURCE`, `WMS_SOURCE`, `TMS_SOURCE`, `SRM_SOURCE`, `GOVERNED`, `SEMANTIC`, `APP`) | DEPLOYED ✅ |
| Warehouse `FORGE_WH` (XSMALL, auto-suspend 60s) | DEPLOYED ✅ |
| Persona roles (`FORGE_ADMIN`, `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE`) | DEPLOYED ✅ |
| 9 source tables across 4 schemas | DEPLOYED ✅ |
| Sample data (12,452 total records) | DEPLOYED ✅ |
| Governance (5 tags & 4 masking policies) | DEPLOYED ✅ |
| 9 governed views (masking attached inline) | DEPLOYED ✅ |
| Persona sample procedures (3, owned by persona roles) | DEPLOYED ✅ |
| Persona metric procedures (3, owned by persona roles) | DEPLOYED ✅ |
| Semantic view `SUPPLY_CHAIN_SV` (owner `FORGE_ADMIN`; `SELECT` to the 3 persona roles) | DEPLOYED ✅ |
| Cortex Agent `SUPPLY_CHAIN_AGENT` | NOT YET (B10) |
| MCP server | DROPPED 2026-09-29 (user decision) |
| Schema `CONFORMED` (cleansing dynamic tables) | NOT YET (B08c) |
| DMFs | NOT YET (B12) |

**Next action**: B09 (semantic view v2, by hand, on today's data), then B09a. B08c runs C08 once it is READY. CR-006 awaits the user.

---

## Latest from Claude Code

### C09 done: the app follows contract v1.5 (2026-09-29, late)
- **Every metric query applies the §3a time rule**: ship-date window for OTD and landed
  cost, order-date window for fill rate, the latest snapshot for DOI. `get_all_metrics()`
  makes 3 calls, one per window (§5.1). The §8 naive query is windowed too.
- **`SP_DATA_HEALTH` in the app**:
  - `CALL SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH(?)`, with `'shipments'` for the as-of
    date and `'ALL'` for the Data health screen's per-table freshness
  - it reads the first column of the one result row as JSON, in the §7.2 shape
  - if the procedure isn't there in live mode, the as-of date is hidden (never a practice
    date)
- **Data quality is judged by layer**: the app's DMF query now also selects
  `table_schema` from `DATA_QUALITY_MONITORING_RESULTS`. Results on `*_SOURCE` show as
  "Expected in raw data"; zero is required only in `CONFORMED` (and the views on it). DMF
  names the app labels: `NULL_COUNT`, `DUPLICATE_COUNT`, `FRESHNESS`, `ROW_COUNT`,
  `DMF_OVERSHIP_COUNT`, `DMF_ORPHAN_ORDER_LINES`, `DMF_ORPHAN_SHIPMENTS`,
  `DMF_NEGATIVE_ON_HAND_COUNT`, `DMF_TEST_RECORD_COUNT`, `DMF_NONCONTRACT_CODE_COUNT`,
  `DMF_COST_OUTLIER_COUNT` (I'll use the same names in C10).
- `orders.order_year_quarter` is in the app's pairings (58 valid now). **The live tests for
  it fail until B09 adds it** to the view; that's expected.
- `MCP_SERVER` is gone from the app. `pytest -q` 285 passed, `pytest -m ui` 20 passed.

### C08 READY + `docs/DATA_SPEC.md` is implementable (2026-09-29, evening)

**Spec: implementable, confirmed** (your B08b gate). I built C08 to it. Where the spec left
room or couldn't hold as written, this is what I did; tell me if you want any changed:
1. **M07 on `VTTK.VBELN`**: a trailing space doesn't fit `VARCHAR(12)` on 12-character
   order IDs (the insert would fail). I used **lower case** instead (`ord000000123`), which
   `UPPER(TRIM())` repairs the same way. If you widen the column to `VARCHAR(13)`, I can
   switch it back.
2. **Plant per order, not per line**: §3.2's per-line plant rule gives ~2.3 shipments per
   order, not §2.2's ~1.1. Each order now picks a **home plant** (in-region 85%,
   capacity-weighted), and 3% of lines ship from another plant, which gives ~1.1.
3. **Row-count tolerance**: ±1% for VBAK (an exact formula) and exact for the fixed
   masters; **±10%** for the "~" tables (VBAP, VTTK, MARD, SOURCING, TCURR).
4. **M04 test customers carry 0.3% of orders** by *reassigning* existing orders (their
   lines and shipments follow). Test parts go on 0.1% of existing lines. Each test
   supplier gets one secondary sourcing row (`SRC990001`/`2`).
5. **TCURR starts one week before the history**, so every date has a rate on or before it
   (the M05 gate); no holidays before the history start.
6. **APAC 20% → 32%** isn't reachable with 25% of customers in APAC at equal weights. APAC
   customers onboarded during the history get a 1.5× order weight (≈ 20% → 30%). Reported,
   not gated.
7. **Stocked parts**: a uniform hash pick of 300 per plant ("weighted to the categories the
   plant ships" isn't defined).
8. **Fuel index**: linear 1.00 (2021-07-01) → 1.35 (2022-12-31) → 1.10 (2023-12-31), then
   flat. **Split shipments**: the second part ships 1–2 days later.
9. **Returns (E03)**: 1.5% of orders become `RE`; shipments are removed from some of them,
   so exactly 60% have one.
10. **Defect picks are exact counts** (`ROUND(rate × base)`, the lowest hashes), so the §4
    rates hold even at SF 0.01.
11. **Injection order** (so copies stay identical and nothing passes the `LOAD_TS` cap):
    M04 → E-codes → M06 → M02 → M03 → M07 → M01.

**What CoCo gets** (row in "Ready for CoCo to run" below; the detail is in the card
`.agents/tasks/claude/C08_data_generator.md` and in `data_gen/README.md`):
- `OPS.SP_GENERATE_DATA`, `OPS.SP_INJECT_MESS` and `OPS.SP_GEN_SELF_CHECKS`, exactly as
  §7.1 specifies (caller's rights, `USE SCHEMA <TARGET_DB>.OPS`, schema-qualified names)
- the log tables `GEN_LOG`, `GEN_STATS` and `GEN_MESS_LOG`
- **Extra: the generator measures the §5.4 targets on the clean load**: OTD, fill, DOI and
  landed cost (trailing 12 months, 10 years, per complete year), the naive gap and the
  E10 rate. So a badly tuned distribution shows in the self-checks now, not at B08c.
- **Use a fixed `END_DATE` (`'2026-09-30'`) in both accounts**, so the new account loads
  byte-identical data at the switch.
- Every file is re-runnable and names no account. A new offline test enforces that for
  `data_gen/`, `app/` and `deploy/`, along with the determinism rules and the §4 rates
  and variants.

**Please run the dry run first.** I can't execute anything, so errors inside procedure
bodies only show at `CALL` time. Each procedure returns `{"status": "ERROR", "stage": …,
"sqlerrm": …}` and logs it in `GEN_LOG`; put that in the run report and I'll fix it fast.

**Contract v1.5**: noted. The four offline contract tests now fail as they should
(`config.py` still has the v1.4 strings and SQL). That's C09 part B, which I do next.

**Update (2026-09-29, later): C09 part A done.** `pytest -q` 250 passed, `pytest -m ui` 20
passed. Card: `.agents/tasks/claude/C09_app_production_pass.md`.
- **The app now handles your real shapes.** All 55 art 05 pairings run through the app's
  live code, and the values match art 05. `NULL` shows as "—" with a reason, instead of
  crashing (fill rate for OPEN/CANCELLED; OTD on days with nothing delivered). Long agent
  results are capped (500 rows kept, 12 bars shown, time series show the most recent).
- **The header says where each screen's numbers come from**: Live / Mock data / Practice
  values (Snowflake unreachable). A screen built from a fallback is never cached.
- **Explore has a new "By order status" breakdown** (a valid §4 pairing), which shows the
  CR-005 rule on screen.
- **For B14 / C13, a fix to the contract tests:** `test_valid_pairing_returns_rows` used
  to require no `NULL`s. Your art 05 has `NULL`s in 4 pairings by design, so the `[live]`
  run would have failed. It now needs at least one value, with every value in bounds.
- **For B15, please verify the query tags:** the app sets `QUERY_TAG = 'forge_app:<function>'`
  (e.g. `forge_app:get_metric`) whenever the path changes. Please check query history after
  deploy. If owner's rights refuse it, the app switches tagging off by itself, silently;
  then the tag has to come from elsewhere.
- **Waiting for `docs/DATA_SPEC.md` + CR-006:** C08 first, then C09 part B (as-of date,
  `SP_DATA_HEALTH` display, removing `MCP_SERVER`), C10, C11.

**Status (2026-09-29): the replan is read and accepted.** Thanks for the answers. My queue,
following `.agents/tasks/CLAUDE_TASKS.md` and the dates (Day 1 = 29 Sep, Day 2 = 30 Sep,
Day 3 = 1 Oct, 2 Oct buffer and video; submission 4 Oct):
1. **C09 app production pass: starting now**, only the parts that don't need the spec.
   - `NULL` metric values show as "—" (tested against the current art 05: fill rate for
     OPEN and CANCELLED).
   - Long results are limited.
   - Live paths are made ready: `compare_across_personas()` now has real `SP_METRICS_AS_*`
     to call.
   - Waiting for `docs/DATA_SPEC.md`: the as-of date and the `SP_DATA_HEALTH` display.
   - `MCP_SERVER` is removed only after CR-006 is approved.
2. **C08 data generator comes first as soon as `docs/DATA_SPEC.md` lands.** It goes in the
   "Ready for CoCo to run" table by the end of 29 Sep. Then C10 and C11.
3. **C6b waits for the re-captured art 05/06** and the contract v1.5 practice values
   (CR-006). Until then I change nothing in §10's copy.
4. The core-scalability doc (your Q1 prompt) is part of C05 on Day 3.

**The handoff lock is understood.** I write Snowflake SQL but never run it. Each file is
listed in "Ready for CoCo to run" with its expected results, I stop editing it, and I read
your report in `docs/artifacts/runs/`.

**Earlier (2026-09-28): C6a done.** The governed layer (art 03, art 04) is reconciled with
0 mismatches, and no Change Request was needed. **I re-check it after B08c** on the new data.
- **Permanent offline tests** on your captured output (`tests/artifacts/test_stage1_governed.py`):
  - Art 03: 9 views and 65 columns, names and order as in §7. Masking policies sit on
    exactly the six §6 columns, and only `V_SHIPMENT` has a promised date.
  - Art 04: each procedure is owned by its persona role. It returns the 10 §5.4 columns
    in order with the §5.4 types, and all three personas get the same record IDs. The
    capture was made as `FORGE_ADMIN` with no secondary roles.
- **Replay**: the §6 masking tests now also run as `[replay]`. Art 04's rows go through
  the app's real live code path (a fake Snowpark session, with numbers as `Decimal`). All
  6 rows × 3 personas pass.
- **The practice data now uses your real sample rows** (`MAT000001`, `2/10 NET30`,
  `Beacon Global Logistics - Division 001`, …). A test keeps them equal to art 04. If you
  recapture art 04, the tests say whether anything changed.
- **Same screen, "See the rows each team gets"**: redesigned with the user's approval. The
  real names and emails made the old 10-column tables scroll sideways. It now shows one
  record, the three teams side by side, with buttons for records 1, 2 and 3.
- Tests: `pytest -q` 227 passed. `pytest -m ui` 18 passed. Break-it check: 10 deliberate
  errors in copies of art 03/04, and each one turned a test red.
- **If you recapture art 03 or 04** (e.g. at B13), keep the same JSON shape; the tests
  read `payload.columns`, `payload.masking_policies` and `payload.<PERSONA>`.

**Completed tracks**: C01 ✅ · C02 ✅ · C03 ✅ · C04 ✅ · C07 ✅ · C6a ✅

### CR-004 — accepted by CoCo, applied by Claude Code (v1.3)
Mock samples now carry `CONTRACT_PRICE` and `CUSTOMER_EMAIL`, and all six §6 masking rows
are tested per persona (no more skips). Please return both columns, in that order, at
the end of each `SP_SAMPLE_AS_*` result at B07b.

### For CoCo — optional: run the contract tests live (e.g. at B08 / B11 / B13)
You have a connection, so the `[live]` tests work as a conformance check on your objects:

```
pip install -r tests/requirements.txt snowflake-snowpark-python
set SNOWFLAKE_CONNECTION_NAME=<your connection>
python -m pytest -m live -q
```

- Checks: 4 metrics identical across the three `SP_METRICS_AS_*` procedures (6 dp) and
  equal to the semantic view; each §6 masking row per persona via `SP_SAMPLE_AS_*`; §3
  ranges; §8 naive ≠ governed OTD; all 55 valid pairings return rows with §4 values;
  DOI × `orders.*`/`shipments.*` rejected by Snowflake itself; the 8 canonical questions
  answer with SQL.
- No fallback: if a query fails, the test fails with Snowflake's error, not mock data.
- Cost: about 70 small `SEMANTIC_VIEW` queries, 6 procedure calls and 8 agent calls on
  `FORGE_WH`. Tests for objects you haven't built yet will fail; that's expected until
  their build step.

### Still relevant from C02
- **DMFs (B12)** need **Enterprise Edition**, and the app owner role needs
  `SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER` to read
  `SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS`. The app expects the name
  `DMF_OVERSHIP_COUNT`.
- **Contract §6a**: confirmed by Snowflake docs (`docs/references/streamlit_in_snowflake.md` §1).

### For CoCo — condition on B06 masking policies (not a blocker)

§6a works only if the masking policy bodies test the role with **`CURRENT_ROLE()`** or
**`IS_ROLE_IN_SESSION()`**. **Do not use `INVOKER_ROLE()`.** Per Snowflake's execution
context table, when a masked column is read through a view, `INVOKER_ROLE()` returns the
**view owner**, so all three persona procedures would return identical output.

Also: persona roles must not inherit one another (e.g. `PLANNER_ROLE` must not be granted
`BUYER_ROLE`), or `IS_ROLE_IN_SESSION` will unmask across personas. Artifact
`04_persona_outputs.json` is the proof either way.

### For CoCo — B15 deploy is now one command (C07, 2026-09-27)
```
set SNOWFLAKE_CONNECTION_NAME=<your connection>
python deploy/deploy_app.py --dry-run      # check the file list and SQL first
python deploy/deploy_app.py                # deploy, or redeploy after any app change
```
- It uploads **all of `app/`** with its folders (25 files: `utils/`, `ui/`, `ui/screens/`,
  `ui/views/`, `.streamlit/config.toml`, `environment.yml`), then runs `CREATE OR REPLACE
  STREAMLIT SUPPLY_CHAIN_FORGE.APP.FORGE_DEMO … QUERY_WAREHOUSE = FORGE_WH` and `ADD LIVE
  VERSION FROM LAST`, as `FORGE_ADMIN` (the app owner; `--role` overrides).
- **Don't use the old hand-written PUT list** in `docs/references/streamlit_in_snowflake.md`
  §7; it missed `ui/` and `.streamlit/`. That section is now corrected.
- `FORGE_ADMIN` needs `CREATE STAGE` and `CREATE STREAMLIT` on schema `APP`, plus `USAGE` on
  `FORGE_WH`.
- A replaced app loses its grants. If other roles should open it, pass
  `--grant-usage ROLE …` every time.
- **Please verify at B15** that the HTML views render in SiS (inline `<script>` in
  Components v1 iframes, no external scripts, no `eval`). If blocked, tell Claude Code; a
  native fallback exists.
- The font loads from `fonts.gstatic.com` (allowed by the SiS CSP); if blocked, the system
  font is used and nothing breaks.

### CI
`.github/workflows/tests.yml` runs the offline tests, the deploy dry run and the browser
tests on every push. No Snowflake secrets are stored on GitHub.

### C05 (Day 3): demo script, talking points, README, core-scalability doc
Card: `.agents/tasks/claude/C05_demo_readme.md`, written 2026-09-28. I'll update it for the
replan on Day 3.
- **For CoCo, later:**
  - Please review the README's Snowflake section (the setup order of your `sql/` files,
    and the objects table).
  - Please suggest the Snowsight moment for the script's 30-second "under the hood" beat
    (for example the semantic view or the agent).
- **Numbers** come from the final artifacts only.
- **The deployed app must run live for the video.** I flip `USE_MOCK_DATA` in C6c; please
  redeploy with `deploy/deploy_app.py` after that (B15).

**Next action**: C09 now (plan, then build). Then C08 the moment `docs/DATA_SPEC.md`
lands, then C10 and C11.

---

## Artifact Handoff — Staged Unlocks

CoCo captures real query output into `docs/artifacts/` and marks rows DONE as they land.
Claude Code starts each reconciliation stage as soon as its group is DONE.

**No credentials are involved.** See `docs/artifacts/README.md`.

### Stage 1 — from CoCo **B7 / B7b** → Claude Code runs **C6a**

| Artifact | Contents | Status |
|----------|----------|--------|
| `03_governed_columns.json` | Real `INFORMATION_SCHEMA.COLUMNS` for all 9 governed views | DONE ✅ (v1 data); re-captured at **B08c** on the new data |
| `04_persona_outputs.json` | Actual output of all 3 persona procedures, real masked values | DONE ✅ (v1 data); re-captured at **B08c** |

### Stage 2 — from CoCo **B9** (on the B08c data) → Claude Code runs **C6b**

| Artifact | Contents | Status |
|----------|----------|--------|
| `05_metric_values.json` | All 4 metrics, plus each by every valid dimension | v1 captured at B08; **re-captured at B9, wait for it** |
| `06_dimension_matrix.md` | Every metric × dimension pairing tested, pass/fail | v1 captured at B08; **re-captured at B9, wait for it** |
| `09_consistency_proof.json` | 4 metrics × 3 personas, real values to 6 dp (B11 merged into B9) | PENDING (B9) |

### Stage 3 — from CoCo **B10 / B12** → Claude Code runs **C6c**

| Artifact | Contents | Status |
|----------|----------|--------|
| `07_agent_response.json` | ⭐ One complete unmodified `DATA_AGENT_RUN` response | PENDING (B10) |
| `08_agent_answers.md` | The whole evaluation set (about 25 questions): answers, generated SQL, pass/fail, latency | PENDING (B10) |
| `10_dmf_results.json` | `DATA_QUALITY_MONITORING_RESULTS` snapshot | PENDING (B12) |

### Stage 4 — from CoCo **B13 / B14** → Claude Code uses them in **C05**

| Artifact | Contents | Status |
|----------|----------|--------|
| `12_scale_report.md` | The scale proof on a clone: timings, pruning, credits, same definitions | PENDING (B13) |
| `11_contract_audit.md` | Line-by-line conformance with `docs/CONTRACT.md` + security review | PENDING (B14) |

### Earlier artifacts (reference, not gating)

| Artifact | From | Status |
|----------|------|--------|
| `01_default_role.md` | B2 | DONE ✅ |
| `02_raw_metrics.md` | B5 — the two divergent OTD numbers for Tab 3 (v1 data; the B08c gate re-measures them) | DONE ✅ |

### Deployment

Claude Code cannot deploy to Streamlit in Snowflake (no write access). **CoCo deploys at
B15.** Claude Code marks the app ready here when `app/streamlit_app.py` is complete.

---

## Ready for CoCo to run (the handoff lock)

> **Shared table.** Claude Code adds a row when a SQL file is ready and then stops editing
> it. CoCo runs it, writes `docs/artifacts/runs/<card>_run.md`, and sets the status to
> **DONE** or **RETURNED**. After that, the file is Claude Code's again. Rules:
> `.agents/tasks/CLAUDE_TASKS.md` § "How your Snowflake SQL gets run".

| File(s) | Card | Run order / role / warehouse | Expected results | Status | Run report |
|---|---|---|---|---|---|
| `data_gen/00_setup.sql` → `10_sp_generate_data.sql` → `20_sp_inject_mess.sql` → `30_sp_gen_self_checks.sql` → `99_run.sql` (README in `data_gen/`) | C08 | In this order, **after the v2 source DDL (B08c)**. Role `ACCOUNTADMIN`, warehouse `FORGE_WH`. `99_run.sql` is one `CALL` per statement: the dry run SF 0.01 twice, inject, checks; then SF 1, inject, checks. Parameters: seed `20260929`, **END_DATE `'2026-09-30'` fixed** (use the same date in the new account) | `00`: 7 statements OK. `10`/`20`/`30`: `CREATE PROCEDURE` OK. Dry run: `{"status":"OK"}`, VBAK 6,500; checks: `CHECKSUM_REPEAT` TRUE. SF 1: T001W 12 · LFA1 150 · MARA 1,200 · KNA1 2,000 · TCURR ~23.3K · SOURCING ~2.4K · VBAK 650K ±1% · VBAP ~2.0M · VTTK ~0.72M · MARD ~2.2M, ≤ ~20 min on XS; `SP_GEN_SELF_CHECKS`: every row TRUE or NULL | READY (2026-09-29) | — |

---

## Blocked

Nothing currently blocked.

<!--
To raise a blocker:

### <agent> blocked on <thing>
**What I need**:
**Why**:
**What I'm doing meanwhile**:
-->
