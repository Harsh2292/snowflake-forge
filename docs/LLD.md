# Low-Level Design (LLD)

**Companion to**: `docs/HLD.md`
**Purpose**: Exact schemas, exact SQL, exact build order. No ambiguity left for implementation.
**Last Updated**: 2026-09-24

---

## 1. Object Inventory

| Object | FQN | Owner |
|--------|-----|-------|
| Database | `SUPPLY_CHAIN_FORGE` | CoCo |
| Warehouse | `FORGE_WH` (XSMALL, auto-suspend 60s) | CoCo |
| Schema — ERP source | `SUPPLY_CHAIN_FORGE.ERP_SOURCE` | CoCo |
| Schema — WMS source | `SUPPLY_CHAIN_FORGE.WMS_SOURCE` | CoCo |
| Schema — TMS source | `SUPPLY_CHAIN_FORGE.TMS_SOURCE` | CoCo |
| Schema — SRM source | `SUPPLY_CHAIN_FORGE.SRM_SOURCE` | CoCo |
| Schema — governed | `SUPPLY_CHAIN_FORGE.GOVERNED` | CoCo |
| Schema — semantic | `SUPPLY_CHAIN_FORGE.SEMANTIC` | CoCo |
| Schema — app | `SUPPLY_CHAIN_FORGE.APP` | CoCo (Claude deploys into it) |
| Semantic view | `SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV` | CoCo |
| Agent | `SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT` | CoCo |
| Roles | `FORGE_ADMIN`, `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE` | CoCo |
| Streamlit | `SUPPLY_CHAIN_FORGE.APP.FORGE_DEMO` | Claude Code |

---

## 2. Source Table Schemas (deliberately inconsistent naming)

### 2.1 `SRM_SOURCE` — Supplier Relationship Management

**`SRM_SOURCE.LFA1` (suppliers)** — SAP-style table name
| Column | Type | Notes |
|--------|------|-------|
| `LIFNR` | VARCHAR(10) | Supplier ID (PK) |
| `NAME1` | VARCHAR(100) | Supplier name |
| `LAND1` | VARCHAR(3) | Country code |
| `REGIO` | VARCHAR(20) | Region: APAC / EMEA / AMER |
| `SUPP_TIER` | NUMBER(1) | 1, 2, or 3 |
| `LEAD_TM_DAYS` | NUMBER(3) | Lead time in days |
| `RELIAB_SCR` | NUMBER(3,2) | Reliability 0.00–1.00 |
| `ZTERM` | VARCHAR(20) | Payment terms — **SENSITIVE** |
| `EMAIL` | VARCHAR(100) | Contact — **PII** |

**`SRM_SOURCE.MARA` (parts)**
| Column | Type | Notes |
|--------|------|-------|
| `MATNR` | VARCHAR(18) | Part ID (PK) |
| `MAKTX` | VARCHAR(100) | Part description |
| `MATKL` | VARCHAR(30) | Category |
| `SUBCAT` | VARCHAR(30) | Subcategory |
| `STPRS` | NUMBER(12,2) | Standard unit cost — **SENSITIVE** |
| `BRGEW` | NUMBER(10,3) | Gross weight kg |
| `CRIT_FLG` | BOOLEAN | Is critical part |

**`SRM_SOURCE.SOURCING` (supplier↔part, M:N)**
| Column | Type | Notes |
|--------|------|-------|
| `SOURCE_ID` | VARCHAR(20) | PK |
| `LIFNR` | VARCHAR(10) | FK → LFA1 |
| `MATNR` | VARCHAR(18) | FK → MARA |
| `IS_PRIMARY` | BOOLEAN | Primary source flag |
| `CONTRACT_PRICE` | NUMBER(12,2) | **SENSITIVE** |

### 2.2 `WMS_SOURCE` — Warehouse Management

**`WMS_SOURCE.T001W` (plants)**
| Column | Type | Notes |
|--------|------|-------|
| `WERKS` | VARCHAR(4) | Plant ID (PK) |
| `NAME1` | VARCHAR(100) | Plant name |
| `LAND1` | VARCHAR(3) | Country |
| `REGION_CD` | VARCHAR(20) | APAC / EMEA / AMER |
| `PLANT_TYPE` | VARCHAR(20) | MFG / DC / HUB |
| `CAPACITY_UNITS` | NUMBER(10) | Capacity |

