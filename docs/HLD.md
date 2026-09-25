# High-Level Design (HLD)

**Project**: Supply Chain Forge
**Hackathon**: Snowflake CoCo CLI Hackathon — GCC Edition (Hack2Skill)
**Problem Statement**: Supply Chain Ontology and Governed Conversational Analytics
**Last Updated**: 2026-09-24

---

## 1. The Problem (Restated)

In a real manufacturing company, supply chain data lives in **four disconnected systems**:

| System | What it holds | Who uses it |
|--------|--------------|-------------|
| **ERP** (e.g. SAP) | Customers, sales orders, order lines | Sales, Finance |
| **WMS** (Warehouse Mgmt) | Plants, inventory levels, stock movements | Warehouse staff, Planners |
| **TMS** (Transport Mgmt) | Shipments, carriers, delivery tracking | Logistics |
| **SRM** (Supplier Relationship) | Suppliers, parts, sourcing contracts | Procurement |

Each system has its own column naming, its own definition of "delivered," and its own
notion of a date. When the planner asks "what's our on-time delivery rate?" and the
logistics manager asks the same question, they query different systems with different
formulas and get **different numbers**. Nobody trusts anybody's report.

**This is the actual problem.** Not "we need a dashboard." The problem is *semantic
disagreement* across organizational silos.

---

## 2. The Solution (What We Build)

A **governed semantic layer** that sits above all four source systems and becomes the
single arbiter of what every business term means.

```
┌──────────────────────────────────────────────────────────────────────┐
│  LAYER 4 — CONVERSATION                                              │
│  Cortex Agent  +  Streamlit persona app                              │
│  "What was our fill rate for electronics in APAC last quarter?"      │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ natural language
┌───────────────────────────────▼──────────────────────────────────────┐
│  LAYER 3 — SEMANTIC (the ontology, as code)                          │
│  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV                         │
│                                                                       │
│  • Logical tables + PRIMARY KEYs      → entities                     │
│  • RELATIONSHIPS                      → the ontology graph            │
│  • DIMENSIONS (with SYNONYMS)         → business vocabulary           │
│  • FACTS                              → atomic measures               │
│  • METRICS                            → THE canonical formulas        │
│  • AI_VERIFIED_QUERIES                → pinned, human-verified SQL    │
│  • AI_SQL_GENERATION instructions     → guardrails for the LLM        │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ SELECT on
┌───────────────────────────────▼──────────────────────────────────────┐
│  LAYER 2 — GOVERNED (conformed + protected)                          │
│  SUPPLY_CHAIN_FORGE.GOVERNED.*                                       │
│                                                                       │
│  • Conformed views: cryptic source columns → business names           │
│  • Row access policies      → persona sees only their scope           │
│  • Masking policies         → PII / commercial terms hidden           │
│  • Object tags              → entity type, sensitivity, metric family │
│  • Data metric functions    → freshness, nulls, referential integrity │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ reads
┌───────────────────────────────▼──────────────────────────────────────┐
│  LAYER 1 — SOURCE SYSTEMS (deliberately messy + inconsistent)         │
│                                                                       │
│  ERP_SOURCE      WMS_SOURCE      TMS_SOURCE      SRM_SOURCE          │
│  ──────────      ──────────      ──────────      ──────────          │
│  KNA1 customers  T001W plants    VTTK shipments  LFA1 suppliers      │
│  VBAK orders     MARD inventory  carriers        MARA parts          │
│  VBAP order_line                                 sourcing            │
│                                                                       │
│  Column naming is intentionally SAP-like and inconsistent:            │
│  ERD_DAT vs PROM_DLV_DT vs DELIV_DATE — all mean "promised date"      │
└──────────────────────────────────────────────────────────────────────┘
```

### Why the four-schema source design matters

Most hackathon submissions will have one clean `RAW` schema. Ours simulates the actual
enterprise mess. In the demo we can show:

1. Four schemas, four naming conventions, three different "delivery date" columns
2. A query against ERP alone gives one OTD number; TMS alone gives another
3. The semantic layer resolves it to **one** number, and we can point to the exact
   `METRICS` clause that defines it

That is the problem statement, demonstrated rather than asserted.

---

## 3. Tech Stack (Decided)

