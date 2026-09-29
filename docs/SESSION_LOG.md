# Session Log

> Append-only. Newest entry at the top.
> Write an entry every time you stop work so the next session can resume cleanly.

---

## Template

```
## Session N — YYYY-MM-DD — <Agent>

**Milestone**: M?
**Build steps completed**: B? → B?
**Credits used this session**: ?

### Done
-

### Blocked / Open
-

### Next action (exact)
-
```

---

## Session 26 — 2026-09-29 — Claude Code

**Milestone**: M6 (app production pass), replan Day 1
**Build steps completed**: C09 ✅ (part B, contract v1.5)
**Credits used this session**: 0

### Done
- **C09 part B**, building on the approved card:
  - `config.py` copies v1.5 (§3 strings, §3a window settings, `DATA_HEALTH_PROC`, no MCP,
    `orders.order_year_quarter`)
  - `forge_data`: windowed §5 and §8 SQL; one call per window; `get_data_health()`;
    quality judged by layer (`table_schema`)
  - screens: an as-of line on every screen (hidden in live if `SP_DATA_HEALTH` is
    missing), window labels in Explore, per-table freshness in Data health, 10 source
    tables in the catalog
- Tests: the 4 contract tests broken by v1.5 are green again; 13 new ones; pairings 55 →
  58. `pytest -q` 285 passed; `pytest -m ui` 20 passed; screenshots checked.

### Blocked / Open
- The live test for `orders.order_year_quarter` fails until B09 adds it.
- `SP_DATA_HEALTH` doesn't exist until B12 (C10 writes it); the app shows practice values
  until then.

### Next action (exact)
- C10: data-quality SQL + `SP_DATA_HEALTH` in `quality/` (plan, card, build, hand over).

### Resume notes for the next session (context was cleared here)
- **State**:
  - C08 is READY in the handoff lock; CoCo is planning B08c and hasn't run it yet (no
    `docs/artifacts/runs/` folder)
  - C09 is done
  - GitHub CI run #2 failed only on the 4 v1.5 contract tests, which the uncommitted C09
    work fixes. The user commits and pushes.
- **C10 inputs (already read once)**:
  - DATA_SPEC §7.2: the `SP_DATA_HEALTH` signature and JSON shape, the status rules, the DMF
    minimum table, the schedule (`TRIGGER_ON_CHANGES` else `USING CRON 0 6 * * * UTC`), and
    the agent tool YAML
  - `docs/references/data_metric_functions.md` and `agent_custom_tools.md`
- **Key facts from those**:
  - custom DMFs must `RETURNS NUMBER`, SQL only, deterministic; multi-table DMFs attach with
    `ON (col, TABLE(db.sch.t(col)))`
  - the schedule is per table (all DMFs share it)
  - `ROW_COUNT` must be attached `ON ()`
  - `FRESHNESS` on a view or dynamic table needs a column
  - results are in `SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS` (`table_schema`,
    `table_name`, `metric_name`, `argument_names`, `value`, `measurement_time`)
  - the `SP_DATA_HEALTH` tool is `type: generic`; resource `type: procedure`, identifier
    `…SP_DATA_HEALTH(VARCHAR)`
  - `EXECUTE AS OWNER` (owner `FORGE_ADMIN`); it must never return row values or masked
    columns; output under 16 KB
- **Names the app already expects** (keep them in C10): `DMF_OVERSHIP_COUNT`,
  `DMF_ORPHAN_ORDER_LINES`, `DMF_ORPHAN_SHIPMENTS`, `DMF_NEGATIVE_ON_HAND_COUNT`,
  `DMF_TEST_RECORD_COUNT`, `DMF_NONCONTRACT_CODE_COUNT`, `DMF_COST_OUTLIER_COUNT`.
  `forge_data.get_data_health()` calls `CALL …SP_DATA_HEALTH(?)` and reads the first
  column as JSON.
- **The same rules as C08**:
  - every file re-runnable on an empty account, naming no account
  - a header with card, role, warehouse, run order and expected results
  - hand over via the "Ready for CoCo to run" table
  - extend `tests/unit/test_data_gen_sql.py`-style static checks to `quality/`
- **Shell tip**: bash heredocs containing `'''` or backticks break in this environment;
  write Python edit scripts to the scratchpad with the Write tool, then run them.

---

## Session 25 — 2026-09-29 — Claude Code

**Milestone**: M3 (replan Day 1), the critical path
**Build steps completed**: C08 ✅ READY (handed to CoCo); B08b confirmation given
**Credits used this session**: 0 (no Snowflake access)

### Done
- Read B08b: `docs/DATA_SPEC.md`, `snowflake_execution_notes.md`, and the generation and
  scripting references. **Confirmed the spec is implementable** in HANDOFF, with 11
  decisions listed where it left room. Two were real conflicts:
  - M07's trailing space doesn't fit `VARCHAR(12)`; lower case is used instead
  - a per-line plant gives ~2.3 shipments per order, not ~1.1; an order-level home plant
    is used instead
- Wrote card C08 and built `data_gen/` (the user asked to plan and build it in one go):
  - `00_setup` (OPS log tables)
  - `10` `SP_GENERATE_DATA`: hash-only randomness; exact `NUMBER` sums; gap-free IDs;
    chunked by year; the §5.4 targets measured on the clean load
  - `20` `SP_INJECT_MESS`: exact-count picks for every §4 code, in a fixed order
  - `30` `SP_GEN_SELF_CHECKS`: counts, uniqueness, checksum repeat, targets, rates,
    data cross-checks, the `LOAD_TS` cap
  - `99_run`: dry run twice, then SF 1; fixed `END_DATE` for the account switch
  - `README.md`
- New offline checks, `tests/unit/test_data_gen_sql.py` (23): no `RANDOM()` or clock in the
  data; no account names in `data_gen/`, `app/` or `deploy/`; re-runnable DDL; headers;
  every §4 code at its rate; variants equal to §4.3. Checked they catch breakage.
- Handed over under the lock (HANDOFF "Ready for CoCo to run": READY).
- Updated `CLAUDE.md` to contract v1.5.

### Blocked / Open
- C08's live gate is CoCo's run report (B08c). Errors inside procedure bodies only show at
  `CALL` time, so the dry run comes first.
- **4 offline contract tests fail**: contract v1.5 changed the §3 strings, the §5 windows
  and the §8 queries. That's C09 part B, next.

### Next action (exact)
- C09 part B: the v1.5 definition strings and time windows in `config.py` / `forge_data.py`,
  the as-of date, the `SP_DATA_HEALTH` display, removing MCP. Then C10 and C11.

---

## Session 24 — 2026-09-29 — CoCo

**Milestone**: M3 (replan, Day 1)
**Build steps completed**: B08b delivered (gate waits for the user's CR-006 approval and Claude Code's confirmation)
**Credits used this session**: ~22.5 Cortex Code credits (~$45; main session plus 2 doc subagents)
and ~1.35 warehouse credits (~$4). The earlier "< 0.05" counted the warehouse only and was wrong.
See the credit check below.

### Done
- Planned B08b in plan mode. The user chose the time rule: **trailing 12 months** for flow
  metrics and the **latest snapshot** for DOI. Wrote card `coco/B08b_data_spec.md`.
- **`docs/DATA_SPEC.md`** (new, ~850 lines):
  - source DDL v2 (10 tables, incl. `ERP_SOURCE.TCURR`)
  - volumes (~650K orders, ~2M lines at SF 1) and realism rules
  - the mess catalogue: 7 repairable defects + 13 edge cases, each with its rate, rule and
    tolerance, plus the code map
  - the `CONFORMED` contract, the time rule and the metric targets
  - determinism rules
  - the interfaces: generator procedures, `SP_DATA_HEALTH`, eval set and runner, scale harness
- **CR-006 (PROPOSED)** in `CONTRACT.md` §11:
  - new §3 definition strings and a §3a time rule; §5 patterns and the §8 query get the window
  - new FQNs; MCP removed; 10 source tables; additive semantic-view content
- **Context pack** in `docs/references/`:
  - `snowflake_execution_notes.md` (CoCo, live-verified)
  - 6 fetched-doc files, drafted by 2 subagents and reviewed
  - README index rows
- **Live findings (read-only)**:
  - Enterprise edition
  - every v1 source column is `NOT NULL`, and IDs are `VARCHAR(10)`: both fixed in DDL v2
  - the SQL tool doesn't keep session variables or `USE ROLE` between calls
  - compile-only doesn't check procedure bodies
  - `RANDOM(seed)` is not reproducible (docs); the hash recipe gave identical checksums on
    5M rows on 2 warehouses
  - `SEMANTIC_VIEW WHERE` accepts the 12-month window and a latest-snapshot subquery
  - `GET_QUERY_OPERATOR_STATS` gives pruning counts
  - a custom DMF compiles

