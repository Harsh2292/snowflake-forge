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
