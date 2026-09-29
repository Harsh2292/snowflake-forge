# Milestones

> Each milestone has a hard exit criterion. Do not advance until it passes.
> `B#` = CoCo build steps (`docs/LLD.md` §8). `C#` = Claude Code tracks
> (`.agents/tasks/CLAUDE_TASKS.md`).

## Parallel Execution Model

Both agents work simultaneously against the frozen `docs/CONTRACT.md`. Claude Code has no
Snowflake access: CoCo runs everything and hands real output back as artifacts.

**Replanned 2026-09-29 (user-approved):** finish in 3 days, production-ready and deployed,
with realistic 10-year data, a cleansing layer, a scale proof and cost controls. Queue:
`.agents/tasks/COCO_TASKS.md`. Post-hackathon: `docs/ROADMAP.md`.

```
        CoCo (Snowflake)                          Claude Code (app, data)
        ────────────────                          ───────────────────────
M1-M2   B1–B7b foundation + governance  ✅   ──► C6a  ✅   (C01–C04, C07 ✅)
M3      B8   semantic view v1           ✅
        B8b  data spec v2 + CR-006    ────────►  C08  data generator (data_gen/)
        B8c  load + CONFORMED layer   ◄────────  C08         C09 app production pass
        B9   semantic view v2 → art 05/06/09 ──► C6b
M4      B10  agent + evaluation set → art 07/08 ► C6c
M5      B12  data-quality checks → art 10
        B13  scale proof on a clone → art 12
M6      B14  contract audit + security → art 11
        B15  production hardening + deploy        C05 demo, README; rehearsal
```

Critical path: **B8b → C08 → B8c → B9 captures → B10 → B15**.

### Genuinely sequential residue

| Item | Why unavoidable |
|------|----------------|
| Loading the generated data | C08 must exist before B8c can run it |
| Artifact capture | Objects and data must exist before a query can run |
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

## M3 — Semantic Layer and Realistic Data  ← THE CRITICAL MILESTONE

**Goal**: The ontology exists as a queryable semantic view with canonical metrics, over
realistic, messy, 10-year data that a cleansing layer repairs.

**Build steps**: B8 ✅ → B8b → B8c → B9 (Claude Code: C08 generator)

| Task | Owner |
|------|-------|
| Semantic view with 2 tables, validated; grown to 9 tables + 10 relationships | CoCo ✅ |
| Facts, dimensions, 4 canonical metrics; `SP_METRICS_AS_*` | CoCo ✅ |
| Data spec v2: source changes, mess catalogue, metric and time rules, interfaces (CR-006) | CoCo |
| Seeded SQL data generator in `data_gen/` (CoCo runs it) | Claude Code |
| Load the data; `CONFORMED` cleansing layer under the governed views | CoCo |
| Semantic view v2: every business column, AI instructions, verified queries | CoCo |
| Metadata-driven view generator + name search (Cortex Search) | CoCo |

**Exit criterion**:
```
The 4 metrics return values inside the §3 ranges on the new data, identical across personas
Every repairable defect present in SOURCE, absent in CONFORMED
§7 governed columns unchanged; §4 matrix passes (55 valid, the invalid rejected)
DESCRIBE SEMANTIC VIEW lists every verified query, and each runs
Art 05, 06, 09 re-captured
```

**Risk note**: build incrementally. Semantic view validation is strict about clause
order (FACTS before DIMENSIONS before METRICS) and metric/dimension granularity.

---

## M4 — Conversational Layer

**Goal**: Natural language questions return governed answers, with measured accuracy.

**Build steps**: B10 (Claude Code: C6c)

| Task | Owner |
|------|-------|
| Cortex Agent with Analyst + chart + data-health tools | CoCo |
| Evaluation set + runner (about 25–30 questions: canonical, cross-functional, multi-part, out-of-scope, ambiguous, Hindi); CoCo runs it | Claude Code |
| Agent response parser + proof grid against real JSON | Claude Code |

**Exit criterion**:
```
The 8 canonical answers match art 05
Out-of-scope questions are refused; ambiguous ones get a clarifying question
The evaluation pass rate and latencies are recorded (art 08)
No masked value leaks into an answer
```

**This is the MVP boundary.** After M4 the core product works end to end.

---

## M5 — Quality and Scale

**Goal**: Show the data is trustworthy, and that the core system behaves the same at scale.

**Build steps**: B12 → B13

| Task | Owner |
|------|-------|
| DMF and `SP_DATA_HEALTH` SQL (CoCo runs it) | Claude Code |
| Scale-test harness (CoCo runs it on a zero-copy clone, 100M+ order lines, sized to budget) | Claude Code |
| Running both, and the scale report (art 12) | CoCo |

**Exit criterion**:
```
DMF results visible in DATA_QUALITY_MONITORING_RESULTS; SOURCE shows the injected defects,
CONFORMED shows none of the repairable ones
At scale: every path returns, definitions and SQL shape unchanged, personas identical,
timings and credits recorded (art 12)
```

---

## M6 — Production and Demo

**Goal**: Deployed, hardened, and believable in five minutes.

**Build steps**: B14 → B15 (Claude Code: C09, C05)

| Task | Owner | Judge criterion |
|------|-------|----------------|
| Contract audit (runs Claude Code's live tests) + security review (art 11) | CoCo | Technical Execution |
| Live tests refreshed for the new data and CR-006 | Claude Code | Technical Execution |
| Cost controls: resource monitor, sizing, query tags | CoCo | Technical Execution |
| Deploy to `APP.FORGE_DEMO`; verify it runs in SiS | CoCo | Solution Completeness |
| App production pass: `NULL` handling, paging, as-of date, live mode | Claude Code | Solution Completeness |
| "Disagreement" demo — naive ERP-only SQL vs governed metric | Both | Real World Relevance |
| Demo script rehearsed to 5 minutes; submission README | Claude Code | All three |
| Stretch: parallel multi-part router, KPI shortcut, lineage trace | Both | Technical Execution |

**Exit criterion**: the deployed app runs the demo start to finish in under 5 minutes
without a failure, and every judging criterion has a specific moment in the demo that
addresses it.

---

## Progress Tracker

| Milestone | Status | Exit criterion met |
|-----------|--------|-------------------|
| M0 Foundation | ✅ Complete | Yes |
| M1 Data Foundation | ✅ Complete (v1 data; realistic data comes in M3) | Yes |
| M2 Governance | ✅ Complete | Yes |
| M3 Semantic Layer + realistic data | 🔄 B8 done; B8b next | — |
| M4 Conversational | ⬜ Not started | — |
| M5 Quality and Scale | ⬜ Not started | — |
| M6 Production and Demo | ⬜ Not started | — |