### Credit check (2026-09-29, from ORGANIZATION_USAGE / ACCOUNT_USAGE)
- **Allowance**: $400 of free usage, from 2026-09-17 to **2026-10-18**. When the balance hits
  zero or the end date passes, the account stops unless a card is added.
- **Spent**: ~$138. Cortex Code is ~$118 (58.9 credits × $2), warehouses ~$20 (6.5 credits ×
  $3), everything else < $1. **Left: ~$262.** `REMAINING_BALANCE_DAILY` shows $295.72 because it
  lags today's usage.
- **Spend per day**: 24 Sep $30, 25 Sep $19, 27 Sep $18, 28 Sep $14, 29 Sep ~$49 (so far).
- **Projection to 2 Oct**:
  - at ~$25/day: ~$100–120
  - at ~$50/day (a heavy day like today): ~$200
  - B13 scale proof: ~$6–10
  - agent evals: ~$5–15
  - DT/DMF/Search background: ~$1–3/day
- **Outcome**: enough to finish if CoCo stays lean, but tight if every day is like today.
- **After submission**: with schedules suspended, keeping the app live costs ~$1–3/day. The hard
  limit is **18 Oct**, not the balance.
- **Levers**:
  - lean CoCo sessions (the main cost)
  - COMPUTE_WH auto-suspend 600 s → 60 s
  - a resource monitor for warehouses and an account budget alert for everything else
  - DT target lag ≥ 1 h or DOWNSTREAM
  - DMFs on TRIGGER_ON_CHANGES or a daily cron
  - Cortex Search TARGET_LAG 1 day
  - B13 on MEDIUM for ≤ 30 min, then drop the clone
  - suspend all schedules after submission

### Also done this session (after B08b)
- **Credit check** (above). Corrected the stale budget line in `COCO.md`.
- **Account switch plan**, user-approved, in `COCO.md` ("Account switch plan"), with:
  - a new B8m entry in `COCO_TASKS.md` and the B08m row in `.agents/NEXT.md`
  - a HANDOFF note to Claude Code: scripts must re-run cleanly on an empty account and must
    not name the account
  - the timeline: build in the old account until the end of 1 Oct (incl. B13); B08m trial
    move 30 Sep; cutover at the end of 1 Oct; B14/B15 on 2 Oct in the new account
- **New event account created** by the user and added as a VS Code connection. Read-only
  checks only:
  - region Azure Central India, same Snowflake version, `CORTEX_ENABLED_CROSS_REGION =
    ANY_REGION`
  - edition not confirmed (needs ORGADMIN; the user can check it in Snowsight)
  - nothing was created there; the account details get recorded at B08m, as the user asked
- **CR-006 ACCEPTED** by the user and applied in the `CONTRACT.md` body as **v1.5** (§1,
  §3, §3a, §4, §5, §7, §8, §10). Added one line: metrics with different default windows need
  separate `SEMANTIC_VIEW` calls. Updated NEXT, HANDOFF, the B08b card and COCO_TASKS.
  HANDOFF asks Claude Code to update the "v1.4; CR-006 pending" line in `CLAUDE.md`.

### Blocked / Open
- ~~CR-006 needs the user's approval~~ ✅ accepted (v1.5).
- Claude Code to confirm in HANDOFF that DATA_SPEC is implementable (B08b gate 2).
- The user to confirm the new account's edition is Enterprise (Snowsight → Admin → Accounts).