**`WMS_SOURCE.MARD` (inventory snapshots)**
| Column | Type | Notes |
|--------|------|-------|
| `INV_KEY` | VARCHAR(40) | PK — `WERKS‖MATNR‖SNAP_DT` |
| `WERKS` | VARCHAR(4) | FK → T001W |
| `MATNR` | VARCHAR(18) | FK → MARA |
| `LABST` | NUMBER(12,3) | Quantity on hand |
| `INSME` | NUMBER(12,3) | Quantity reserved |
| `REORD_PT` | NUMBER(12,3) | Reorder point |
| `DAILY_USG` | NUMBER(12,3) | Daily usage rate |
| `SNAP_DT` | DATE | Snapshot date |

### 2.3 `ERP_SOURCE` — Enterprise Resource Planning

**`ERP_SOURCE.KNA1` (customers)**
| Column | Type | Notes |
|--------|------|-------|
| `KUNNR` | VARCHAR(10) | Customer ID (PK) |
| `NAME1` | VARCHAR(100) | Company name — **PII** |
| `EMAIL` | VARCHAR(100) | **PII** |
| `LAND1` | VARCHAR(3) | Country |
| `REGIO` | VARCHAR(20) | Region |
| `KTOKD` | VARCHAR(20) | Segment: ENTERPRISE / MIDMARKET / SMB |
| `KLIMK` | NUMBER(15,2) | Credit limit — **SENSITIVE** |

**`ERP_SOURCE.VBAK` (order headers)**
| Column | Type | Notes |
|--------|------|-------|
| `VBELN` | VARCHAR(10) | Order ID (PK) |
| `KUNNR` | VARCHAR(10) | FK → KNA1 |
| `AUDAT` | DATE | Order date |
| `ERDAT` | DATE | **ERP's promised date** (differs from TMS!) |
| `GBSTK` | VARCHAR(20) | Status: OPEN / SHIPPED / DELIVERED / CANCELLED |
| `PRIO` | VARCHAR(10) | HIGH / NORMAL / LOW |

**`ERP_SOURCE.VBAP` (order lines)**
| Column | Type | Notes |
|--------|------|-------|
| `LINE_ID` | VARCHAR(20) | PK |
| `VBELN` | VARCHAR(10) | FK → VBAK |
| `MATNR` | VARCHAR(18) | FK → MARA |
| `WERKS` | VARCHAR(4) | FK → T001W (fulfilling plant) |
| `KWMENG` | NUMBER(12,3) | Quantity ordered |
| `QTY_SHIPPED` | NUMBER(12,3) | Quantity shipped (≤ ordered) |
| `NETPR` | NUMBER(12,2) | Unit price |

### 2.4 `TMS_SOURCE` — Transport Management

**`TMS_SOURCE.VTTK` (shipments)**
| Column | Type | Notes |
|--------|------|-------|
| `TKNUM` | VARCHAR(10) | Shipment ID (PK) |
| `VBELN` | VARCHAR(10) | FK → VBAK |
| `WERKS` | VARCHAR(4) | FK → T001W (origin) |
| `CARRIER_CD` | VARCHAR(20) | Carrier code |
| `DPTBG` | DATE | Ship date |
| `PROM_DLV_DT` | DATE | **TMS's promised date** (authoritative) |
| `ACT_DLV_DT` | DATE | Actual delivery (NULL if in transit) |
| `FREIGHT_AMT` | NUMBER(12,2) | Freight cost |
| `DUTY_AMT` | NUMBER(12,2) | Duty cost |
| `HANDLING_AMT` | NUMBER(12,2) | Handling cost |
| `SHP_STATUS` | VARCHAR(20) | IN_TRANSIT / DELIVERED / DELAYED |

> **The deliberate conflict**: `ERP_SOURCE.VBAK.ERDAT` and `TMS_SOURCE.VTTK.PROM_DLV_DT`
> both claim to be "the promised date" and they disagree on ~20% of orders. The governed
> layer declares TMS authoritative. This is the demo's opening hook.

---

## 3. Data Generation Targets

