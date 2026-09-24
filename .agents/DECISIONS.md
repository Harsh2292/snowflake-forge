# Architecture Decision Record

> Log key decisions so both agents (and future-you) understand WHY things are the way they are.

---

## ADR-001: Database Structure

**Date**: 2024-09-24
**Status**: Accepted

**Decision**: Use a single database `SUPPLY_CHAIN_FORGE` with three schemas:
- `RAW` — Source tables with realistic supply chain data
- `GOVERNED` — Views/tables with governance policies applied
- `SEMANTIC` — Semantic views and Cortex Agent

**Rationale**: Judges want to see a clean, production-style architecture. Three schemas show clear data progression (raw → governed → semantic) which demonstrates the ontology concept.

---

## ADR-002: Entity Model

**Date**: 2024-09-24
**Status**: Accepted

**Decision**: Core entities follow the supply chain flow:
```
SUPPLIERS → PARTS → PLANTS → INVENTORY
                                  ↓
CUSTOMERS → ORDERS → ORDER_ITEMS → SHIPMENTS
```

Supporting relationships:
- A supplier supplies many parts
- A part can be sourced from many suppliers (M:N via SUPPLIER_PARTS)
- A plant holds inventory for parts
- An order has many order items, each referencing a part
- A shipment fulfills one or more order items
- A customer places many orders

**Rationale**: This matches real-world ERP data models (SAP MM/SD modules). Judges evaluating "Real World Relevance" will recognize this pattern.

---

## ADR-003: Canonical Metric Definitions

**Date**: 2024-09-24
**Status**: Accepted

**Decision**: Four canonical metrics, each with a single authoritative formula:

| Metric | SQL Formula |
|--------|-------------|
| On-Time Delivery | `COUNT_IF(actual_delivery_date <= promised_delivery_date) / COUNT(*)` |
| Fill Rate | `SUM(quantity_shipped) / SUM(quantity_ordered)` |
| Days of Inventory | `AVG(quantity_on_hand) / NULLIFZERO(AVG(daily_usage))` |
| Landed Cost | `unit_cost + freight_cost + duty_cost + handling_cost` |

**Rationale**: These are the standard supply chain KPIs. The semantic view encodes these formulas so every persona gets the same calculation — this is the core of the "governed conversational analytics" requirement.

---

## ADR-004: Persona Roles

**Date**: 2024-09-24
**Status**: Accepted

**Decision**: Three persona roles, each with distinct data access but SAME metric formulas:

| Role | Sees | Restricted From |
|------|------|----------------|
| `PLANNER_ROLE` | Inventory, orders, demand forecasts | Supplier cost details |
| `BUYER_ROLE` | Supplier info, costs, purchase orders | Customer PII |
| `LOGISTICS_ROLE` | Shipments, delivery tracking, carriers | Supplier financial terms |

**Rationale**: Demonstrates row/column-level access policies while proving the "same metric, same answer" requirement. Different roles see different data scopes but the aggregated metrics resolve identically.

---

## ADR-005: Agent Split (CoCo vs Claude Code)

**Date**: 2024-09-24
**Status**: Accepted

**Decision**: CoCo owns all Snowflake objects (SQL, semantic views, agent config, governance). Claude Code owns all application code (Streamlit, tests, demo scripts). The `.agents/HANDOFF.md` file is the coordination bridge.

**Rationale**: CoCo has direct Snowflake execution + specialized skills (agent-studio, data-governance). Claude Code excels at application scaffolding and test writing. Clean ownership prevents conflicts.
