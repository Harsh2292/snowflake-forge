# COCO.md — CoCo Agent Entry Point

> **Read this file at the start of every CoCo session.**
>
> Then read, in this order:
> 1. **`.agents/NEXT.md`** — names the exact task card to open. Start here.
> 2. `docs/CONTRACT.md` — the frozen interface. Binding. Do not deviate.
> 3. The task card named in `NEXT.md` — self-contained, has its own gate
>
> Reference when needed: `docs/HLD.md` (architecture), `docs/LLD.md` (exact schemas),
> `docs/GAPS_RESOLVED.md` (resolved design questions), `docs/SESSION_LOG.md` (history).

## How Work Is Organised

Work is broken into **task cards** — one per build step, each executable in about one
session, each carrying its own gate.

```
.agents/NEXT.md                 ← what to do right now
.agents/tasks/coco/B01…B17.md   ← your cards
.agents/tasks/claude/C01…C06.md ← Claude Code's cards
```

Execute one card at a time. A card is done when its **Gate** passes, not when the SQL
runs. Then update `NEXT.md`, `HANDOFF.md`, and `SESSION_LOG.md` as the card instructs.

**Task Card & Planning Rule**: When moving to the next task, first enter plan mode, plan the task, author the task card markdown file (`.agents/tasks/coco/Bxx_...md`), get user confirmation, and only then proceed with implementation.

## The Contract Is Binding

`docs/CONTRACT.md` is frozen at v1.1. Claude Code is building the entire application
against it **in parallel, right now**, using a mock data layer. Every metric identifier,
dimension identifier, governed view column name, role name, and FQN you create must
match it exactly.

If reality forces a deviation, append a Change Request to `CONTRACT.md` §11 and tell the
user. **Never silently rename anything** — that is the one action that breaks the other
agent's work irrecoverably.

Build step **B13** is a full conformance audit against the contract. Do not skip it.

## Auto-Mode Rules

- **Auto-mode is ON** — execute commands without asking for confirmation each time.
- **DO NOT** create git commits, push, or create PRs automatically.
- Everything else (SQL execution, file writes, deployments) — just do it.

## Working Branch

`development` — all dev happens here. Merge to `main` only after testing.

## Project: Supply Chain Forge

**Hackathon**: Snowflake CoCo CLI Hackathon (GCC Edition) — Hack2Skill
**Problem Statement**: Supply Chain Ontology and Governed Conversational Analytics

### What We're Building

A governed "single source of truth" for supply chain data in Snowflake:

1. **Supply Chain Ontology** — Entity-relationship model: Supplier → Part → Plant → Shipment → Order → Customer
2. **Semantic Views** — Business meaning encoded as semantic views with canonical metrics (OTD, Fill Rate, DOI, Landed Cost)
3. **Cortex Agent** — Natural language analytics grounded in the semantic views
4. **Cross-Persona Proof** — Same question from Planning, Procurement, or Logistics returns the same answer

### Judging Criteria

| Criteria | What Judges Want |
|----------|-----------------|
| Real World Relevance | Realistic data model, actual supply chain metrics |
| Technical Execution | Semantic views + Cortex Agent working end-to-end |
| Solution Completeness | Ontology → Semantic Views → Agent → Multi-persona demo |

## CoCo Ownership (YOU own these)

| Area | Path | Skills to Use |
|------|------|--------------|
| Database setup | `sql/01_setup/` | `sql-author` |
| Table DDL | `sql/02_tables/` | `sql-author` |
| Sample data | `sql/03_sample_data/` | `sql-author` |
| Governance | `sql/04_governance/` | `data-governance` |
| Data quality | `sql/05_quality/` | `data-quality` |
| Semantic views | `semantic/` | `agent-studio` |
| Cortex Agent | `agent/` | `agent-studio` |
| Lineage validation | — | `lineage` |

### DO NOT TOUCH (Claude Code owns these)

- `app/` — Streamlit demo application
- `tests/` — Cross-persona consistency tests
- `demo/` — Demo presentation scripts

## Snowflake Connection

- **Connection**: `tyduokn-gf25237` (account `DA53081`, `AZURE_CENTRALINDIA`)
- **Target Database**: `SUPPLY_CHAIN_FORGE`
- **Source schemas**: `ERP_SOURCE`, `WMS_SOURCE`, `TMS_SOURCE`, `SRM_SOURCE`
- **Derived schemas**: `GOVERNED`, `SEMANTIC`, `APP`
- **Warehouse**: `FORGE_WH` (XSMALL, auto-suspend 60s)
- **Roles**: `FORGE_ADMIN`, `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE`

### Verified account capabilities

- `CORTEX_ENABLED_CROSS_REGION = ANY_REGION` — all frontier models available
- Semantic views support `AI_VERIFIED_QUERIES`, `AI_SQL_GENERATION`,
  `AI_QUESTION_CATEGORIZATION` in DDL
- `SNOWFLAKE.CORTEX.DATA_AGENT_RUN()` available — agent callable from plain SQL
- Credits consumed to date: 0.43 of ~$390 budget. Not a constraint; keep warehouses XS
  with 60s auto-suspend and avoid materializations.

## Coordination Protocol

1. At session start, read `docs/SESSION_LOG.md` for the exact next action
2. Work the queue in `.agents/tasks/COCO_TASKS.md`
3. A task is done when its **gate** passes, not when the SQL merely runs
4. At session end, append an entry to `docs/SESSION_LOG.md`
5. Update `docs/MILESTONES.md` progress tracker when a milestone completes
6. Update `.agents/HANDOFF.md` when Claude Code needs something from you
7. Log architecture decisions in `.agents/DECISIONS.md`

## Current State

**Milestone**: M0 complete. M1 (Data Foundation) is next.
**Next action**: See `docs/SESSION_LOG.md` — execute build step B1.

## Critical Gotchas

- **Cortex Agents use the caller's DEFAULT role**, not the session role. Grant agent
  privileges to the default role explicitly or agent calls fail.
- **Semantic view clause order is enforced**: `TABLES` → `RELATIONSHIPS` → `FACTS` →
  `DIMENSIONS` → `METRICS`. Build incrementally (2 tables first), never all 9 blind.
- **Row access policies must not change metric aggregates** across personas, or the
  core hackathon claim breaks. Policies restrict detail rows; consistency tests assert
  aggregate equality.
- ERP `VBAK.ERDAT` and TMS `VTTK.PROM_DLV_DT` deliberately disagree. Only TMS is
  authoritative. Never expose ERP's date as a promised date in the governed layer.
