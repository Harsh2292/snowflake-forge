# Milestones

> Each milestone has a hard exit criterion. Do not advance until it passes.
> `B#` = CoCo build steps (`docs/LLD.md` §8). `C#` = Claude Code tracks
> (`.agents/tasks/CLAUDE_TASKS.md`).

## Parallel Execution Model

Both agents work simultaneously against the frozen `docs/CONTRACT.md`.
Live access is exposed in **three staged unlocks**, not one handoff at the end.

```
        CoCo (Snowflake)                     Claude Code (app)
        ────────────────                     ─────────────────
M1      B1  database, schemas           C1   API reference library
        B2  roles, grants               C2   data access layer (mock + live branches)
        B3  source tables               C3   Streamlit app, 5 tabs (mock-driven)
        B4  data generation             C4   test suite (written; red until live)
        B5  distribution verify         C5   demo script, README

M2      B6  tags, masking
        B7  governed views
        B7b persona procedures
        B7c MCP read-only  ───────────► C6a  verify governed columns + masking   LIVE

M3      B8  semantic view  ───────────► C6b  verify metrics + dimensions         LIVE
        B9  verified queries

M4      B10 Cortex Agent   ───────────► C6c  verify agent response parsing       LIVE
        B11 consistency check
        B12 DMFs
        B13 contract audit
        B14 MCP + agent tools
        B15 handoff

M5                                           deploy to SiS, full demo

M6      differentiation (both)
```

**First live unlock is at B7c — about 40% through CoCo's queue.** Deliberate: contract
mismatches surface while they are still cheap to fix, rather than during final integration.

### Genuinely sequential residue

| Item | Why unavoidable |
|------|----------------|
| Live tests going green | Objects must exist before a query can succeed |
| SiS deployment | Needs semantic view + agent deployed |
| Final demo rehearsal | Needs the whole stack |

Everything else overlaps.

---

## M0 — Foundation ✅ COMPLETE

**Goal**: Project planned, documented, version-controlled, and the interface frozen.

| Task | Owner | Status |
|------|-------|--------|
| Folder structure + coordination files | CoCo | ✅ |
| Git repo + GitHub remote | CoCo | ✅ |
| Verify Snowflake account capabilities | CoCo | ✅ |
| HLD written | CoCo | ✅ |
| LLD written | CoCo | ✅ |
| **Interface contract frozen** | CoCo | ✅ |
| Parallel task queues for both agents | CoCo | ✅ |
| Milestones + session log | CoCo | ✅ |

**Exit criterion**: `docs/CONTRACT.md` is frozen, and both agents have a task queue
they can execute without waiting on each other. ✅

---

## M1 — Data Foundation

**Goal**: Four source systems exist with realistic, messy, internally-consistent data.

**Build steps**: B1 → B5

| Task | Owner |
|------|-------|
| Database, 7 schemas, `FORGE_WH` | CoCo |
| 4 roles + grants (including default-role grants for agent) | CoCo |
| 10 source tables across `ERP_SOURCE` / `WMS_SOURCE` / `TMS_SOURCE` / `SRM_SOURCE` | CoCo |
| Data generation in FK order | CoCo |
| Distribution verification | CoCo |

**Exit criterion**:
```
OTD        between 0.84 and 0.90
Fill rate  between 0.90 and 0.95
DOI        between 15 and 45
Row counts within 10% of LLD §3 targets
ERP promised date disagrees with TMS on 15–25% of orders
```

---

## M2 — Governance Layer

**Goal**: Data is conformed, tagged, masked, and access-controlled.

**Build steps**: B6 → B7

| Task | Owner |
|------|-------|
| 5 tag definitions + application | CoCo |
| 4 masking policies | CoCo |
| Row access policy on `V_PLANT` | CoCo |
| 9 governed conformed views | CoCo |

**Exit criterion**:
```
PLANNER_ROLE   → unit_cost IS NULL, payment_terms masked
BUYER_ROLE     → customer_name masked, unit_cost visible
LOGISTICS_ROLE → payment_terms masked, customer_name masked
All 3 roles    → can SELECT every governed view without error
```

---