| Table | Rows | Distribution requirements |
|-------|------|--------------------------|
| `LFA1` (suppliers) | 60 | Tier 1: 20%, Tier 2: 50%, Tier 3: 30%. Reliability 0.70–0.99 |
| `MARA` (parts) | 250 | 6 categories × 4 subcategories. ~15% critical |
| `SOURCING` | 400 | Avg 1.6 suppliers per part; one `IS_PRIMARY` per part |
| `T001W` (plants) | 12 | 4 APAC, 4 EMEA, 4 AMER. Mix MFG/DC/HUB |
| `MARD` (inventory) | ~9,000 | 12 plants × 250 parts sampled × 30 daily snapshots. DOI 15–45 days |
| `KNA1` (customers) | 120 | 3 segments, 3 regions |
| `VBAK` (orders) | 800 | 12 months, seasonal Q4 uplift. ~5% cancelled |
| `VBAP` (order lines) | ~2,400 | Avg 3 lines/order. Fill rate ≈ 93% |
| `VTTK` (shipments) | ~900 | ~1.1 shipments/order. OTD ≈ 87%. ~8% still in transit |

**Generation method**: `INSERT ... SELECT` from `TABLE(GENERATOR(ROWCOUNT => n))` using
`SEQ4()`, `UNIFORM()`, `NORMAL()`, `RANDOM()` with a fixed seed where supported so runs
are reproducible.

**Target metric outcomes** (verify after load):
- OTD ≈ 0.87
- Fill rate ≈ 0.93
- DOI between 15 and 45
- Landed cost = 8–18% premium over unit cost

---

## 4. Governed Layer — Conformed Views

Each view renames cryptic source columns to business vocabulary and resolves conflicts.

| View | Source | Key transformations |
|------|--------|--------------------|
| `GOVERNED.V_SUPPLIER` | `SRM_SOURCE.LFA1` | `LIFNR`→`supplier_id`, `NAME1`→`supplier_name`, `REGIO`→`region`, `ZTERM`→`payment_terms` (masked) |
| `GOVERNED.V_PART` | `SRM_SOURCE.MARA` | `MATNR`→`part_id`, `MAKTX`→`part_name`, `MATKL`→`category`, `STPRS`→`unit_cost` (masked) |
| `GOVERNED.V_SOURCING` | `SRM_SOURCE.SOURCING` | `CONTRACT_PRICE` masked |
| `GOVERNED.V_PLANT` | `WMS_SOURCE.T001W` | `WERKS`→`plant_id`, `REGION_CD`→`region`. Row access policy attached here |
| `GOVERNED.V_INVENTORY` | `WMS_SOURCE.MARD` | `LABST`→`quantity_on_hand`, `INSME`→`quantity_reserved`, `DAILY_USG`→`daily_usage` |
| `GOVERNED.V_CUSTOMER` | `ERP_SOURCE.KNA1` | `KUNNR`→`customer_id`, `NAME1`→`customer_name` (masked), `KLIMK`→`credit_limit` (masked) |
| `GOVERNED.V_ORDER` | `ERP_SOURCE.VBAK` | `VBELN`→`order_id`, `AUDAT`→`order_date`. **`ERDAT` deliberately NOT exposed as promised date** |
| `GOVERNED.V_ORDER_LINE` | `ERP_SOURCE.VBAP` | `KWMENG`→`quantity_ordered`, `QTY_SHIPPED`→`quantity_shipped` |
| `GOVERNED.V_SHIPMENT` | `TMS_SOURCE.VTTK` | `PROM_DLV_DT`→`promised_delivery_date` (**authoritative**), `ACT_DLV_DT`→`actual_delivery_date`, cost columns → `freight_cost` / `duty_cost` / `handling_cost` |

---

## 5. Governance Objects

### 5.1 Tags (`GOVERNED` schema)

| Tag | Allowed values |
|-----|---------------|
| `ENTITY_TYPE` | SUPPLIER, PART, PLANT, INVENTORY, CUSTOMER, ORDER, ORDER_LINE, SHIPMENT, SOURCING |
| `SOURCE_SYSTEM` | ERP, WMS, TMS, SRM |
| `SENSITIVITY` | PUBLIC, INTERNAL, CONFIDENTIAL, RESTRICTED |
| `PII` | TRUE, FALSE |
| `METRIC_FAMILY` | DELIVERY, FULFILLMENT, INVENTORY, COST |

