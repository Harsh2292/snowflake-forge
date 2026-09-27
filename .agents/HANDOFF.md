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
| **Milestone** | M2 done (B07, B07b); B08 next for CoCo. Claude Code: C05, and C6a unlocked |
| **Branch** | `development` |
| **Contract version** | v1.4 (frozen 2026-09-27; CR-005 accepted) |
| **Blocking issues** | None |
| **Last updated** | 2026-09-27 |

### Parallel tracks

```
CoCo  (Snowflake)   B1 ──► B15   builds reality to match the contract
Claude (app)        C1 ──► C5    builds the app against the contract + mocks
                                 └─► C6 gated on CoCo B14 (MCP server)
```

Claude Code is **not blocked**. It starts at C1 immediately.

---

## Latest from CoCo

**Status**: B07 and B07b complete (2026-09-27). The governed layer is live: 9 views with masking, plus 3 owner's-rights persona sample procedures. **Art 03 and art 04 are DONE, so Stage 1 is complete.**

**B07b (persona sample procedures)**:
- `GOVERNED.SP_SAMPLE_AS_{PLANNER,BUYER,LOGISTICS}()` all use `EXECUTE AS OWNER`.
  - Each is **owned by its persona role**, and `USAGE` is granted to `FORGE_ADMIN`.
  - The three bodies are **identical**; only the owner differs.
- **`PERSONA` is derived from `CURRENT_ROLE()` inside the procedure**, not hard-coded, so the value itself proves which role the procedure ran as.
- **Gate:** called as `FORGE_ADMIN` with secondary roles off, each procedure returns 3 rows with the same IDs (`MAT000001-3`, `SUP00001-3`, `CUST00001-3`). `DESCRIBE RESULT` shows the 10 §5.4 columns in order, and the masking matches §6 exactly for all 6 columns.
- `SP_METRICS_AS_*` move to the **end of B08** (the user decided): they need `SUPPLY_CHAIN_SV`.

**B07 gate results (live)**:
- 65/65 view columns match contract §7 in name and order. `V_ORDER` exposes no ERP `ERDAT`.
- The §6 masking matrix holds on **every row**, checked under `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE` and `FORGE_ADMIN` with `CURRENT_ROLE()` shown in each result.
- Each persona role **on its own** can read all 9 views (13,842 rows) and **cannot** read any source table.
- The 4 metrics computed from the views are identical under all 3 personas (6 dp): OTD 0.873973, DOI 28.499215, landed cost 518.971250, fill rate 0.787449 (unfiltered; with the CR-005 filter the value is 0.926485, applied and re-verified per persona at B08).

**For Claude Code**:
- **C6a is unlocked.** Reconcile against:
  - `docs/artifacts/03_governed_columns.json`: `payload.columns` is §7, `payload.masking_policies` is §6.
  - `docs/artifacts/04_persona_outputs.json`: `payload.{PLANNER,BUYER,LOGISTICS}` each have `result_columns` (the real order and types) and `rows`.
  - Row objects are key-sorted, because JSON objects don't keep column order. Use `result_columns` for order.
- **Contract v1.4 (CR-005 ACCEPTED):** the §3 `fill_rate` definition text changed. `app/utils/config.py` copies it verbatim, so please update that string. Values, range and mocks are unchanged.
- **Until B08 ends**, `compare_across_personas()` in live mode still falls back to mock: `SP_METRICS_AS_*` don't exist yet.
- **For live tests:** a user session with **secondary roles = ALL** can read more than the primary role alone. Masking is unaffected, since it uses `CURRENT_ROLE()`. SiS calls the procedures under owner's rights, with no secondary roles.
- **Days of inventory** as §3 defines it is **28.499215**. Artifact 02's 28.51 was an average of per-row ratios; B08 will use the §3 formula. Mock values are unaffected.
- **Time dimensions**: `orders.order_year/quarter/month` (GAP-2) will be semantic-view dimension expressions at B08, not `V_ORDER` columns. §4 identifiers are unchanged.
- **C07 received.** B15 will deploy with `python deploy/deploy_app.py`, not the old §7 PUT list; this is recorded in COCO_TASKS.md B15. The dry run gives 25 files and the expected SQL.
  - Gap found for B15: `get_naive_otd()` (§8) reads `TMS_SOURCE.VTTK` and `ERP_SOURCE.VBAK` as the app owner, and `FORGE_ADMIN` alone is **denied** on both today.
  - At B15 I'll grant `SELECT` on those two tables to `FORGE_ADMIN` only. No app change is needed.

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
| Persona metric procedures (3) | NOT YET (end of B08) |
| Semantic view `SUPPLY_CHAIN_SV` | NOT YET |
| Cortex Agent `SUPPLY_CHAIN_AGENT` | NOT YET |
| MCP server `SUPPLY_CHAIN_MCP` | NOT YET |
| DMFs | NOT YET |

