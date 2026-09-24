# COCO.md — CoCo Agent Entry Point

> **Read this file at the start of every CoCo session.**
> Then read `.agents/HANDOFF.md` for the latest project state.

## Auto-Mode Rules

- **Auto-mode is ON** — execute commands without asking for confirmation each time.
- **DO NOT** create git commits, push, or create PRs automatically.
- Everything else (SQL execution, file writes, deployments) — just do it.

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

- **Connection**: `tyduokn-gf25237`
- **Target Database**: `SUPPLY_CHAIN_FORGE`
- **Schemas**: `RAW`, `GOVERNED`, `SEMANTIC`
- **Warehouse**: `FORGE_WH` (XS)
- **Roles**: `FORGE_ADMIN`, `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE`

## Coordination Protocol

1. Before starting work, read `.agents/HANDOFF.md`
2. After completing a task, update `.agents/HANDOFF.md` under `## Latest from CoCo`
3. Mark completed tasks in `.agents/TASKS.md`
4. Log any architecture decisions in `.agents/DECISIONS.md`

## Quick Start (What to do first)

If this is a fresh session and nothing is deployed yet:
1. Run `sql/01_setup/01_database.sql` to create the database and schemas
2. Run `sql/01_setup/02_roles_grants.sql` to create persona roles
3. Run table DDLs in `sql/02_tables/` in any order
4. Run `sql/03_sample_data/seed_data.sql` to load sample data
5. Build semantic view with `agent-studio` skill using `semantic/supply_chain.yaml`
6. Deploy Cortex Agent using `agent/supply_chain_agent.yaml`
7. Update HANDOFF.md so Claude Code can build the demo layer