### 5.2 Masking policies

| Policy | Applied to | Visible to | Masked value |
|--------|-----------|-----------|--------------|
| `MASK_SUPPLIER_COST` | `V_PART.unit_cost`, `V_SOURCING.contract_price` | `FORGE_ADMIN`, `BUYER_ROLE` | `NULL` |
| `MASK_PAYMENT_TERMS` | `V_SUPPLIER.payment_terms` | `FORGE_ADMIN`, `BUYER_ROLE` | `'*** RESTRICTED ***'` |
| `MASK_CUSTOMER_PII` | `V_CUSTOMER.customer_name`, `V_CUSTOMER.email` | `FORGE_ADMIN`, `PLANNER_ROLE`, `LOGISTICS_ROLE` | `'*** MASKED ***'` |
| `MASK_CREDIT_LIMIT` | `V_CUSTOMER.credit_limit` | `FORGE_ADMIN` | `NULL` |

### 5.3 Row access policy

`RAP_PLANT_REGION` on `GOVERNED.V_PLANT`:
- `FORGE_ADMIN` → all rows
- `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE` → all rows (MVP)
- Demo-only extra role `LOGISTICS_APAC_ROLE` → `region = 'APAC'` only

> **Critical**: the row access policy must NOT reduce the shipment population used by
> metrics, or persona metric values will diverge. It is attached to `V_PLANT` for
> *detail* filtering, and the consistency tests assert aggregate equality.

### 5.4 Data Metric Functions

| DMF | Target | Purpose |
|-----|--------|---------|
| `SNOWFLAKE.CORE.NULL_COUNT` | `V_SHIPMENT.promised_delivery_date` | Promised date must always exist |
| `SNOWFLAKE.CORE.DUPLICATE_COUNT` | `V_ORDER_LINE.line_id` | PK integrity |
| `SNOWFLAKE.CORE.FRESHNESS` | `V_INVENTORY.snapshot_date` | Inventory recency |
| Custom `DMF_ORPHAN_ORDER_LINES` | `V_ORDER_LINE` | Referential integrity to orders |
| Custom `DMF_OVERSHIP_CHECK` | `V_ORDER_LINE` | `quantity_shipped <= quantity_ordered` |

---

## 6. Semantic View Specification