## M3 — Semantic Layer  ← THE CRITICAL MILESTONE

**Goal**: The ontology exists as a queryable semantic view with canonical metrics.

**Build steps**: B8 → B9

| Task | Owner |
|------|-------|
| Semantic view with 2 tables, validated | CoCo |
| Grow to 9 tables + 10 relationships | CoCo |
| Facts, dimensions, 4 canonical metrics | CoCo |
| `AI_SQL_GENERATION` + `AI_QUESTION_CATEGORIZATION` instructions | CoCo |
| 8 `AI_VERIFIED_QUERIES` | CoCo |

**Exit criterion**:
```sql
-- All four must return sensible values
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_SV METRICS shipments.on_time_delivery_rate);
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_SV METRICS order_lines.fill_rate);
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_SV METRICS inventory.days_of_inventory);
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_SV METRICS shipments.avg_landed_cost);

-- Plus at least one metric × dimension combination
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_SV
  METRICS shipments.on_time_delivery_rate DIMENSIONS plants.plant_region);
```

**Risk note**: build incrementally. Semantic view validation is strict about clause
order (FACTS before DIMENSIONS before METRICS) and metric/dimension granularity.

---

## M4 — Conversational Layer

**Goal**: Natural language questions return governed answers.

**Build steps**: B10 → B12

| Task | Owner |
|------|-------|
| Cortex Agent with Analyst + chart tools | CoCo |
| Agent tested against 8 canonical questions | CoCo |
| Cross-persona consistency verified in SQL | CoCo |
| 5 DMFs attached and running | CoCo |
| `HANDOFF.md` updated with all FQNs | CoCo |

**Exit criterion**:
```
DATA_AGENT_RUN returns a grounded numeric answer for all 8 canonical questions
All 4 metrics identical across PLANNER / BUYER / LOGISTICS (6 decimal places)
Agent declines an out-of-scope question
Agent asks for clarification on an ambiguous question
DMF results visible in DATA_QUALITY_MONITORING_RESULTS
```

**This is the MVP boundary.** After M4 the core product works end to end.

---

## M5 — Demo Layer

**Goal**: A human can see and believe the whole thing in five minutes.

**Build steps**: B14 → B15

| Task | Owner |
|------|-------|
| Streamlit app: persona switcher + NL query + results | Claude Code |
| Consistency proof tab | Claude Code |
| Metric charts | Claude Code |
| `pytest` consistency suite | Claude Code |

**Exit criterion**:
```
App deployed to SUPPLY_CHAIN_FORGE.APP.FORGE_DEMO
Persona switcher changes visible detail but not metric values
NL query returns an answer inside the app
Consistency tab shows 12 green assertions (4 metrics × 3 roles)
pytest passes
```

---

## M6 — Differentiation

**Goal**: Move from "works" to "wins."

**Build steps**: B16 + enhancements

| Task | Owner | Judge criterion |
|------|-------|----------------|
| "Disagreement" demo — naive ERP-only SQL vs governed metric | CoCo | Real World Relevance |
| Lineage trace: source column → metric → answer | CoCo | Technical Execution |
| Edge-case suite: ambiguous, out-of-scope, cross-domain | CoCo | Technical Execution |
| Multilingual query demo | CoCo | Real World Relevance |
| DMF quality panel in app | Claude Code | Solution Completeness |
| Demo script rehearsed to 5 minutes | Both | All three |
| Submission README | Both | Solution Completeness |
| SQL + security review sweep | CoCo | Technical Execution |

**Exit criterion**: demo runs start to finish in under 5 minutes without a failure,
and every judging criterion has a specific moment in the demo that addresses it.

---

## Progress Tracker

| Milestone | Status | Exit criterion met |
|-----------|--------|-------------------|
| M0 Foundation | ✅ Complete | Yes |
| M1 Data Foundation | ⬜ Not started | — |
| M2 Governance | ⬜ Not started | — |
| M3 Semantic Layer | ⬜ Not started | — |
| M4 Conversational | ⬜ Not started | — |
| M5 Demo | ⬜ Not started | — |
| M6 Differentiation | ⬜ Not started | — |