### Next action (exact)
- **New CoCo session** on the old connection `tyduokn-gf25237`: B09 (semantic view v2, by
  hand, on today's data), then B09a. B08c when C08 is READY. B08m trial move on 30 Sep.
- Claude Code: C08 (critical path; READY by end of Day 1), C09 part B (unblocked by v1.5),
  C10, C11.

---

## Session 23 — 2026-09-29 — Claude Code

**Milestone**: M6 (app production pass), Day 1 of the replan
**Build steps completed**: C09 part A ✅
**Credits used this session**: 0 (no Snowflake access)

### Done
- Read the replan (CLAUDE.md, NEXT, HANDOFF, CLAUDE_TASKS, COCO_TASKS, ROADMAP, ADR-008).
  My questions were answered in HANDOFF: deadline 4 Oct (work done by 2 Oct), the
  scalability-doc prompt, §10 practice values via CR-006.
- Updated my HANDOFF section for the replan; wrote the C09 card; the user approved it.
- **Built C09 part A**:
  - `NULL` handled everywhere (`config.as_number`, "—" with a reason; JSON NaN safety net
    in `view.build`)
  - Explore "By order status"
  - long results capped (agent tables 500 rows + true counts; 12 bars; the most recent 12
    for time series)
  - an honest source badge, and fallbacks never cached
  - query tags per path
  - replay of all 55 art 05 pairings and the whole app in live mode
- Fixed the pairing contract test, which rejected the `NULL`s real Snowflake returns.
- `pytest -q` 250 passed, 112 skipped; `pytest -m ui` 20 passed; screenshots checked in
  light and dark.

### Blocked / Open
- `docs/DATA_SPEC.md` + CR-006 (CoCo B08b) not landed yet: C08 (critical path), C09 part B,
  C10 and C11 wait for them.
- Query tags under owner's rights: CoCo checks at B15.

### Next action (exact)
- When `docs/DATA_SPEC.md` lands: plan C08, write its card, get approval, build it, and
  list it in "Ready for CoCo to run" by the end of 29 Sep.

---

## Session 22 — 2026-09-29 — CoCo

**Milestone**: M3 (replan)
**Build steps completed**: none (a user-approved replan of the remaining queue)
**Credits used this session**: small (one read-only profiling query)

### Done
- **Replanned the rest of the project with the user.** Goal: 3 days to production-ready
  and deployed. The core system (question → agent → semantic view → SQL → governed data →
  answer) must stay correct, fast and cheap from today's data to billions of rows, and while
  data changes. Only infrastructure knobs change with scale.
- **Profiled the live source data**: 1 year of orders, 30 days of inventory, 0 orphans,
  0 duplicates, 0 NULLs, 0 impossible values, one spelling per code, no currencies. It's
  clean and small, not realistic.
- **The user's decisions**:
  - Claude Code writes seeded SQL generators in `data_gen/`; CoCo reviews and runs them
  - both repairable mess and business-rule edge cases
  - 10 years at moderate size in the main DB, plus a scale proof on a clone
  - MCP dropped
  - the parallel multi-part router is a stretch item only
- **Rewrote `.agents/tasks/COCO_TASKS.md`**:
  - 9 core system rules at the top, and a 3-day plan
  - new steps B08b (data spec + CR-006), B08c (load + `CONFORMED` layer), B09 v2, B10
    (agent + evaluation set), B12, B13 (scale proof), B14 (audit + security), B15 (hardening
    + deploy)
  - removed: B07c, MCP, B11 (merged into B09), B16, B17
- **Updated**:
  - `.agents/NEXT.md` (new sequence and progress)
  - `.agents/HANDOFF.md`: the replan and requests to Claude Code (take ownership of
    `data_gen/`, C08 generator, C09 app pass, C6b to wait for the re-capture, stretch
    router), plus the new artifact stages
  - `docs/artifacts/README.md` (schedule, MCP upgrade path removed)
  - `docs/MILESTONES.md` (M3–M6 redefined)
  - `docs/LLD.md` (§7a dropped, §8 re-aligned)
  - `.agents/DECISIONS.md` (ADR-008; ADR-007 superseded)
- **New `docs/ROADMAP.md`**: post-hackathon productization, parked and gated on customer
  demand (source adapters, configurable metrics, per-user identity, Native App packaging,
  scale and cost, operations).
- **Deleted 5 TODO-only placeholders**: `mcp/01_mcp_server.sql`,
  `semantic/supply_chain.yaml`, `semantic/verified_queries/canonical_metrics.yaml`,
  `agent/supply_chain_agent.yaml`, `sql/05_quality/dmf_checks.sql`. All are recoverable
  from git; nothing referred to them.

### Blocked / Open
- C08 (Claude Code) is on the critical path and needs `docs/DATA_SPEC.md` from B08b.
- Contract body unchanged; CR-006 is written at B08b for the user's approval.

### Next action (exact)
- CoCo: **B08b**. Plan it, write the card `coco/B08b_data_spec.md`, write
  `docs/DATA_SPEC.md` and CR-006.
- Claude Code: read the replan in HANDOFF; write the C08/C09 cards; start C09 now and C08
  once `DATA_SPEC.md` lands.

### Later the same session: the work split re-done (user-approved)
- **The user's decisions**:
  - expose every governed business column in the one semantic view, as long as it stays
    fast
  - build a metadata-driven view generator now
  - include a Cortex Search service on names and a data-health tool for the agent
  - Claude Code takes on more work, including writing Snowflake SQL
- **Checked Claude Code's answer on "dynamic" semantic views.** Mostly right. Two
  corrections: B08 is already done (the expansion is B09), and splitting the view by domain
  would break cross-system questions (Cortex Agents don't join across semantic views).
- **Verified live with `cortex analyst query`**: Analyst aggregates exposed facts without
  a named metric. "Total landed cost by carrier" became `SUM(freight + duty + handling)`,
  and "shipments per carrier" became an ad-hoc `COUNT`.
- **Rewrote**:
  - `.agents/tasks/COCO_TASKS.md`: the new split, the ownership table, the handoff lock, B8b
    (+ context pack + interfaces), new B9a (generator + name search), B9 expansion scope and
    speed gate, and B10/B12/B13/B14 now run Claude Code's files
  - `.agents/tasks/CLAUDE_TASKS.md` (with the user's permission): C08–C14 with inputs,
    outputs, acceptance checks and references; done tracks kept as history
  - `CLAUDE.md` Boundaries (with the user's permission): new folders `data_gen/`, `quality/`,
    `eval/`, `tests/scale/`; writes SQL, never runs it; the handoff lock
  - `.agents/NEXT.md`, `.agents/HANDOFF.md` (+ the shared "Ready for CoCo to run" table),
    `docs/artifacts/README.md` (`runs/` reports), `docs/MILESTONES.md` (owners)

### Next action (exact, supersedes the above)
- CoCo: **B08b**. Plan it, write the card, then `docs/DATA_SPEC.md`, the reference files in
  `docs/references/`, and CR-006.
- Claude Code: read HANDOFF "Latest from CoCo" and `CLAUDE_TASKS.md`; plan and start
  **C09** now; C08, C10, C11 once `DATA_SPEC.md` lands.

---

## Session 21 — 2026-09-28 — CoCo

**Milestone**: M3 (semantic layer)
**Build steps completed**: B08 (semantic view, art 05/06, `SP_METRICS_AS_*`)
**Credits used this session**: small (about 180 `SEMANTIC_VIEW` queries on `FORGE_WH` XS)

### Done
- Wrote and approved the card `.agents/tasks/coco/B08_semantic_view.md`.
- **`SEMANTIC.SUPPLY_CHAIN_SV`** (`semantic/01_semantic_view.sql`), created by `FORGE_ADMIN`:
  - 9 tables, 10 relationships, 24 dimensions (§4's 23 plus `orders.order_week`), 4 metrics with synonyms and §3 comments.
  - Built in 4 stages; each stage's metric matched B07 exactly.
  - CR-005 is implemented with two `PRIVATE` facts on `order_lines` that read `orders.order_status`, so no CR was needed.
- **`SELECT` on the view** granted to the 3 persona roles (`COPY GRANTS` keeps it across re-runs).
- **`GOVERNED.SP_METRICS_AS_{PLANNER,BUYER,LOGISTICS}()`** (`sql/04_governance/05_persona_metric_procedures.sql`): owner's rights, owned by the persona roles, `USAGE` to `FORGE_ADMIN`.
- **Art 05** `05_metric_values.json`: 4 overall values plus the 55 valid pairings in full. SHA-256 `02eb2c2e…b814b2a5` matches Snowflake.
- **Art 06** `06_dimension_matrix.md`: 96 cells, with pass/fail and the error text.
- **Gate, all 7 checks pass** (see the card):
  - OTD 0.873973, fill rate 0.926485, DOI 28.499215, landed cost 518.971250, identical to 6 dp across the view (as `FORGE_ADMIN` and each persona alone) and the 3 procedures.
  - 55/55 valid pairings pass.
  - DOI × `orders.*`/`shipments.*` are rejected by Snowflake (9/9).

### Blocked / Open
- **`suppliers.*` × fill rate / DOI runs but fans out** through `sourcing`. It's not a §4 pairing, so the contract is unaffected. Carried into B09's `AI_SQL_GENERATION`.
- **Data observations, recorded in art 06 for C6b**: shipments cover 6 of 12 plants, and fill rate is exactly 1.000 for 3 of the 6 categories.

### Next action (exact)
- CoCo: B09. Plan it and write the card `B09_verified_queries.md`, then add the AI instructions and the 8 verified queries to `SUPPLY_CHAIN_SV`.
- Claude Code: C6b is unlocked (art 05/06).

---

## Session 20 — 2026-09-28 — Claude Code

**Milestone**: M6 (planning the demo and submission docs)
**Build steps completed**: C05 card written (not built)
**Credits used this session**: 0

### Done
- Wrote `.agents/tasks/claude/C05_demo_readme.md`. It covers a timed 5-minute
  `demo/demo_script.md` over the real app screens, `demo/talking_points.md`, the repo
  `README.md`, and README screenshots. Pass 1 happens now (provisional numbers); pass 2
  after C6b/C6c and B15 (final numbers, live screenshots, a timed rehearsal).
- Found: the current `demo/demo_script.md` describes the old tabbed app (persona
  dropdown, "Consistency Proof" tab) and column names that don't exist. There is no
  `README.md` yet.
- Noted a dependency: `USE_MOCK_DATA` must be flipped (C6b/C6c) and the app redeployed
  before the video is recorded.

- **The user deferred C05 until all other tasks are complete.** The card stays as
  written, and approval is asked again then.

### Blocked / Open
- C6b is waiting for art 05/06 (CoCo B08, in progress).
- Before C05: the user confirms the Hack2Skill submission rules (video length limit,
  upload location, deadline with time zone, README/repo requirements).

### Next action (exact)
- When art 05/06 land: plan C6b, write its card, and get approval.

---

## Session 19 — 2026-09-28 — Claude Code

**Milestone**: M3 (Stage 1 reconciled)
**Build steps completed**: C6a ✅
**Credits used this session**: 0 (no Snowflake access; everything offline)

### Done
- **C6a approved by the user and built.** Art 03 and art 04 match the contract, with 0
  mismatches, so no Change Request is needed.
- `config.py`: added `SAMPLE_COLUMNS` (§5.4) and `GOVERNED_COLUMNS` (§7). Unit tests
  compare both with the contract's table text.
- `tests/conftest.py`:
  - `artifact` fixture: loads `docs/artifacts/*`, and skips while a file is missing.
  - `ReplaySession`: answers the `SP_SAMPLE_AS_*` calls with art 04's rows, typed like
    Snowpark (`Decimal`, `None`).
  - A `[replay]` mode for the `forge` fixture.
- `tests/governance/test_masking.py`: every §6 row now also runs as `[replay]`.
- `tests/artifacts/test_stage1_governed.py`, 16 tests:
  - Art 03: view columns and order, masking policy placement, promised date only on
    `V_SHIPMENT`.
  - Art 04: procedure owners, §5.4 columns and types, identical record IDs, caller role.
  - Practice data equals art 04 through the live path.
  - The Same screen chips and the rows drawer follow the real rows.
- `mock_data.masking_sample()` now returns the real captured rows, masked per §6.
- The **Same screen's rows drawer** was redesigned, with the user's choice. With real
  data, the 10-column tables wrapped names onto 5 lines and cut off the email column. It
  now shows one record, the three teams side by side, with Record 1/2/3 buttons. Masked
  values read "hidden", "restricted" or "masked" with a lock icon. The browser test checks
  for no sideways overflow and switches records.
- Break-it check (scratchpad, not committed): 10 errors planted in copies of art 03/04,
  and each turned a test red.
- `pytest -q` 227 passed, 112 skipped (live). `pytest -m ui` 18 passed. Screenshots checked
  in light and dark.

### Blocked / Open
- C6b needs art 05/06 (CoCo B08). C6c needs art 07–09.

### Next action (exact)
- C05: plan the demo script and README, write `.agents/tasks/claude/C05_*.md`, and get
  approval.

---

## Session 18 — 2026-09-27 — CoCo

**Milestone**: M2 (Governance Layer) complete
**Build steps completed**: B07b ✅ (and contract v1.4)
**Credits used this session**: < 0.01

### Done
- **CR-005 accepted by the user.** Contract is now **v1.4**: the §3 `fill_rate` definition excludes OPEN and CANCELLED orders.
- **Scope decision (the user's):** `SP_METRICS_AS_*` move to the end of B08, because they need `SUPPLY_CHAIN_SV`. The B8 section of COCO_TASKS.md lists everything carried in.
- **B07b:** wrote `sql/04_governance/04_persona_procedures.sql`.
  - 3 owner's-rights `SP_SAMPLE_AS_*` procedures with identical bodies, each owned by its persona role, with `USAGE` granted to `FORGE_ADMIN`.
  - `PERSONA` is derived from `CURRENT_ROLE()`, so every result shows which role the procedure ran as.
- **Gate passed** (as `FORGE_ADMIN`):
  - 3 rows per procedure, with the same IDs everywhere.
  - The 10 §5.4 columns in order (checked with `DESCRIBE RESULT`).
  - Masking matches §6 for all 6 columns.
  - Persona roles on their own can't read source tables.
- **Captured art 04** (`docs/artifacts/04_persona_outputs.json`); its SHA-256 matches Snowflake's hash of the result. **Stage 1 is complete, so Claude Code's C6a is unlocked.**
- **Found while running the gate:**
  - In this session, `USE ROLE` stopped carrying over between separate statements. Role-switched checks now run inside one `EXECUTE IMMEDIATE` block.
  - The user has **secondary roles = ALL** (including `ACCOUNTADMIN`), which lets a persona session read source tables. With secondary roles off, persona roles are denied.
  - Masking is unaffected, because it uses `CURRENT_ROLE()`. B07's access check was re-run with secondary roles off, and it passes.

### Blocked / Open
- Nothing blocked.

### Next action (exact)
- **CoCo**: plan B08 (semantic view → art 05/06, then `SP_METRICS_AS_*`).
- **Claude Code**: C05; C6a is unlocked; update the `fill_rate` definition string in `config.py` (v1.4).

---

## Session 17 — 2026-09-27 — CoCo

**Milestone**: M2 (Governance Layer)
**Build steps completed**: B07 ✅
**Credits used this session**: < 0.01

### Done
- **B07 (Governed views)**:
  - Wrote `sql/04_governance/03_governed_views.sql`: 9 conformed views in `GOVERNED`, owned by `ACCOUNTADMIN` (it owns the source tables; `FORGE_ADMIN` has no `SELECT` on them). Masking policies and tags are attached **inline** in `CREATE OR REPLACE VIEW`, so each view is created with its masking in one atomic statement and the script can be re-run. `SELECT` on all views granted to `FORGE_ADMIN` and the 3 persona roles.
  - `V_ORDER` does not expose ERP `ERDAT`; `V_SHIPMENT.promised_delivery_date` (TMS) is the only promised date.
  - GAP-2 time columns (`order_year/quarter/month/week`) go into B08 as semantic-view dimension expressions, so `V_ORDER` stays exactly §7.
  - Gate passed:
    - 9 views.
    - 65/65 columns match §7 in name and order.
    - The full §6 matrix holds on every row, per role (with `CURRENT_ROLE()` shown in each result).
    - View row counts equal source row counts.
    - The 4 metrics are identical across all 3 personas to 6 dp.
  - Captured `docs/artifacts/03_governed_columns.json`: columns plus `POLICY_REFERENCES`. Its SHA-256 matches Snowflake's hash of the captured result.
- **Found at the metric check**:
  - Fill rate as §3 defines it is 0.787449 over all lines, below the §3 range. The artifact 02 value of 0.9265 excluded OPEN and CANCELLED orders.
  - Raised **CR-005 (PROPOSED)** in CONTRACT §11 to make that exclusion explicit.
  - Days of inventory as §3 defines it is 28.499215. Artifact 02's 28.51 was an average of per-row ratios; no CR is needed, and B08 will use the §3 formula.

### Blocked / Open
- ~~CR-005 needs a decision~~ Accepted in Session 18 (contract v1.4).

### Next action (exact)
- **CoCo**: B07b (`.agents/tasks/coco/B07b_persona_procedures.md`), the 6 persona procedures and artifact `04_persona_outputs.json`.

---

## Session 16 — 2026-09-25 — CoCo

**Milestone**: M2 (Governance Layer)
**Build steps completed**: B06 ✅
**Credits used this session**: < 0.01

### Done
- **B06 (Governance Tags & Masking Policies)**:
  - Authored `sql/04_governance/01_tags.sql`:
    - Created 5 object tags in `GOVERNED` schema with strict allowed value lists: `ENTITY_TYPE`, `SOURCE_SYSTEM`, `SENSITIVITY`, `PII`, `METRIC_FAMILY`.
    - Applied governance tags across all 9 source tables and key columns. Cleaned up old placeholder files.
  - Authored `sql/04_governance/02_masking_policies.sql`:
    - Created 4 dynamic column masking policies in `GOVERNED` schema:
      - `MASK_SUPPLIER_COST`: Protects unit cost and contract price (visible to `FORGE_ADMIN`, `BUYER_ROLE`, `ACCOUNTADMIN`; `NULL` for others).
      - `MASK_PAYMENT_TERMS`: Protects payment terms (visible to `FORGE_ADMIN`, `BUYER_ROLE`, `ACCOUNTADMIN`; `'*** RESTRICTED ***'` for others).
      - `MASK_CUSTOMER_PII`: Protects customer name and email (visible to `FORGE_ADMIN`, `PLANNER_ROLE`, `LOGISTICS_ROLE`, `ACCOUNTADMIN`; `'*** MASKED ***'` for `BUYER_ROLE`).
      - `MASK_CREDIT_LIMIT`: Protects financial credit limits (visible to `FORGE_ADMIN`, `ACCOUNTADMIN`; `NULL` for all 3 personas).
    - Formulated with `CURRENT_ROLE()` per Contract v1.3 §6a for owner's-rights procedure compatibility.
  - Verified in Snowflake that all 5 tags and 4 masking policies exist in `GOVERNED` schema.
  - Authored task card `.agents/tasks/coco/B07_governed_views.md`.
  - Updated `.agents/NEXT.md`, `.agents/HANDOFF.md`, and `.agents/tasks/COCO_TASKS.md`.

### Blocked / Open
- Nothing blocked.

### Next action (exact)
- **CoCo**: Execute **B07** (`.agents/tasks/coco/B07_governed_views.md`) — create 9 conformed views in `GOVERNED` schema, attach masking policies, and capture artifact `docs/artifacts/03_governed_columns.json`.

---

## Session 15 — 2026-09-25 — CoCo

**Milestone**: M1 (Data Foundation Complete) → M2
**Build steps completed**: B05 ✅
**Credits used this session**: < 0.01

### Done
- **B05 (Distribution Verification & Artifact Capture)**:
  - Wrote SQL verification script `sql/03_sample_data/03_verify_distributions.sql`.
  - Executed sanity check queries in Snowflake confirming all four canonical metrics sit strictly within Contract v1.3 ranges:
    - **On-Time Delivery (OTD)**: `0.8740` (87.40% vs target 84%–90%)
    - **Order Fill Rate**: `0.9265` (92.65% vs target 90%–95%)
    - **Days of Inventory (DOI)**: `28.51` days (vs target 15–45 days)
    - **Average Landed Cost**: `$518.97` (vs target $150–$900)
    - **The Tab 3 Divergence Delta**: `78.36%` naive ERP OTD vs `87.40%` authoritative TMS OTD (**9.04% discrepancy delta** caused by the 20% date conflict rate).
    - **Integrity**: 0 overshipping violations, 250 of 250 parts have primary suppliers.
  - Captured artifact `docs/artifacts/02_raw_metrics.md` containing all verified baseline tables, regional breakouts, and divergence statistics.
  - Authored task card `.agents/tasks/coco/B06_tags_masking.md` for Milestone M2 (Governance Layer).
  - Updated tracking in `.agents/NEXT.md`, `.agents/HANDOFF.md`, and `.agents/tasks/COCO_TASKS.md`.

### Blocked / Open
- Milestone M1 (Data Foundation) is 100% complete!
- Nothing blocked.

### Next action (exact)
- **CoCo**: Execute **B06** (`.agents/tasks/coco/B06_tags_masking.md`) — create 5 governance tags and 4 dynamic column masking policies in `GOVERNED` schema.

---

## Session 14 — 2026-09-25 — CoCo

**Milestone**: M1 (Data Foundation)
**Build steps completed**: B03 ✅, B04 ✅
**Credits used this session**: < 0.05

### Done
- **B03 (Source Tables DDL)**:
  - Wrote `sql/02_tables/01_srm_source.sql` (`LFA1`, `MARA`, `SOURCING`), `02_wms_source.sql` (`T001W`, `MARD`), `03_erp_source.sql` (`KNA1`, `VBAK`, `VBAP`), and `04_tms_source.sql` (`VTTK`).
  - Executed all DDL in Snowflake and verified 9 tables created matching `docs/LLD.md` §2. Cleaned up old placeholder files.
- **B04 (Data Generation)**:
  - Authored `sql/03_sample_data/01_generate_masters.sql` and `02_generate_transactions.sql`.
  - Populated 12,452 total records in strict Foreign Key order across all 9 tables:
    - `LFA1`: 60 suppliers
    - `MARA`: 250 parts (6 categories)
    - `SOURCING`: 400 contracts (250 primary, 150 secondary)
    - `T001W`: 12 plants (4 APAC, 4 EMEA, 4 AMER)
    - `KNA1`: 120 customers (3 segments)
    - `VBAK`: 800 orders (12-month span with Q4 seasonal volume surge)
    - `VBAP`: 2,400 order lines (3 lines/order)
    - `VTTK`: 880 shipments (1 to 2 shipments/order, 70 in-transit)
    - `MARD`: 9,000 inventory snapshots (12 plants × 25 sampled parts × 30 days)
  - Verified statistical calibration against Contract v1.3:
    - **OTD Rate**: `0.8740` (87.4% vs target 84%–90%)
    - **Fill Rate**: `0.9265` (92.7% vs target 90%–95%)
    - **Days of Inventory (DOI)**: `28.51` days (vs target 15–45 days)
    - **Avg Landed Cost**: `$518.97` (vs target $150–$900)
    - **Date Discrepancy Hook**: `20.00%` (deliberate conflict rate between ERP `ERDAT` and TMS `PROM_DLV_DT`)
    - **Naive vs Authoritative OTD**: `78.36%` naive ERP OTD vs `87.40%` authoritative TMS OTD (9.04% divergence for Tab 3 demo)
    - **Integrity**: 0 overshipped lines (`QTY_SHIPPED <= KWMENG`), exactly 250 primary parts.
- Authored task card `.agents/tasks/coco/B05_verify_distributions.md`.
- Updated `.agents/NEXT.md`, `.agents/HANDOFF.md`, and `.agents/tasks/COCO_TASKS.md`.

### Blocked / Open
- Nothing blocked.

### Next action (exact)
- **CoCo**: Execute **B05** (`.agents/tasks/coco/B05_verify_distributions.md`) — capture artifact `docs/artifacts/02_raw_metrics.md` and complete distribution verification.

---

## Session 15 — 2026-09-27 — Claude Code

**Milestone**: M2 → M3
**Build steps completed**: contract v1.4 applied (CR-005, `fill_rate` definition)
**Credits used this session**: 0

### Done
- Read CoCo's message: B07 and B07b done, Stage 1 artifacts (03, 04) DONE, contract v1.4.
- `app/utils/config.py`: `fill_rate` definition now matches §3 v1.4 verbatim. New unit
  tests compare `config.py` with the contract's Python blocks (§2, §3, §10). 188 passed.
- First comparison of art 03 and art 04 against §5.4, §6 and §7: **0 mismatches**.
- Wrote the C6a card. **The user put it on hold** (not approved).

### Blocked / Open
- The user is unavailable 28–30 Sep (interviews). Then about 4 working days to
  submission. The plan to finish in that time is in the user conversation, and the
  priority order is recorded below.

### Next action (exact)
When the user is back:
1. **CoCo**: B08 (semantic view + `SP_METRICS_AS_*`) → B09 → B10 → B11 → B15 deploy.
2. **Claude Code**: C6a (approve and run) → C6b / C6c as art 05–09 land → C05 docs.
3. Last day: rehearsal, video, submission.

---

## Session 14 — 2026-09-27 — Claude Code

**Milestone**: M2
**Build steps completed**: C07 ✅ (CI + deploy script)
**Credits used this session**: 0

### Done
- The user asked whether the project covers CI/CD. It didn't, and the documented deploy
  steps (`docs/references/streamlit_in_snowflake.md` §7) missed `ui/` and `.streamlit/`,
  so the app would have failed to start at B15. Corrected.
- `deploy/deploy_app.py`: one command uploads all of `app/` and (re)creates
  `SUPPLY_CHAIN_FORGE.APP.FORGE_DEMO`, with `--dry-run`, `--role` and `--grant-usage`.
  10 offline tests with a fake session.
- `.github/workflows/tests.yml`: `pytest -q`, the deploy dry run and `pytest -m ui` on
  every push; screenshots kept as a build artifact. No Snowflake secrets on GitHub.
- Verified in a fresh venv built only from the requirements files: 186 passed, 18 browser
  tests passed.
- CLAUDE.md: Claude Code also owns `deploy/` and `.github/`.

### Blocked / Open
- The first GitHub Actions run happens when the user pushes. Check the Actions tab.

### Next action (exact)
**Claude Code**: waiting on the user's choice of the CoCo tasks to take over (B11 script,
B13 audit, M6 tricky-question tests, B17 review, and B12/B14 files if CoCo hands them
over), or C05.

---

## Session 13 — 2026-09-25 — Claude Code

**Milestone**: M2
**Build steps completed**: C04 ✅
**Credits used this session**: 0 (no Snowflake access)

### Done
- Wrote the C04 card, explained it in plain English, and got the user's approval.
- **Contract tests**: `tests/consistency`, `governance`, `semantic` and `agent`. Each runs
  as `[mock]` and `[live]` through the `forge` fixture (`tests/conftest.py`). Live skips
  without a Snowflake session, and a live fallback to mock data fails the test.
- **Source isolation**: offline checks that only the §8 naive query touches `*_SOURCE`
  and that every statement matches a contract pattern.
- **Browser suite** (`pytest -m ui`): starts Streamlit, drives Chromium through every
  screen in light and dark at 1366 and 1600 px, runs the C03 interactions, checks for JS
  errors and sideways scrolling, and saves screenshots to `tests/ui/_screenshots/`.
- `pytest.ini` (markers mock / live / ui; `ui` excluded by default), `tests/requirements.txt`.
  Removed the per-file `sys.path` setup and moved the contract checks out of the C02 unit tests.
- **CR-004 raised** (user approved): add `CONTRACT_PRICE` and `CUSTOMER_EMAIL` to the
  sample procedures so all six §6 masking rows can be checked per persona.
- Break-it check: each broken rule turned its test red (recorded in the card).
- Stopped the user's running Streamlit app, as asked.
- Results: `pytest -q` 170 passed, 118 skipped; `pytest -m ui` 18 passed.

- **CR-004 accepted by CoCo (contract v1.3) and applied**: mock samples carry the two new
  columns; all six masking rows are tested. `pytest -q` 176 passed, 112 skipped.

### Blocked / Open
- None.
- ~~Layout at 1366 px~~ **Fixed at the user's request:** header and "next" columns now size
  to their labels, the header never wraps, and The problem and The fix views are taller
  so nothing is cut off at 1280 px. Browser checks now cover 1280, 1366 and 1600 px
  (18 passed).

### Next action (exact)
**Claude Code**: C05. Plan the demo script and README in plain English, write
`.agents/tasks/claude/C05_demo_docs.md`, get approval, then build.

---

## Session 12 — 2026-09-25 — Claude Code

**Milestone**: M2
**Build steps completed**: none (housekeeping before C04)
**Credits used this session**: 0

### Done
- User reviewed C03 Revision 2 in the running app and approved it ("looks good").
- Rewrote `CLAUDE.md` (local, gitignored). It now points to NEXT.md, HANDOFF.md, the
  contract and the cards instead of restating them, and it records the current app
  architecture, run/test commands and gotchas. Removed stale content: contract v1.1, the
  old metric formulas, `persona_queries.py`, and the "wait for CoCo" rule.
- Read CoCo's updates: B02 done, 9 source tables confirmed, artifact `01_default_role.md`
  (persona roles don't inherit each other, as the masking design requires).

### Next action (exact)
**Claude Code**: C04. Plan in plain English, write `.agents/tasks/claude/C04_tests.md`,
get approval, then build.

---

## Session 11 — 2026-09-24 — Claude Code

**Milestone**: M2
**Build steps completed**: C03 Revision 2 ✅
**Credits used this session**: 0 (mock mode only)

### Done
- **User review of C03:** the built app looked older and more cramped than the approved
  prototype, the Ask bar looked old-fashioned, screens weren't full width, and header menu
  clicks only worked around the text.
- **Click bug fixed:** Streamlit's invisible fixed top bar was covering the menu. Verified
  by clicking directly on the text with Playwright.
- **CoCo accepted CR-002 and CR-003** (contract v1.2). Applied: Q8 is now "Which plants have
  the worst on-time delivery?"; the persona metric procedures are official.
- Installed Anthropic's `webapp-testing` skill + Playwright/Chromium (local `.venv`, skill
  in gitignored `.claude/skills/`).
- **Rebuilt** The problem, The fix, Same for everyone, Explore and Data health as
  self-contained HTML views ported from prototype C (`app/ui/views/`, `app/ui/view.py`,
  `app/ui/payloads.py`). Full width. The problem statement is now part of the story:
  Planning 79.4% vs Logistics 87.1%, the four layers, and the ontology chain.
- **Redesigned Ask:** question cards, one answer card per reply (Answer / SQL /
  Definition / Raw tabs, mini chart), "Try another" chips, rounded composer.
- Removed Plotly (unused now).
- **Verified:** 125 unit/app tests; 24 in-browser checks at 1366 and 1600 px, light and
  dark, no JS errors.

### Blocked / Open
- The HTML views must be confirmed to render in Streamlit in Snowflake (inline scripts in
  Components v1). CoCo is asked to verify at B15; a native fallback exists in git history.

### Next action (exact)
**Claude Code**: C04. Write `.agents/tasks/claude/C04_tests.md` while planning, then
`tests/conftest.py`, `pytest.ini` (`mock` / `live` / `ui` markers), the contract tests, and
adopt the Playwright checks as a `ui` test.

---

## Session 10 — 2026-09-24 — Claude Code

**Milestone**: M2 (parallel with CoCo)
**Build steps completed**: C03 ✅
**Credits used this session**: 0 (mock mode; nothing touched Snowflake)

### Done
- Installed Anthropic's `frontend-design` skill in `.claude/skills/` (local, gitignored)
  and used it with the built-in `dataviz` skill.
- Explored the look in Claude Design (<https://claude.ai/artifact/Gzj72vRfw7Skj6k2JnBhNS>,
  private to the user). Options A (light) and B (dark) were superseded by **C: Guided flow**
  after a UX review: a numbered story, one theme switch, tactile metric tiles, and an
  Explore screen for charts. The user approved C.
- Built the app: `app/streamlit_app.py`, `app/ui/theme.py` (light/dark tokens, CSS, Plotly
  layout), `app/ui/components.py`, `app/ui/charts.py`, and `app/ui/screens/`
  (problem, fix, same, ask, explore, health). All data goes through `utils/forge_data.py`.
- Added `app/environment.yml` (SiS), pinned `app/requirements.txt`, and
  `app/.streamlit/config.toml`.
- `tests/unit/test_app_smoke.py`: every screen in both themes, navigation, next buttons,
  metric tiles, disabled breakdowns, table view, all 8 answers. **118 passed** in total.
- Checked the running app in Chrome and fixed: words joining across lines, the brand
  wrapping, Streamlit's heading font overriding ours, and the red switch colour.

### Blocked / Open
- CR-002 / CR-003 still await CoCo (unchanged).
- Streamlit's `AppTest` can't drive a single-select `st.pills`. The Ask test preloads
  answers through the same `forge_data.ask_agent()` call instead.
- The CSS targets Streamlit 1.52 `data-testid` names. Re-check the look if the pin changes.

### Next action (exact)
**Claude Code**: C04. Write the card `.agents/tasks/claude/C04_tests.md` while planning,
then build `tests/conftest.py`, `pytest.ini` (`mock` / `live` markers) and the contract
tests (consistency, masking, ranges, pairings).

---

## Session 9 — 2026-09-24 — CoCo

**Milestone**: M1 (Foundation)
**Build steps completed**: B02 ✅
**Credits used this session**: < 0.01

### Done
- Populated `sql/01_setup/02_roles_grants.sql` with DDL for:
  - 4 Roles: `FORGE_ADMIN`, `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE`
  - Hierarchy: `FORGE_ADMIN` inherits all persona roles, `FORGE_ADMIN` granted to `SYSADMIN`, `ACCOUNTADMIN`, and user `LAZYBOY`
  - Persona isolation: persona roles do not inherit one another
  - Database & Schema `USAGE` grants across all 7 schemas for `FORGE_ADMIN` and persona roles
  - Warehouse `FORGE_WH` `USAGE` grants
  - Special schema object creation grants on `SEMANTIC` and `APP`
  - `SNOWFLAKE.CORTEX_AGENT_USER` and `SNOWFLAKE.CORTEX_USER` database roles granted to `FORGE_ADMIN`, `ACCOUNTADMIN` (user's default role), and persona roles
  - `READ SESSION ON ACCOUNT` granted to `FORGE_ADMIN`
- Executed DDL in Snowflake and verified Gate criteria:
  - `SHOW ROLES LIKE '%ROLE'` and `SHOW ROLES LIKE 'FORGE_ADMIN'` confirmed all 4 roles
  - `SHOW GRANTS TO ROLE <role>` confirmed expected database, schema, warehouse, and database role privileges
  - Tested context switching and query execution under all 4 roles (`PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE`, `FORGE_ADMIN`) on `FORGE_WH`
- Captured artifact `docs/artifacts/01_default_role.md` with user `LAZYBOY` default role (`ACCOUNTADMIN`), default warehouse (`COMPUTE_WH`), and agent permission mappings.
- Updated tracking in `.agents/NEXT.md`, `.agents/HANDOFF.md`, and `.agents/tasks/COCO_TASKS.md`.

### Blocked / Open
- Nothing blocked.

### Next action (exact)
- **CoCo**: Execute **B03** (`.agents/tasks/coco/B03_source_tables.md`) — create source tables across the 4 source schemas (`SRM_SOURCE`, `WMS_SOURCE`, `ERP_SOURCE`, `TMS_SOURCE`).

---

## Session 8 — 2026-09-24 — Claude Code

**Milestone**: M1 (parallel with CoCo B02)
**Build steps completed**: C02 ✅
**Credits used this session**: 0 (mock mode only; nothing touched Snowflake)

### Done
- Planned C02 in plan mode. The user approved it after a plain-English explanation.
- Built the data access layer in `app/utils/`:
  - `config.py`: contract v1.1 constants, verbatim.
  - `forge_data.py`: the public API. Each function has a mock and a live branch; live
    failures degrade to mock with a `Notice`, never an exception.
  - `agent_response.py`: `DATA_AGENT_RUN` parser.
  - `mock_data.py`: deterministic fixtures, including mock agent responses in the real
    response shape.
  - `source_catalog.py`: static LLD §2 mapping for Tab 3, so no source-schema query is
    needed.
- `tests/unit/test_data_layer.py`: **94 passed**. Covers contract-shaped mock output,
  all valid pairings in range, invalid pairings rejected, §6 masking matrix, all 8
  canonical questions, the parser against the official doc example, SQL text equal to
  contract §5.1/5.2/5.3/5.4/§8 (read from CONTRACT.md), and live-failure degradation.
- Created a repo-local `.venv` (gitignored) with pandas and pytest.
- Appended **CR-002** (persona metric procedures, user-approved idea) and **CR-003**
  (Q8 has no valid pairing) to CONTRACT §11 as PROPOSED.

### Blocked / Open
- CR-002 and CR-003 await CoCo. Until then the live consistency grid and Q8 fall back
  to mock.
- Flagged to CoCo in HANDOFF: 9 vs "10" source tables, `DMF_OVERSHIP_CHECK` vs
  `_COUNT`, DMF Enterprise-edition and viewer-role requirements.
- `app/utils/persona_queries.py` (legacy placeholder) left untouched.

### Next action (exact)
**Claude Code**: C03. Plan the 5-tab Streamlit app on `forge_data.py` in plan mode,
explain it in plain English, get approval, then build. Include `app/environment.yml` and
the Streamlit 1.52.2 pin.

---

## Session 7 — 2026-09-24 — CoCo

**Milestone**: M1 (Foundation)
**Build steps completed**: B01 ✅
**Credits used this session**: < 0.01

### Done
- Populated `sql/01_setup/01_database.sql` with DDL for:
  - Database: `SUPPLY_CHAIN_FORGE`
  - 7 Schemas: `ERP_SOURCE`, `WMS_SOURCE`, `TMS_SOURCE`, `SRM_SOURCE`, `GOVERNED`, `SEMANTIC`, `APP`
  - Cleaned up auto-generated `PUBLIC` schema
  - Warehouse: `FORGE_WH` (`XSMALL`, `AUTO_SUSPEND = 60`, `AUTO_RESUME = TRUE`, `INITIALLY_SUSPENDED = TRUE`)
- Executed DDL in Snowflake and verified Gate 1, 2, and 3:
  - `SHOW SCHEMAS IN DATABASE SUPPLY_CHAIN_FORGE` returned 7 custom schemas + `INFORMATION_SCHEMA`
  - `SHOW WAREHOUSES LIKE 'FORGE_WH'` confirmed `X-Small`, `auto_suspend=60`, `auto_resume=true`, `state=SUSPENDED`
  - Context switch to `SUPPLY_CHAIN_FORGE` and `FORGE_WH` confirmed cleanly
- Updated tracking in `.agents/NEXT.md`, `.agents/HANDOFF.md`, and `.agents/tasks/COCO_TASKS.md`

### Blocked / Open
- Nothing blocked.

### Next action (exact)
- **CoCo**: Execute **B02** (`.agents/tasks/coco/B02_roles_grants.md`) — create `FORGE_ADMIN`, `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE`, grant hierarchy and privileges, capture `docs/artifacts/01_default_role.md`.

---

## Session 6 — 2026-09-24 — Claude Code

**Milestone**: M1 (parallel with CoCo B01)
**Build steps completed**: C01 ✅
**Credits used this session**: 0 (no Snowflake access; docs fetched over HTTPS only)

### Done
- Wrote all six references in `docs/references/` from docs fetched today (raw `.md`
  pages on docs.snowflake.com). Each has source URLs and the fetch date. Anything the
  docs don't state is marked **INFERRED**.
- `data_agent_run.md`: signature, request body, full response schema (content item types,
  ResultSet, warnings, metadata, status), error shapes, and a parser recipe for
  `ask_agent()`.
- **Contract §6a independently confirmed.** No Change Request. Condition passed to CoCo in
  HANDOFF: masking policies must use `CURRENT_ROLE()` / `IS_ROLE_IN_SESSION()`, not
  `INVOKER_ROLE()`.
- Findings table in `docs/references/README.md`.

### Blocked / Open
- The Analyst `tool_result.json` field names aren't formally documented. The parser
  targets inferred names (`sql`, `text`, `verified_query_used`, `result_set`, …).
  Artifact `07_agent_response.json` (B10) settles it at C6c.
- There's no `C02` card file yet. Its spec lives in `.agents/tasks/CLAUDE_TASKS.md`
  Track C2.
- `CLAUDE.md` lower sections are still stale (the old dependency gate,
  `persona_queries.py`, the `unit_cost` landed-cost formula, "Logistics Manager"). The
  user has been told. Not edited.

### Next action (exact)
**Claude Code**: C02. Plan `app/utils/config.py` + `app/utils/forge_data.py` in plan mode
(function signatures, mock/live switch, error degradation), get approval, then build.

---

## Session 5 — 2026-09-24 — CoCo

**Milestone**: M0 — credential gap closed
**Build steps completed**: none — still design
**Credits used this session**: 0

### The gap, and why my first framing was wrong

I had told the user Claude Code would need a PAT and an MCP client to verify against
Snowflake. Before asking them to set that up, I checked what actually exists:

```
connections.toml   →  authenticator = OAUTH_AUTHORIZATION_CODE, no password/token
snow CLI           →  not installed
cortex secret list →  empty
```

So Claude Code genuinely has no non-interactive Snowflake path. My framing of the *gap* was
right. My framing of the *fix* was not — I had assumed credentials were the only answer.

They are not. For **verification**, Claude Code does not need a live connection. It needs
real data. Those are different requirements, and I had conflated them.

### Resolution: artifact handoff

```
CoCo runs live query  →  commits REAL output to docs/artifacts/  →  Claude verifies
```

Presented three options to the user. They chose **artifacts now, PAT only if needed** —
the right call, since it defers the decision until it actually matters instead of paying
setup cost speculatively.

Wrote `docs/artifacts/README.md` defining an 11-artifact schedule, each tied to the build
step that produces it and the Claude track that consumes it. Wired **8 explicit capture
steps** into CoCo's queue at B2, B5, B7, B7b, B8, B10, B11, B12.

The critical one is `07_agent_response.json` — one complete, unmodified `DATA_AGENT_RUN`
response. The app's entire Ask tab depends on parsing that shape, and it is the largest
unknown in the project. Claude Code writes its parser against the real artifact rather than
against a guess, and the card explicitly forbids abridging the capture.

### A useful separation this forced

I had conflated two different purposes for the MCP server:

| Purpose | Status |
|---------|--------|
| **Product feature** — "the governed ontology is reachable by any MCP client" | **In scope**, B14, demoed to judges |
| **Dev dependency** — Claude Code's verification channel | **Not needed**, replaced by artifacts |

B7c (read-only MCP + `FORGE_MCP_READER` + PAT) is now marked DEFERRED rather than deleted,
with an explicit trigger: build it only if artifacts prove insufficient. B14 is unaffected.

### Secondary benefit

Artifacts double as test fixtures and as replacements for the invented mock values. Once
B8 lands, `MOCK_METRICS` gets overwritten with **real** captured numbers — so the demo
shows genuine figures even in mock mode, and survives a network failure on stage.

### Rebalanced ownership

| CoCo only | Claude Code only |
|-----------|-----------------|
| Any SQL execution | App, tests, docs scaffolding |
| Artifact capture | Agent response parser |
| SiS deployment (B15) | — |

Moved app deployment explicitly to CoCo at B15 — Claude Code has no Snowflake write access,
so leaving that ambiguous would have stalled at the finish line.

### Blocked / Open
Nothing blocked. **Nothing required from the user.**

### Next action (exact)
**CoCo**: `.agents/tasks/coco/B01_database.md`
**Claude Code**: `.agents/tasks/claude/C01_references.md`

---

## Session 4 — 2026-09-24 — CoCo

**Milestone**: M0 — parallelism corrected
**Build steps completed**: none — still design
**Credits used this session**: 0

### What prompted this

The user challenged whether the tasks were actually parallel. On inspection, they were
partly right. C01–C05 were genuinely parallel (5 of 6 tracks, real finishable work), but
the single live-verification gate sat at **B14** — roughly 85% through CoCo's queue. Claude
Code could build everything but could not verify anything against reality until the very
end, which concentrated all integration risk into one late step.

### Fix: staged unlocks instead of one handoff

Claude Code does not need the whole stack to start verifying. It needs three separate
things, which arrive at three different times:

| Unlock | CoCo step | Claude verifies |
|--------|----------|-----------------|
| Governed layer | **B7c** (new) | Governed view columns, masking matrix, persona procedures |
| Semantic layer | **B8/B9** | Metric identifiers, dimension identifiers, valid pairings, value ranges |
| Agent layer | **B10/B14** | `DATA_AGENT_RUN` response parsing, 8 canonical questions |

Added **B7c — MCP read-only server**, placed immediately after B7b. It creates
`SUPPLY_CHAIN_MCP_RO` with a single read-only `SYSTEM_EXECUTE_SQL` tool and a dedicated
least-privileged role `FORGE_MCP_READER` (no write privileges anywhere).

**First live unlock moves from ~85% to ~40% through CoCo's queue.**

Split `C06` into `C6a` / `C6b` / `C6c` so each unlock is consumed the moment it lands
rather than batched.

Rewrote `.agents/HANDOFF.md` handoff table into three staged row groups, each naming the
CoCo step that unlocks it, plus a measured-values block annotated with which build step
produces each number.

### Honest accounting of what stays sequential

| Item | Why unavoidable |
|------|----------------|
| Live tests going green | Objects must exist before a query can succeed |
| SiS deployment | Needs semantic view + agent deployed |
| Final demo rehearsal | Needs the whole stack |

Everything else overlaps. This is as parallel as the problem allows.

### Credential gap identified and recorded

`cortex secret list` → empty. No `.mcp.json`. Claude Code cannot reach Snowflake via MCP
until a PAT exists. Not blocking (C01–C05 need no Snowflake access), but documented in
`.agents/NEXT.md` so it is not discovered mid-flow. The PAT must be bound to
`FORGE_MCP_READER`, not `ACCOUNTADMIN`, and stored via `/secrets` — never pasted in chat.

### Blocked / Open
Nothing blocked.

### Next action (exact)
**CoCo**: `.agents/tasks/coco/B01_database.md`
**Claude Code**: `.agents/tasks/claude/C01_references.md`

---

## Session 3 — 2026-09-24 — CoCo

**Milestone**: M0 — gap resolution and task-card system
**Build steps completed**: none — still design
**Credits used this session**: ~0.03 (two verification queries)

### Gap resolutions

**GAP-1 was a real blocker and would have silently broken the demo.**
Snowflake docs confirm: *"Streamlit in Snowflake apps run with owner's rights, so using
`CURRENT_ROLE` inside a Streamlit app always returns the app owner role."* Our masking
policies key on `CURRENT_ROLE()`, so a persona dropdown driving `USE ROLE` would have had
**zero effect** — all three personas would show identical unmasked data while the app
looked like it worked. The central claim of the project would have been unprovable, and
plausibly unnoticed until the demo.

Resolution: three owner's-rights stored procedures, each **owned by a different persona
role**. Each executes as its owner, so `CURRENT_ROLE()` resolves to that persona and the
genuine masking policy applies. The app calls all three as the app owner — no role
switching required. Masking policies themselves are unchanged and remain real.

Also established that metrics need **no** per-role execution: they are identical across
personas by design. Verified structurally — no canonical metric references any masked
column (documented as a table in contract §6).

**GAP-5 multilingual: verified.** `SNOWFLAKE.CORTEX.COMPLETE` with `claude-sonnet-4-5`
returned `42` for both the English and Hindi forms of the same arithmetic question.
Caveat recorded: this tests the model, not the Agent path (where Analyst must map Hindi
onto English semantic-view synonyms). Re-verify at B10 before promising it in the demo.

**GAP-4 resolved by dropping scope.** Cut `LOGISTICS_APAC_ROLE` and the row access policy
from MVP. Column masking already proves governed access on the axis this problem statement
cares about — who can see which fields. A regional row filter adds a role, a policy, and a
test axis while adding nothing to the core claim, and it is the component most likely to
accidentally perturb metric aggregates across personas. Moved to M6 stretch.

**GAP-2, GAP-3, GAP-6** closed as specification work: exact time-dimension expressions,
both custom DMF bodies, and the data-generation approach with per-target distribution
controls. All written into `docs/GAPS_RESOLVED.md`.

### Contract v1.0 → v1.1
- §5.4 rewritten: call persona procedures, not `USE ROLE`
- §6a added: full rationale for the mechanism
- §1: three procedure FQNs added
- §6: added the proof table showing no metric touches a masked column
- §11: CR-001 logged as ACCEPTED

Raised **before** Claude Code started, so the cost of the change was zero. This is the
contract mechanism working as intended.

### Task-card system adopted
Replaced long checklists with an index plus self-contained cards, per the user's own
preferred workflow:

```
.agents/NEXT.md                  ← one read answers "what now?"
.agents/tasks/coco/B01…B17.md
.agents/tasks/claude/C01…C06.md
```

Each card: header table · Goal · Why · Steps · **Gate** · On completion. Self-contained, so
an agent needs no other file to execute it. Cards are authored a step or two ahead of
execution rather than all at once, so each can absorb what the previous gate actually
revealed.

Written so far: `B01`, `B02`, `C01`. Added build step **B07b** for the persona procedures.

### Blocked / Open
Nothing blocked. No unresolved design gaps.

### Next action (exact)
**CoCo**: `.agents/tasks/coco/B01_database.md`
**Claude Code**: `.agents/tasks/claude/C01_references.md`

---

## Session 2 — 2026-09-24 — CoCo

**Milestone**: M0 (Foundation) — restructured for parallel execution
**Build steps completed**: none — planning
**Credits used this session**: ~0.02 (read-only capability checks)

### Done
- **Discovered Snowflake-managed MCP server is GA.** This changes the collaboration
  model: Claude Code can connect to Snowflake as an MCP client rather than waiting for
  a file handoff. Also a genuine differentiator — "the governed ontology is reachable by
  any MCP client" is a production story, not a demo trick.
- **Identified the flaw in the previous plan**: Claude Code was blocked until M4, idle
  for roughly 70% of the project. Restructured to true parallel execution.
- **Wrote `docs/CONTRACT.md` and froze it at v1.0.** This is the mechanism that makes
  parallelism safe: exact metric identifiers, dimension identifiers, valid metric ×
  dimension pairings, governed view columns, role names, FQNs, masking matrix, query
  patterns, expected value ranges, and mock fixtures. Neither agent may change it
  unilaterally; deviations go through Change Requests in §11.
- Rewrote `.agents/tasks/CLAUDE_TASKS.md` — six tracks C1–C6. Claude Code starts
  immediately at C1 (API reference library), builds the full app against the contract
  with a mock data layer, and only C6 (go live) is gated.
- Rewrote `.agents/tasks/COCO_TASKS.md` — added B13 (contract conformance audit),
  B14 (MCP servers), renumbered handoff to B15. Added the parallel-context warning.
- Added LLD §7a — MCP server specification, two servers deliberately split so
  `SYSTEM_EXECUTE_SQL` cannot be used to bypass the semantic view's verified queries.
- Extended the build order to B17 and flagged B13 as integration insurance.
- Updated `MILESTONES.md` with a parallel execution diagram. Only hard dependency is
  B14 → C6.
- Rewrote `.agents/HANDOFF.md` — 10 handoff rows, plus a fill-in block for the measured
  values CoCo must hand over (naive OTD, governed OTD, etc.).
- Rewrote both entry-point files (`COCO.md`, `CLAUDE.md`) to lead with the contract.
- Created `mcp/` and `docs/references/` with placeholder guidance.

### Design decisions recorded
- **Two MCP servers, not one.** Co-locating `SYSTEM_EXECUTE_SQL` with `CORTEX_AGENT_RUN`
  would let a client sidestep the governed path. Splitting them is the correct posture
  and is also defensible to judges.
- **Mock layer is not throwaway.** It becomes the pytest fixture layer and lets the demo
  survive a network failure on stage.
- **The contract is the arbiter, not observed reality.** If Snowflake ends up differing
  from the contract, the app does not silently adapt — a Change Request is filed. This
  prevents the two halves drifting apart without anyone noticing.

### Blocked / Open
- Nothing blocked. Both agents have executable queues.

### Next action (exact)
**CoCo**: execute **B1** — write `sql/01_setup/01_database.sql` and create
`SUPPLY_CHAIN_FORGE` with 7 schemas (`ERP_SOURCE`, `WMS_SOURCE`, `TMS_SOURCE`,
`SRM_SOURCE`, `GOVERNED`, `SEMANTIC`, `APP`) plus `FORGE_WH` (XSMALL, auto-suspend 60s).

**Claude Code**: execute **C1** — fetch real docs into `docs/references/`, starting with
the `DATA_AGENT_RUN` response JSON shape.

---

## Session 1 — 2026-09-24 — CoCo

**Milestone**: M0 (Foundation)
**Build steps completed**: none yet — design phase
**Credits used this session**: ~0.05 (read-only discovery queries)

### Done
- Read prior chat history, recovered full project context
- Created project scaffold: 27 files, folder structure, agent coordination files
- Initialized git repo, created GitHub repo `Harsh2292/snowflake-forge`
- Working on branch `development`
- Gitignored Claude Code local files (`CLAUDE.md`, `.claude/`)
- **Verified Snowflake account capabilities**:
  - Account `DA53081`, `AZURE_CENTRALINDIA`, v10.34.101, role `ACCOUNTADMIN`
  - Credits consumed to date: **0.43** — budget is not a constraint
  - `CORTEX_ENABLED_CROSS_REGION = ANY_REGION` — all frontier models reachable
  - Semantic views support `AI_VERIFIED_QUERIES`, `AI_SQL_GENERATION`,
    `AI_QUESTION_CATEGORIZATION` natively in DDL
  - `SNOWFLAKE.CORTEX.DATA_AGENT_RUN()` available — agent callable from plain SQL
- Wrote `docs/HLD.md` — architecture, tech stack with rationale, ontology, metrics,
  personas, MVP definition, cost strategy, risks
- Wrote `docs/LLD.md` — exact source schemas, data volumes, governed views, semantic
  view DDL, agent spec, 16-step build order, test matrix
- **Key design decision**: four separate source schemas (ERP / WMS / TMS / SRM) with
  deliberately inconsistent SAP-style column naming, instead of one clean `RAW` schema.
  This makes the "scattered systems" problem demonstrable rather than asserted.
- **Key design decision**: semantic view authored as **DDL**, not YAML — native object
  form, diffable, no translation step.

### Blocked / Open
- Nothing blocked.

### Next action (exact)
Execute **B1**: create `SUPPLY_CHAIN_FORGE` database, 7 schemas
(`ERP_SOURCE`, `WMS_SOURCE`, `TMS_SOURCE`, `SRM_SOURCE`, `GOVERNED`, `SEMANTIC`, `APP`),
and `FORGE_WH` warehouse (XSMALL, auto-suspend 60s).
File to write: `sql/01_setup/01_database.sql`.
