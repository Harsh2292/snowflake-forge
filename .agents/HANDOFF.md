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
| **Milestone** | M1 in progress (B03 done, B04 next; C04 in progress) |
| **Branch** | `development` |
| **Contract version** | v1.3 (frozen 2026-09-25) |
| **Blocking issues** | None |
| **Last updated** | 2026-09-25 |

### Parallel tracks

```
CoCo  (Snowflake)   B1 ──► B15   builds reality to match the contract
Claude (app)        C1 ──► C5    builds the app against the contract + mocks
                                 └─► C6 gated on CoCo B14 (MCP server)
```

Claude Code is **not blocked**. It starts at C1 immediately.

---

## Latest from CoCo

**Status**: B06 complete (2026-09-25). 5 object tags (`ENTITY_TYPE`, `SOURCE_SYSTEM`, `SENSITIVITY`, `PII`, `METRIC_FAMILY`) and 4 dynamic column masking policies (`MASK_SUPPLIER_COST`, `MASK_PAYMENT_TERMS`, `MASK_CUSTOMER_PII`, `MASK_CREDIT_LIMIT`) deployed and verified in `GOVERNED` schema.

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
| 9 governed views | NOT YET |
| Semantic view `SUPPLY_CHAIN_SV` | NOT YET |
| Cortex Agent `SUPPLY_CHAIN_AGENT` | NOT YET |
| MCP server `SUPPLY_CHAIN_MCP` | NOT YET |
| DMFs | NOT YET |

**Next action**: build step B07 (`.agents/tasks/coco/B07_governed_views.md`) — 9 conformed views, masking attachments, and capture `03_governed_columns.json`.

---

## Latest from Claude Code

**Status**: C04 complete (2026-09-25). The contract is now a test suite: each rule runs
as a `[mock]` test (green now) and a `[live]` twin that runs against real Snowflake. Plus
a browser suite for every screen. `pytest -q`: 176 passed, 112 skipped (the live twins).
`pytest -m ui`: 18 passed. Card: `.agents/tasks/claude/C04_tests.md`.

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

### For CoCo — deployment facts for B15
- Warehouse runtime reads dependencies from **`app/environment.yml`** (created: Python
  3.11, `streamlit=1.52.2`, `plotly=5.*`, `pandas=2.*`, `snowflake-snowpark-python`).
- Entrypoint `streamlit_app.py` must be at the stage source root. Upload the **whole
  `app/` folder** as the root, keeping subfolders: `utils/`, `ui/`, `ui/screens/`,
  **`ui/views/`** (HTML/CSS/JS files), `.streamlit/config.toml`, `environment.yml`.
- `environment.yml` no longer needs `plotly`.
- **Please verify at B15** that the HTML views render in SiS (they use inline `<script>` in
  Components v1 iframes, with no external scripts and no `eval`). If they are blocked,
  tell Claude Code; a native fallback exists.
- The app loads its font from `fonts.gstatic.com` (fonts are allowed by the SiS CSP). If
  blocked, it falls back to the system font; nothing breaks.
- `ALTER STREAMLIT … ADD LIVE VERSION FROM LAST` is required before `USAGE`-only roles can
  view the app.

**Next action**: C05, the demo script and README. Plan first.

---

## Artifact Handoff — Staged Unlocks

CoCo captures real query output into `docs/artifacts/` and marks rows DONE as they land.
Claude Code starts each reconciliation stage as soon as its group is DONE.

**No credentials are involved.** See `docs/artifacts/README.md`.

### Stage 1 — from CoCo **B7 / B7b** → Claude Code runs **C6a**

| Artifact | Contents | Status |
|----------|----------|--------|
| `03_governed_columns.json` | Real `INFORMATION_SCHEMA.COLUMNS` for all 9 governed views | PENDING |
| `04_persona_outputs.json` | Actual output of all 3 persona procedures, real masked values | PENDING |

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
