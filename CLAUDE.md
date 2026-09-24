# CLAUDE.md — Claude Code Agent Entry Point

> **This file is auto-read at session start.**
> Then read `.agents/HANDOFF.md` for the latest project state.

## Project: Supply Chain Forge

**Hackathon**: Snowflake CoCo CLI Hackathon (GCC Edition) — Hack2Skill
**Problem Statement**: Supply Chain Ontology and Governed Conversational Analytics

### What We're Building

A governed "single source of truth" for supply chain data in Snowflake:

1. **Supply Chain Ontology** — Entity-relationship model: Supplier → Part → Plant → Shipment → Order → Customer
2. **Semantic Views** — Business meaning encoded as semantic views with canonical metrics
3. **Cortex Agent** — Natural language analytics grounded in the semantic views
4. **Cross-Persona Proof** — Same question from different personas returns the same answer

### Canonical Metrics

| Metric | Formula | Meaning |
|--------|---------|---------|
| On-Time Delivery (OTD) | `COUNT(delivered <= promised) / COUNT(total)` | % orders delivered by promised date |
| Fill Rate | `SUM(qty_fulfilled) / SUM(qty_ordered)` | % demand fulfilled from stock |
| Days of Inventory (DOI) | `AVG(inventory_on_hand) / AVG(daily_usage)` | How long current inventory lasts |
| Landed Cost | `unit_cost + freight + duties + handling` | Total cost to destination |

## Claude Code Ownership (YOU own these)

| Area | Path | What to Build |
|------|------|--------------|
| Streamlit app | `app/streamlit_app.py` | Demo app with persona switcher |
| App utilities | `app/utils/persona_queries.py` | Query builder per persona |
| Dependencies | `app/requirements.txt` | Python deps |
| Consistency tests | `tests/consistency/test_cross_persona.py` | Prove metrics are identical across personas |
| Demo script | `demo/demo_script.md` | Hackathon presentation guide |

### DO NOT TOUCH (CoCo owns these)

- `sql/` — All SQL scripts (DDL, DML, governance, quality)
- `semantic/` — Semantic view YAML definitions
- `agent/` — Cortex Agent configuration

## Key Snowflake Objects (set by CoCo)

Check `.agents/HANDOFF.md` for the latest deployed object names. Expected:

- **Database**: `SUPPLY_CHAIN_FORGE`
- **Semantic View**: `SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV`
- **Cortex Agent**: `SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT`
- **Persona Roles**: `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE`

## Streamlit App Requirements

The demo app should:
1. Have a persona selector (dropdown: Planner, Buyer, Logistics Manager)
2. Show a natural language query input
3. Route queries through the Cortex Agent
4. Display results with the semantic view lineage (which metric definition was used)
5. Have a "consistency proof" tab that runs the same query as all 3 personas and shows identical results

## Coordination Protocol

1. Before starting work, read `.agents/HANDOFF.md`
2. After completing a task, update `.agents/HANDOFF.md` under `## Latest from Claude Code`
3. Mark completed tasks in `.agents/TASKS.md`
4. Do NOT deploy to Snowflake — CoCo handles all Snowflake operations

## Dependencies on CoCo

Before you can build the app, CoCo must have:
- [ ] Created the database and tables
- [ ] Loaded sample data
- [ ] Deployed the semantic view
- [ ] Deployed the Cortex Agent
- [ ] Set up persona roles with appropriate grants

Check HANDOFF.md — if these aren't done, tell the user to switch to CoCo first.