```sql
CREATE OR REPLACE SEMANTIC VIEW SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV

  TABLES (
    suppliers   AS GOVERNED.V_SUPPLIER    PRIMARY KEY (supplier_id)
                   WITH SYNONYMS ('vendor','source','supplier'),
    parts       AS GOVERNED.V_PART        PRIMARY KEY (part_id)
                   WITH SYNONYMS ('material','SKU','component','item'),
    sourcing    AS GOVERNED.V_SOURCING    PRIMARY KEY (source_id),
    plants      AS GOVERNED.V_PLANT       PRIMARY KEY (plant_id)
                   WITH SYNONYMS ('facility','site','warehouse','DC'),
    inventory   AS GOVERNED.V_INVENTORY   PRIMARY KEY (inventory_key),
    customers   AS GOVERNED.V_CUSTOMER    PRIMARY KEY (customer_id),
    orders      AS GOVERNED.V_ORDER       PRIMARY KEY (order_id),
    order_lines AS GOVERNED.V_ORDER_LINE  PRIMARY KEY (line_id),
    shipments   AS GOVERNED.V_SHIPMENT    PRIMARY KEY (shipment_id)
  )

  RELATIONSHIPS (
    sourcing_to_supplier   AS sourcing    (supplier_id) REFERENCES suppliers,
    sourcing_to_part       AS sourcing    (part_id)     REFERENCES parts,
    inventory_to_plant     AS inventory   (plant_id)    REFERENCES plants,
    inventory_to_part      AS inventory   (part_id)     REFERENCES parts,
    orders_to_customer     AS orders      (customer_id) REFERENCES customers,
    lines_to_order         AS order_lines (order_id)    REFERENCES orders,
    lines_to_part          AS order_lines (part_id)     REFERENCES parts,
    lines_to_plant         AS order_lines (plant_id)    REFERENCES plants,
    shipments_to_order     AS shipments   (order_id)    REFERENCES orders,
    shipments_to_plant     AS shipments   (plant_id)    REFERENCES plants
  )

  FACTS (
    shipments.is_on_time        AS IIF(actual_delivery_date <= promised_delivery_date, 1, 0),
    shipments.total_landed_cost AS freight_cost + duty_cost + handling_cost,
    order_lines.line_revenue    AS quantity_ordered * unit_price,
    inventory.available_qty     AS quantity_on_hand - quantity_reserved
  )

  DIMENSIONS (
    suppliers.supplier_name, suppliers.supplier_region, suppliers.supplier_tier,
    parts.part_name, parts.category, parts.subcategory, parts.is_critical,
    plants.plant_name, plants.plant_region, plants.plant_country, plants.plant_type,
    customers.customer_segment, customers.customer_region,
    orders.order_date, orders.order_month, orders.order_quarter, orders.order_year,
    orders.order_status, orders.order_priority,
    shipments.ship_date, shipments.carrier, shipments.shipment_status,
    inventory.snapshot_date
  )

  METRICS (
    -- 1. ON-TIME DELIVERY
    shipments.on_time_delivery_rate AS
      COUNT_IF(actual_delivery_date <= promised_delivery_date)
        / NULLIFZERO(COUNT_IF(actual_delivery_date IS NOT NULL))
      WITH SYNONYMS ('OTD','on time delivery','delivery performance','on-time %')
      COMMENT = 'Share of delivered shipments arriving on or before the TMS promised
                 delivery date. Excludes in-transit shipments. TMS PROM_DLV_DT is the
                 sole authoritative promised date.',

    -- 2. FILL RATE
    order_lines.fill_rate AS
      SUM(quantity_shipped) / NULLIFZERO(SUM(quantity_ordered))
      WITH SYNONYMS ('fill rate','order fulfillment rate','service level')
      COMMENT = 'Quantity shipped divided by quantity ordered, aggregated across order
                 lines. Partial shipments are pro-rated, not counted as total misses.',

    -- 3. DAYS OF INVENTORY
    inventory.days_of_inventory AS
      AVG(quantity_on_hand) / NULLIFZERO(AVG(daily_usage))
      WITH SYNONYMS ('DOI','days of inventory','inventory days','days of supply')
      COMMENT = 'Average on-hand quantity divided by average daily usage. Uses gross
                 on-hand, not net of reservations.',

    -- 4. LANDED COST
    shipments.avg_landed_cost AS
      AVG(freight_cost + duty_cost + handling_cost)
      WITH SYNONYMS ('landed cost','total delivered cost','all-in cost')
      COMMENT = 'Average total cost to move a shipment to destination: freight plus
                 duties plus handling.'
  )

  COMMENT = 'Governed supply chain ontology unifying ERP, WMS, TMS and SRM sources.'

  AI_SQL_GENERATION
    'Always use the predefined METRICS for on-time delivery, fill rate, days of
     inventory, and landed cost. Never recompute these from base columns. Never use
     ERP promised dates; only shipments.promised_delivery_date is authoritative.'

  AI_QUESTION_CATEGORIZATION
    'Answer questions about suppliers, parts, plants, inventory, orders, shipments,
     and customers. If a question is outside supply chain scope, say so. If a metric
     is requested without a time window, state the window you used.'

  AI_VERIFIED_QUERIES ( ... 8-10 pinned canonical questions ... );
```

### Verified queries to pin (minimum set)

| Name | Question |
|------|----------|
| `vq_otd_overall` | What is our overall on-time delivery rate? |
| `vq_otd_by_region` | What is on-time delivery rate by region? |
| `vq_otd_by_quarter` | What was on-time delivery rate by quarter? |
| `vq_fill_rate_overall` | What is our fill rate? |
| `vq_fill_rate_by_category` | What is fill rate by product category? |
| `vq_doi_by_plant` | What are days of inventory by plant? |
| `vq_landed_cost_by_region` | What is average landed cost by region? |
| `vq_worst_suppliers_otd` | Which suppliers have the worst on-time delivery? |

---

## 7. Cortex Agent Specification