| Layer | Technology | Why this and not alternatives |
|-------|-----------|-------------------------------|
| Storage / compute | **Snowflake** (Azure Central India, v10.34.101) | Required by hackathon |
| Source data generation | **SQL** — `GENERATOR` + `SEQ4()` + `UNIFORM`/`NORMAL` | Reproducible, version-controlled, no CSV files to lose. Judges can re-run it. |
| Conformance layer | **Snowflake views** | No extra storage, no refresh lag, zero pipeline to maintain during a hackathon |
| Ontology | **`CREATE SEMANTIC VIEW` DDL** (not YAML) | DDL is the native object form, is diffable in git, and is what `DESCRIBE SEMANTIC VIEW` returns. YAML would be an extra translation step. |
| Metric governance | **`METRICS` clause + `AI_VERIFIED_QUERIES`** | The metric formula lives in exactly one place. VQRs pin known questions to verified SQL so the LLM cannot re-derive a metric differently. |
| Access control | **Row access policies + masking policies + object tags** | This is literally what "governed" means in the problem statement |
| Data quality | **Data Metric Functions (DMFs)** | Native, schedulable, and surfaces in the demo as a trust signal |
| Conversation | **Cortex Agent** with `cortex_analyst_text_to_sql` + `data_to_chart` tools | Agent (not bare Analyst) gives us planning, clarification, and multi-step reasoning |
| Agent invocation | **`SNOWFLAKE.CORTEX.DATA_AGENT_RUN()`** | Callable from plain SQL → the Streamlit app needs no REST plumbing, no PAT, no auth code |
| Demo UI | **Streamlit in Snowflake** | Runs inside Snowflake, inherits the session role, nothing to host |
| Charts | **Plotly** (via Streamlit) | Already available in SiS |
| Tests | **Python + pytest** | Cross-persona consistency assertions |
| LLM | **`orchestration: auto`** | Snowflake picks the best available model; `ANY_REGION` is already enabled on this account |

### What we deliberately do NOT use

- **No external LLM API** — Cortex is in-account; no keys, no egress, no vendor story to defend
- **No vector DB / RAG framework** — the ontology is structured; semantic views are the grounding
- **No LangChain / LlamaIndex** — Cortex Agent *is* the orchestrator
- **No dbt** — 4 layers of views does not justify a transformation framework for a hackathon
- **No dynamic tables / materializations** for MVP — views are instant and free; add later only if latency demands it
- **No Docker / external hosting** — SiS removes the entire deployment surface

---

## 4. The Ontology (Entities & Relationships)

```
                    ┌───────────┐
                    │ SUPPLIERS │
                    └─────┬─────┘
                          │ supplies (M:N via SOURCING)
                    ┌─────▼─────┐
                    │   PARTS   │◄──────────────┐
                    └─────┬─────┘               │
                          │ stocked at          │ ordered as
                    ┌─────▼─────┐         ┌─────┴──────┐
                    │ INVENTORY │         │ ORDER_LINES│
                    └─────┬─────┘         └─────┬──────┘
                          │ held at             │ belongs to
                    ┌─────▼─────┐         ┌─────▼─────┐
                    │  PLANTS   │         │  ORDERS   │
                    └─────┬─────┘         └─────┬─────┘
                          │ ships from          │ placed by
                    ┌─────▼─────┐         ┌─────▼─────┐
                    │ SHIPMENTS │────────►│ CUSTOMERS │
                    └───────────┘ delivers└───────────┘
```

**9 entities**: SUPPLIERS, PARTS, SOURCING, PLANTS, INVENTORY, CUSTOMERS, ORDERS,
ORDER_LINES, SHIPMENTS

**Hierarchies** (needed for drill-down questions):
- Geography: Plant → Country → Region → Global
- Product: Part → Subcategory → Category
- Supplier: Supplier → Tier (1/2/3) → Strategic classification
- Time: Date → Week → Month → Quarter → Year

---

## 5. Canonical Metrics (The Core Contract)

These four formulas are the single source of truth. They live in the `METRICS` clause
of the semantic view and nowhere else.

| # | Metric | Formula | Grain | Why it's contentious in real life |
|---|--------|---------|-------|-----------------------------------|
| 1 | **On-Time Delivery (OTD)** | `COUNT_IF(actual_delivery_date <= promised_delivery_date) / COUNT(*)` | Shipment | Logistics measures dock-out; Sales measures customer receipt; ERP has a different promised date than TMS |
| 2 | **Fill Rate** | `SUM(quantity_shipped) / SUM(quantity_ordered)` | Order line | Some teams count partial lines as a full miss; others pro-rate |
| 3 | **Days of Inventory (DOI)** | `AVG(quantity_on_hand) / NULLIFZERO(AVG(daily_usage))` | Plant × Part × Day | Some use on-hand; others use on-hand minus reserved |
| 4 | **Landed Cost** | `unit_cost + freight_cost + duty_cost + handling_cost` | Shipment line | Freight is often excluded, or duties allocated differently |

