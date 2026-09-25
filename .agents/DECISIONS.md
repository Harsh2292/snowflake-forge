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
**Status**: Superseded by ADR-006

**Decision**: CoCo owns all Snowflake objects (SQL, semantic views, agent config, governance). Claude Code owns all application code (Streamlit, tests, demo scripts). The `.agents/HANDOFF.md` file is the coordination bridge.

**Rationale**: CoCo has direct Snowflake execution + specialized skills (agent-studio, data-governance). Claude Code excels at application scaffolding and test writing. Clean ownership prevents conflicts.

**Why superseded**: the ownership split was right, but the *sequencing* was wrong — it left Claude Code blocked and idle until M4. See ADR-006.

---

## ADR-006: Frozen Interface Contract for Parallel Execution

**Date**: 2026-09-24
**Status**: Accepted

**Decision**: Introduce `docs/CONTRACT.md`, frozen at v1.0, as the binding interface
between the two agents. It fixes: FQNs, role names, metric identifiers, dimension
identifiers, valid metric × dimension pairings, governed view column names, the masking
matrix, query patterns, expected value ranges, and mock fixtures.

Neither agent may change it unilaterally. Deviations are filed as Change Requests in
§11 and escalated to the user. CoCo's build step B13 is a full conformance audit against
it.

Claude Code builds the entire application against the contract using a mock data layer
(`USE_MOCK_DATA = True`) while CoCo builds Snowflake reality to match. One flag flip
switches the app to live.

**Rationale**: the previous plan blocked Claude Code until milestone M4 — roughly 70% of
the project spent idle. The blocker was not ownership, it was the absence of a stable
interface to build against. Freezing the interface removes the dependency without
creating collision risk, because both sides target the same immutable spec rather than
each other's in-progress work.

**Consequence**: integration risk shifts from "will the halves fit?" to "does reality
match the contract?" — which is a single auditable check (B13) rather than an open-ended
debugging session at the end.

---

## ADR-007: Two MCP Servers, Deliberately Split

**Date**: 2026-09-24
**Status**: Accepted

**Decision**: Create two Snowflake-managed MCP servers rather than one:

| Server | Tools | Purpose |
|--------|-------|---------|
| `SUPPLY_CHAIN_MCP` | `CORTEX_AGENT_RUN`, `CORTEX_ANALYST_MESSAGE` | The governed path |
| `SUPPLY_CHAIN_MCP_RO` | `SYSTEM_EXECUTE_SQL` (read-only, least-privileged) | Schema introspection only |

**Rationale**: Snowflake's own guidance warns that exposing `SYSTEM_EXECUTE_SQL` on the
same server as an agent tool lets an MCP client bypass the semantic view, its metric
definitions, and its verified queries. For a project whose entire thesis is *governed*
analytics, co-locating them would undermine the claim. Splitting them is both the correct
security posture and a defensible design choice to explain to judges.

**Consequence**: Claude Code uses the read-only server for development verification and
the governed server for actual agent calls. Grants are issued per tool, since `USAGE` on
an MCP server does not imply tool access.