```sql
CREATE OR REPLACE AGENT SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT
  COMMENT = 'Governed conversational analytics over the supply chain ontology'
  PROFILE = '{"display_name":"Supply Chain Forge","color":"blue"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  orchestration:
    budget:
      seconds: 45
      tokens: 16000
    tool_not_accessible: accept

  instructions:
    response: >
      Answer with the number first, then one sentence of context. Always state the
      time window used. Always name the metric definition applied. Never invent a
      metric formula.
    orchestration: >
      For any question about on-time delivery, fill rate, days of inventory, or
      landed cost, use the Analyst tool against SUPPLY_CHAIN_SV. If the question is
      ambiguous about time window or entity, ask one clarifying question. If the
      question is outside supply chain scope, decline briefly.
    sample_questions:
      - question: "What is our on-time delivery rate this quarter?"
      - question: "Which suppliers have the worst on-time delivery?"
      - question: "What is fill rate by product category?"
      - question: "What are days of inventory by plant?"

  tools:
    - tool_spec:
        type: cortex_analyst_text_to_sql
        name: SupplyChainAnalyst
        description: Governed text-to-SQL over the supply chain ontology
    - tool_spec:
        type: data_to_chart
        name: data_to_chart
        description: Visualize returned data

  tool_resources:
    SupplyChainAnalyst:
      semantic_view: SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
      warehouse: FORGE_WH
      query_timeout: 60
  $$;
```

**Invocation from Streamlit** (no REST, no PAT):
```sql
SELECT TRY_PARSE_JSON(
  SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT',
    OBJECT_CONSTRUCT('messages', ARRAY_CONSTRUCT(
      OBJECT_CONSTRUCT('role','user','content',
        ARRAY_CONSTRUCT(OBJECT_CONSTRUCT('type','text','text', ?)))))::VARCHAR,
    TRUE
  )
) AS response;
```

---

## 7a. MCP Server Specification