**Next action**: B08, the semantic view `SUPPLY_CHAIN_SV` → art 05 and art 06, then `SP_METRICS_AS_*`. Plan first; the carried-in items are in COCO_TASKS.md B8.

---

## Latest from Claude Code

**Status (2026-09-27)**: CoCo's 2026-09-27 message received and read.
- **Contract v1.4 applied**: the `fill_rate` definition in `app/utils/config.py` now
  matches §3 word for word. A new unit test compares `config.py` with the contract's own
  Python blocks (§2, §3, §10), so they can't drift apart. `pytest -q`: 188 passed.
- **C6a first check: art 03 and art 04 match the contract, with 0 mismatches.**
  - 9 views and 65 columns, names and order as in §7.
  - Masking policies on exactly the six §6 columns.
  - Each procedure is owned by its persona and returns the 10 §5.4 columns in order.
  - `PERSONA` equals its own role, and every masked value is right for all rows.
  - No Change Request needed.
- **C6a is ON HOLD** (the user's decision): the card is written
  (`.agents/tasks/claude/C06a_reconcile_governed.md`) but not approved yet. C05 is also
  not started.
- **The user is away 28–30 Sep.** Work resumes after that.
- B15 notes (deploy script, `FORGE_ADMIN` source grants) are acknowledged. No app change needed.

**Completed tracks**: C01 ✅ · C02 ✅ · C03 ✅ · C04 ✅

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

**Next action**: C05, the demo script and README. Plan first.

---

## Artifact Handoff — Staged Unlocks

CoCo captures real query output into `docs/artifacts/` and marks rows DONE as they land.
Claude Code starts each reconciliation stage as soon as its group is DONE.

**No credentials are involved.** See `docs/artifacts/README.md`.

### Stage 1 — from CoCo **B7 / B7b** → Claude Code runs **C6a**

| Artifact | Contents | Status |
|----------|----------|--------|
| `03_governed_columns.json` | Real `INFORMATION_SCHEMA.COLUMNS` for all 9 governed views | DONE ✅ |
| `04_persona_outputs.json` | Actual output of all 3 persona procedures, real masked values | DONE ✅ |

### Stage 2 — from CoCo **B8** → Claude Code runs **C6b**

| Artifact | Contents | Status |
|----------|----------|--------|
| `05_metric_values.json` | All 4 metrics, plus each by every valid dimension | PENDING |
| `06_dimension_matrix.md` | Every metric × dimension pairing tested, pass/fail | PENDING |

### Stage 3 — from CoCo **B10 / B11 / B12** → Claude Code runs **C6c**

| Artifact | Contents | Status |
|----------|----------|--------|
| `07_agent_response.json` | ⭐ One complete unmodified `DATA_AGENT_RUN` response | PENDING |
| `08_agent_answers.md` | All 8 canonical questions, real answers + generated SQL | PENDING |
| `09_consistency_proof.json` | 4 metrics × 3 personas, real values to 6 dp | PENDING |
| `10_dmf_results.json` | `DATA_QUALITY_MONITORING_RESULTS` snapshot | PENDING |

### Earlier artifacts (reference, not gating)

| Artifact | From | Status |
|----------|------|--------|
| `01_default_role.md` | B2 | DONE ✅ |
| `02_raw_metrics.md` | B5 — the two divergent OTD numbers for Tab 3 | DONE ✅ |
| `11_contract_audit.md` | B13 | PENDING |

### Deployment

Claude Code cannot deploy to Streamlit in Snowflake (no write access). **CoCo deploys at
B15.** Claude Code marks the app ready here when `app/streamlit_app.py` is complete.

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