Each metric also gets:
- A `COMMENT` stating the business definition in plain English
- `WITH SYNONYMS` so "OTD", "on time %", "delivery performance" all resolve
- At least one `AI_VERIFIED_QUERIES` entry pinning the canonical question to verified SQL

---

## 6. Personas & Governance Model

Three roles. Each sees a **different slice of data** but gets the **identical metric value**.
That contrast is the demo.

| Role | Can see | Cannot see | Represents |
|------|---------|-----------|-----------|
| `PLANNER_ROLE` | Inventory, orders, parts, plants, demand | Supplier unit cost, payment terms | Production planner |
| `BUYER_ROLE` | Suppliers, parts, sourcing, costs, landed cost | Customer name / email / credit limit (PII) | Procurement lead |
| `LOGISTICS_ROLE` | Shipments, carriers, plants, delivery dates | Supplier payment terms, customer credit limit | Logistics coordinator |

Enforcement:
- **Masking policies** on `unit_cost`, `payment_terms`, `contact_email`, `credit_limit`
- **Row access policy** on `PLANTS` — regional staff see only their region (demonstrable)
- **Object tags** — `ENTITY_TYPE`, `SENSITIVITY`, `METRIC_FAMILY`, `SOURCE_SYSTEM`

**The proof**: all three roles ask "what is our Q3 on-time delivery rate?" → same number.
Then each asks a follow-up in their own domain → different, role-appropriate detail.

---

## 7. Success Criteria (MVP Definition of Done)

The MVP is complete when **all** of these are true:

1. Four source schemas exist with realistic, internally-consistent, deliberately-messy data
2. Governed views conform the naming and apply masking + row access
3. One semantic view exposes 9 entities, the relationship graph, and 4 canonical metrics
4. `SELECT ... FROM SEMANTIC_VIEW(...)` returns correct values for all 4 metrics
5. A Cortex Agent answers a natural-language question through the semantic view
6. Three persona roles produce **identical metric values** and **different detail scope**
7. A Streamlit app demonstrates 1–6 with a persona switcher

Everything beyond this list is an enhancement, not MVP.

---

## 8. Post-MVP Enhancements (ranked by judge impact)

| Rank | Enhancement | Maps to judging criterion |
|------|-------------|---------------------------|
| 1 | DMF quality checks visible in the app | Solution Completeness |
| 2 | Lineage trace: source column → metric → answer | Technical Execution |
| 3 | Edge-case handling: ambiguous / out-of-scope / cross-domain questions | Technical Execution |
| 4 | Multilingual query demo (Hindi → same answer) | Real World Relevance |
| 5 | The "disagreement" demo: naive ERP-only SQL vs governed metric | Real World Relevance |
| 6 | Charts via the agent's `data_to_chart` tool | Solution Completeness |
| 7 | Data volume increase + seasonality | Real World Relevance |

---

## 9. Cost & Credit Strategy

**Budget**: ~$390 remaining. **Consumed so far**: 0.43 credits. This is not a real
constraint, but we stay disciplined so it never becomes one.

| Control | Setting |
|---------|---------|
| Warehouse size | `XSMALL` only |
| Auto-suspend | `60` seconds |
| Auto-resume | `TRUE` |
| Materializations | None during MVP (`MAX_STALENESS` unset) |
| Agent testing | Deliberate single calls; never in a loop |
| Agent token budget | `budget: { seconds: 45, tokens: 16000 }` in the agent spec |
| Data generation | One-time `GENERATOR` run, re-runnable but not scheduled |
| Streamlit warehouse | Same `FORGE_WH`, suspends when idle |

Estimated total for the whole project: **under 15 credits**.

---

## 10. Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Semantic view validation errors (strict rules on facts/dimensions/metrics ordering, granularity) | Blocks everything downstream | Build the semantic view incrementally — 2 tables first, validate, then grow. Never write all 9 entities blind. |
| Row access policy silently changes metric values across personas | Breaks the core claim | Test each metric per role explicitly and assert equality. Policies must restrict *detail rows*, not the aggregate population. |
| Agent picks a different SQL path than the canonical metric | Inconsistent answers | `AI_VERIFIED_QUERIES` for every canonical question + `AI_SQL_GENERATION` instructions forbidding metric re-derivation |
| Generated data doesn't produce sensible metric values (e.g. 100% OTD) | Demo looks fake | Target explicit distributions: ~87% OTD, ~93% fill rate, DOI 15–45 days |
| Streamlit-in-Snowflake role handling differs from local | Demo fails on stage | Build and test in SiS from the start, not locally |
| Agent needs *default* role privileges, not session role | Agent calls fail | Grant required privileges to the default role explicitly (documented Snowflake gotcha) |