The Snowflake-managed MCP server exposes the governed ontology to any MCP client
(Claude Code during development; judges' tooling as a talking point).

```sql
-- Primary server: agent + analyst only. No raw SQL here by design.
CREATE OR REPLACE MCP SERVER SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_MCP
  FROM SPECIFICATION $$
  tools:
    - title: "Governed supply chain agent"
      name: "supply_chain_agent"
      type: "CORTEX_AGENT_RUN"
      identifier: "SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT"
      description: "Answers governed supply chain questions about on-time delivery,
                    fill rate, days of inventory, and landed cost across suppliers,
                    parts, plants, inventory, orders, shipments, and customers."

    - title: "Supply chain semantic view"
      name: "supply_chain_semantic_view"
      type: "CORTEX_ANALYST_MESSAGE"
      identifier: "SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV"
      description: "Generates governed SQL over the supply chain ontology."
  $$;
```

```sql
-- Separate server for read-only SQL introspection, least-privileged.
-- Snowflake explicitly warns against co-locating SYSTEM_EXECUTE_SQL with an agent
-- tool: a client could bypass the semantic view and verified queries entirely.
CREATE OR REPLACE MCP SERVER SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_MCP_RO
  FROM SPECIFICATION $$
  tools:
    - title: "Read-only SQL"
      name: "sql_readonly"
      type: "SYSTEM_EXECUTE_SQL"
      description: "Read-only SQL for schema introspection and verification."
      config:
        read_only: true
        query_timeout: 60
        warehouse: "FORGE_WH"
  $$;
```

**Operational notes**
- MCP hostnames must use **hyphens, not underscores** — underscores break the connection
- Prefer OAuth; if a PAT is used, bind it to a least-privileged role
- `USAGE` on the MCP server does **not** grant access to its tools; grant each separately
- Snowflake caps recursion at 10 invocations; avoid agent → MCP → agent loops

---

## 8. Build Order (strict — each step gated on the previous)

| Step | What | Gate before moving on |
|------|------|----------------------|
| **B1** | Database, 7 schemas, `FORGE_WH` | `SHOW SCHEMAS` returns 7 |
| **B2** | 4 roles + grants (incl. **default-role** grants for agent) | `SHOW GRANTS TO ROLE` verified per role |
| **B3** | 10 source tables across 4 source schemas | `SHOW TABLES` returns 10 |
| **B4** | Data generation, in FK order: suppliers → parts → sourcing → plants → customers → orders → lines → shipments → inventory | Row counts match §3 targets |
| **B5** | Raw metric sanity SQL (before any semantic layer) | OTD ≈ 0.87, fill ≈ 0.93, DOI 15–45 |
| **B6** | Tags + masking policies + row access policy | Each persona sees expected masked values |
| **B7** | 9 governed conformed views | `SELECT *` works for each, as each role |
| **B8** | Semantic view — **2 tables first** (shipments + orders), validate, then grow to 9 | `SELECT FROM SEMANTIC_VIEW(...)` returns each metric |
| **B9** | Add `AI_VERIFIED_QUERIES` + AI instructions | `DESCRIBE SEMANTIC VIEW` shows all VQRs |
| **B10** | Cortex Agent | `DATA_AGENT_RUN` returns a grounded answer |
| **B11** | Cross-persona consistency SQL check | All 4 metrics identical across 3 roles |
| **B12** | DMFs | `DATA_QUALITY_MONITORING_RESULTS` populated |
| **B13** | **Contract conformance audit** against `docs/CONTRACT.md` | Zero deviations, or all filed as Change Requests |
| **B14** | MCP server(s) per §7a | Tool discovery returns expected tools |
| **B15** | **Handoff** — update `HANDOFF.md` with FQNs + measured values | Claude Code unblocked for Track C6 |
| **B16** | Lineage trace, edge-case suite, multilingual test | Each produces a demo-ready artifact |
| **B17** | SQL + security review sweep | `sql-verify` clean; no over-broad grants |

> **B8 is the highest-risk step.** Semantic view validation rules are strict about
> fact/dimension/metric ordering and granularity. Build it with 2 tables, confirm a
> metric returns, then add tables incrementally. Do not write 9 entities blind.

> **B13 is the integration insurance.** Claude Code builds the whole app against
> `docs/CONTRACT.md` while this is in progress. If Snowflake reality drifts from the
> contract and nobody audits it, the two halves will not meet.

---

## 9. Cross-Persona Consistency Test Matrix

For each of 4 metrics × 3 roles = 12 assertions:

```sql
-- Run as each role, values must be identical
SELECT
  'on_time_delivery_rate' AS metric,
  ROUND(on_time_delivery_rate, 6) AS value
FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  METRICS shipments.on_time_delivery_rate
);
```

Pass criteria: `ROUND(value, 6)` identical across `PLANNER_ROLE`, `BUYER_ROLE`,
`LOGISTICS_ROLE`.

Additionally assert **divergence** where expected:
- `PLANNER_ROLE` sees `unit_cost IS NULL`
- `BUYER_ROLE` sees `customer_name = '*** MASKED ***'`
- `BUYER_ROLE` sees actual `unit_cost` values

---

## 10. File → Build Step Map

| File | Build step |
|------|-----------|
| `sql/01_setup/01_database.sql` | B1 |
| `sql/01_setup/02_roles_grants.sql` | B2 |
| `sql/02_tables/01_srm_source.sql` | B3 |
| `sql/02_tables/02_wms_source.sql` | B3 |
| `sql/02_tables/03_erp_source.sql` | B3 |
| `sql/02_tables/04_tms_source.sql` | B3 |
| `sql/03_sample_data/01_generate_masters.sql` | B4 |
| `sql/03_sample_data/02_generate_transactions.sql` | B4 |
| `sql/03_sample_data/03_verify_distributions.sql` | B5 |
| `sql/04_governance/01_tags.sql` | B6 |
| `sql/04_governance/02_masking_policies.sql` | B6 |
| `sql/04_governance/03_row_access_policies.sql` | B6 |
| `sql/04_governance/04_governed_views.sql` | B7 |
| `semantic/01_semantic_view.sql` | B8, B9 |
| `agent/01_agent.sql` | B10 |
| `sql/05_quality/01_dmfs.sql` | B12 |
| `tests/consistency/*` | B11, B15 |
| `app/*` | B14 |

> Note: existing per-entity placeholder files in `sql/02_tables/` will be consolidated
> into the four source-system files above.
