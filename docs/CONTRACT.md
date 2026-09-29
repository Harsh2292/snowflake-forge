# Interface Contract

> **FROZEN.** This file is the boundary between CoCo (Snowflake) and Claude Code (app).
>
> **Neither agent may change this file unilaterally.** If a change is genuinely
> required, write the proposal under `## Change Requests` at the bottom, tell the user,
> and wait. A silent change here breaks the other agent's work.
>
> CoCo implements the Snowflake side to match this exactly.
> Claude Code implements the app side to match this exactly.
>
> **Version**: 1.5 · **Frozen**: 2026-09-29 (v1.4: 2026-09-27)
>
> **v1.5 change** (accepted by the user 2026-09-29):
> - **CR-006**: realistic data v2. It adds the new §3 definition strings with edge-case rules
>   and a **§3a time rule** (trailing 12 months; DOI uses the latest snapshot), applied in §5
>   and §8. It also:
>   - updates the §1 FQNs: MCP removed; `SP_DATA_HEALTH`, name search, view generator,
>     `CONFORMED`, `OPS` and the `SEMANTIC_ROLE` tag added
>   - puts the §7 views on `CONFORMED` (names and columns unchanged)
>   - moves to 10 source tables and adds `orders.order_year_quarter`
>
>   The §10 values get re-captured at B09. Detail: `docs/DATA_SPEC.md`.
>
> **v1.4 change**:
> - **CR-005**: `fill_rate` counts only order lines on shipped or delivered orders; open
>   and cancelled orders are excluded (§3). Value, range and mocks are unchanged.
>
> **v1.3 change**:
> - **CR-004**: Appended `CONTRACT_PRICE` and `CUSTOMER_EMAIL` to `SP_SAMPLE_AS_*` procedure return shapes in §5.4, covering all 6 masked columns from §6.
>
> **v1.2 changes**:
> - **CR-002**: Added `GOVERNED.SP_METRICS_AS_{PLANNER,BUYER,LOGISTICS}()` persona metric procedures so consistency proof is computed per role.
> - **CR-003**: Reworded Question 8 to "Which plants have the worst on-time delivery?" (Option B) to match valid metric × dimension pairings (`shipments.on_time_delivery_rate` × `plants.plant_name`).
>
> **v1.1 change**: persona divergence is obtained by calling three owner's-rights stored
> procedures, **not** by `USE ROLE`. See §6a. Reason: Streamlit in Snowflake runs with
> owner's rights, so `CURRENT_ROLE()` inside the app always returns the app owner —
> a `USE ROLE` approach would silently produce identical output for all personas.
> Full analysis in `docs/GAPS_RESOLVED.md` GAP-1.

---

## 1. Fully Qualified Names

| Object | FQN |
|--------|-----|
| Database | `SUPPLY_CHAIN_FORGE` |
| Semantic view | `SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV` |
| Cortex Agent | `SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT` |
| Streamlit app | `SUPPLY_CHAIN_FORGE.APP.FORGE_DEMO` |
| Warehouse | `FORGE_WH` |
| Persona proc — Planner | `SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_PLANNER()` |
| Persona proc — Buyer | `SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_BUYER()` |
| Persona proc — Logistics | `SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_LOGISTICS()` |
| Persona metric proc — Planner | `SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_PLANNER()` |
| Persona metric proc — Buyer | `SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_BUYER()` |
| Persona metric proc — Logistics | `SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_LOGISTICS()` |
| Data-health procedure (agent tool; CR-006) | `SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH(ENTITY VARCHAR) RETURNS VARIANT` (shape: DATA_SPEC §7.2) |
| Name search service (CR-006) | `SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_NAME_SEARCH` (supplier, part, plant and carrier names only; no masked column) |
| View generator (CR-006) | `SUPPLY_CHAIN_FORGE.SEMANTIC.SP_BUILD_SEMANTIC_VIEW(APPLY BOOLEAN)` + its registry tables in `SEMANTIC` |
| Cleansing layer (CR-006) | schema `SUPPLY_CHAIN_FORGE.CONFORMED` (dynamic tables; not readable by persona roles) |
| Operations (CR-006) | schema `SUPPLY_CHAIN_FORGE.OPS` (generator, evaluation set and results, scale results; `FORGE_ADMIN` only) |
| Column-role tag (CR-006) | `SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE` (`KEY` / `DIMENSION` / `FACT` / `EXCLUDE`) |

The MCP server was removed in v1.5 (ADR-008).

---

## 2. Persona Roles

```python
PERSONA_ROLES = {
    "Planner":   "PLANNER_ROLE",
    "Buyer":     "BUYER_ROLE",
    "Logistics": "LOGISTICS_ROLE",
}
```

Display labels used in the UI:

| Key | UI label | Represents |
|-----|----------|-----------|
| `Planner` | Production Planner | Plans production and inventory |
| `Buyer` | Procurement Lead | Manages suppliers and cost |
| `Logistics` | Logistics Coordinator | Manages shipments and delivery |

---

## 3. Canonical Metrics

These are the **exact identifiers** to use in `SEMANTIC_VIEW(...)` queries.

| # | Metric identifier | UI label | Format | Expected range |
|---|------------------|----------|--------|---------------|
| 1 | `shipments.on_time_delivery_rate` | On-Time Delivery | percent, 1 dp | 0.84 – 0.90 |
| 2 | `order_lines.fill_rate` | Fill Rate | percent, 1 dp | 0.90 – 0.95 |
| 3 | `inventory.days_of_inventory` | Days of Inventory | number, 1 dp | 15 – 45 |
| 4 | `shipments.avg_landed_cost` | Avg Landed Cost | currency USD, 2 dp | 150 – 900 |

```python
METRICS = {
    "on_time_delivery_rate": {
        "id": "shipments.on_time_delivery_rate",
        "label": "On-Time Delivery",
        "format": "percent",
        "definition": "Share of delivered shipments arriving on or before the TMS "
                      "promised delivery date. Excludes in-transit shipments and "
                      "shipments with no promised date. Without a stated period, "
                      "covers shipments shipped in the last 12 months.",
    },
    "fill_rate": {
        "id": "order_lines.fill_rate",
        "label": "Fill Rate",
        "format": "percent",
        "definition": "Quantity shipped divided by quantity ordered across order "
                      "lines on shipped or delivered orders. Open and cancelled "
                      "orders are excluded. Partial shipments are pro-rated; "
                      "over-shipments count as fully shipped. Without a stated "
                      "period, covers orders placed in the last 12 months.",
    },
    "days_of_inventory": {
        "id": "inventory.days_of_inventory",
        "label": "Days of Inventory",
        "format": "number",
        "definition": "Average on-hand quantity divided by average daily usage. "
                      "Uses gross on-hand, not net of reservations; negative "
                      "on-hand counts as zero. Without a stated period, uses the "
                      "latest inventory snapshot.",
    },
    "avg_landed_cost": {
        "id": "shipments.avg_landed_cost",
        "label": "Avg Landed Cost",
        "format": "currency",
        "definition": "Average total cost to move a shipment to destination, in "
                      "USD: freight plus duties plus handling. Missing duty or "
                      "handling counts as zero; shipments with unknown or "
                      "implausible cost are excluded. Without a stated period, "
                      "covers shipments shipped in the last 12 months.",
    },
}
```

---

## 3a. Time Rule (CR-006)

One rule for the app, the procedures and the agent.

| Rule | Definition |
|---|---|
| Anchor | `CURRENT_DATE()` at query time |
| Default window (no period named) | trailing 12 months: `date > DATEADD(month, -12, CURRENT_DATE()) AND date <= CURRENT_DATE()`, on `shipments.ship_date` for OTD and landed cost, on `orders.order_date` for fill rate |
| DOI | the latest snapshot: `inventory.snapshot_date = (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY)`; with a period named, the average over the snapshots in it |
| As-of date (shown next to every metric) | the latest shipment `ship_date` loaded, from `SP_DATA_HEALTH` (`as_of_date`) |
| Explicit period | replaces the default; the answer states the period |

---

## 4. Dimensions

Exact identifiers usable in the `DIMENSIONS` clause.

| Entity | Dimension identifiers |
|--------|----------------------|
| suppliers | `suppliers.supplier_name`, `suppliers.supplier_region`, `suppliers.supplier_tier` |
| parts | `parts.part_name`, `parts.category`, `parts.subcategory`, `parts.is_critical` |
| plants | `plants.plant_name`, `plants.plant_region`, `plants.plant_country`, `plants.plant_type` |
| customers | `customers.customer_segment`, `customers.customer_region` |
| orders | `orders.order_date`, `orders.order_month`, `orders.order_quarter`, `orders.order_year`, `orders.order_year_quarter` (e.g. `2026-Q3`; added at B09, CR-006), `orders.order_status`, `orders.order_priority` |
| shipments | `shipments.ship_date`, `shipments.carrier`, `shipments.shipment_status` |
| inventory | `inventory.snapshot_date` |

### Valid dimension values

| Dimension | Values |
|-----------|--------|
| `*_region` | `APAC`, `EMEA`, `AMER` |
| `plants.plant_type` | `MFG`, `DC`, `HUB` |
| `suppliers.supplier_tier` | `1`, `2`, `3` |
| `customers.customer_segment` | `ENTERPRISE`, `MIDMARKET`, `SMB` |
| `orders.order_status` | `OPEN`, `SHIPPED`, `DELIVERED`, `CANCELLED` |
| `orders.order_priority` | `HIGH`, `NORMAL`, `LOW` |
| `shipments.shipment_status` | `IN_TRANSIT`, `DELIVERED`, `DELAYED` |
| `orders.order_quarter` | `Q1`, `Q2`, `Q3`, `Q4` |
| `parts.category` | `ELECTRONICS`, `MECHANICAL`, `RAW_MATERIAL`, `PACKAGING`, `CHEMICAL`, `FASTENERS` |

### Valid metric × dimension pairings

Not every metric works with every dimension (semantic view granularity rules).
These pairings are guaranteed to work:

| Metric | Valid dimensions |
|--------|-----------------|
| `on_time_delivery_rate` | `plants.*`, `orders.*`, `shipments.*`, `customers.*` |
| `fill_rate` | `parts.*`, `plants.*`, `orders.*`, `customers.*` |
| `days_of_inventory` | `plants.*`, `parts.*`, `inventory.snapshot_date` |
| `avg_landed_cost` | `plants.*`, `orders.*`, `shipments.*`, `customers.*` |

> `days_of_inventory` is **not** valid with `orders.*` or `shipments.*` — inventory has
> no relationship path to those entities. Do not attempt it.

---

## 5. Query Patterns

Every metric query applies the §3a time rule (CR-006). Output column names are unchanged.

### 5.1 Metric only

```sql
SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  METRICS shipments.on_time_delivery_rate
  WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
    AND shipments.ship_date <= CURRENT_DATE()
);
```
Returns: one row, one column `ON_TIME_DELIVERY_RATE`.

The `WHERE` depends on the metric:

| Metric | Default `WHERE` |
|---|---|
| `on_time_delivery_rate`, `avg_landed_cost` | the window on `shipments.ship_date` (as above) |
| `fill_rate` | `orders.order_date > DATEADD(month, -12, CURRENT_DATE()) AND orders.order_date <= CURRENT_DATE()` |
| `days_of_inventory` | `inventory.snapshot_date = (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY)` |

Metrics with different default windows go in separate `SEMANTIC_VIEW` calls. One `WHERE`
can't apply both a ship-date window and an order-date window.

### 5.2 Metric by dimension

```sql
SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  DIMENSIONS plants.plant_region
  METRICS shipments.on_time_delivery_rate
  WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
    AND shipments.ship_date <= CURRENT_DATE()
) ORDER BY plant_region;
```
Returns: one row per region. Columns `PLANT_REGION`, `ON_TIME_DELIVERY_RATE`.

> Output column headers are the **unqualified** names, uppercased.
> `plants.plant_region` → column `PLANT_REGION`.

### 5.3 Agent invocation

```sql
SELECT TRY_PARSE_JSON(
  SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT',
    OBJECT_CONSTRUCT('messages', ARRAY_CONSTRUCT(
      OBJECT_CONSTRUCT('role', 'user', 'content',
        ARRAY_CONSTRUCT(OBJECT_CONSTRUCT('type', 'text', 'text', ?)))))::VARCHAR,
    TRUE
  )
) AS response;
```

### 5.4 Persona sample data & metric procedures — call a procedure, do NOT use `USE ROLE`

```sql
-- Sample data procedures (divergence proof in Tab 2)
CALL SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_PLANNER();
CALL SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_BUYER();
CALL SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_LOGISTICS();

-- Metric procedures (consistency proof in Tab 2 — CR-002)
CALL SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_PLANNER();
CALL SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_BUYER();
CALL SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_LOGISTICS();
```

Each procedure is owned by its corresponding persona role and runs `EXECUTE AS OWNER`,
so real masking policies and role contexts apply. The app calls all six as the app owner.

**`USE ROLE` does not work inside Streamlit in Snowflake.** SiS runs with owner's rights;
`CURRENT_ROLE()` always returns the app owner. See §6a.

**Sample data procedures** return a single result set with this shape:

| Column | Type | Notes |
|--------|------|-------|
| `PERSONA` | VARCHAR | `PLANNER` / `BUYER` / `LOGISTICS` |
| `SAMPLE_PART_ID` | VARCHAR | |
| `UNIT_COST` | NUMBER | `NULL` when masked |
| `SAMPLE_SUPPLIER_ID` | VARCHAR | |
| `PAYMENT_TERMS` | VARCHAR | `*** RESTRICTED ***` when masked |
| `SAMPLE_CUSTOMER_ID` | VARCHAR | |
| `CUSTOMER_NAME` | VARCHAR | `*** MASKED ***` when masked |
| `CREDIT_LIMIT` | NUMBER | always `NULL` except `FORGE_ADMIN` |
| `CONTRACT_PRICE` | NUMBER | from `V_SOURCING` for `SAMPLE_PART_ID`; `NULL` when masked |
| `CUSTOMER_EMAIL` | VARCHAR | from `V_CUSTOMER.email` for `SAMPLE_CUSTOMER_ID`; `*** MASKED ***` when masked |

**Metric procedures (CR-002)** return a single row with this shape. From v1.5 each metric
is computed under the §3a time rule (CR-006); the shape and columns are unchanged.

| Column | Type | Notes |
|--------|------|-------|
| `PERSONA` | VARCHAR | `PLANNER` / `BUYER` / `LOGISTICS` |
| `ON_TIME_DELIVERY_RATE` | NUMBER | Identical across all 3 personas |
| `FILL_RATE` | NUMBER | Identical across all 3 personas |
| `DAYS_OF_INVENTORY` | NUMBER | Identical across all 3 personas |
| `AVG_LANDED_COST` | NUMBER | Identical across all 3 personas |

---

## 6. Masking Matrix (drives the divergence proof)

| Column | `PLANNER_ROLE` | `BUYER_ROLE` | `LOGISTICS_ROLE` |
|--------|---------------|-------------|-----------------|
| `V_PART.unit_cost` | `NULL` | visible | `NULL` |
| `V_SOURCING.contract_price` | `NULL` | visible | `NULL` |
| `V_SUPPLIER.payment_terms` | `*** RESTRICTED ***` | visible | `*** RESTRICTED ***` |
| `V_CUSTOMER.customer_name` | visible | `*** MASKED ***` | visible |
| `V_CUSTOMER.email` | visible | `*** MASKED ***` | visible |
| `V_CUSTOMER.credit_limit` | `NULL` | `NULL` | `NULL` |

**Invariant that must hold**: masking changes *column visibility only*. All four
canonical metric values are **identical** across all three roles to 6 decimal places.

This is structural, not coincidental: **no canonical metric references a masked column.**

| Metric | Columns used | Any masked? |
|--------|-------------|------------|
| `on_time_delivery_rate` | `actual_delivery_date`, `promised_delivery_date` | No |
| `fill_rate` | `quantity_shipped`, `quantity_ordered` | No |
| `days_of_inventory` | `quantity_on_hand`, `daily_usage` | No |
| `avg_landed_cost` | `freight_cost`, `duty_cost`, `handling_cost` | No |

Masked columns (`unit_cost`, `contract_price`, `payment_terms`, `customer_name`,
`email`, `credit_limit`) appear in **no** metric formula. That is why the numbers can be
identical while visibility differs.

---

## 6a. Why Persona Divergence Uses Procedures, Not `USE ROLE`

Streamlit in Snowflake runs with **owner's rights**. Per Snowflake documentation:

> "Streamlit in Snowflake apps run with owner's rights, so using `CURRENT_ROLE` inside a
> Streamlit app always returns the app owner role."

Our masking policies key off `CURRENT_ROLE()`. Therefore:

- A persona dropdown driving `USE ROLE` would have **no effect** on masking
- All three personas would return identical unmasked output
- The app would *appear* to work while proving nothing

**The mechanism instead**:

```
PLANNER_ROLE    owns  GOVERNED.SP_SAMPLE_AS_PLANNER()     EXECUTE AS OWNER
BUYER_ROLE      owns  GOVERNED.SP_SAMPLE_AS_BUYER()       EXECUTE AS OWNER
LOGISTICS_ROLE  owns  GOVERNED.SP_SAMPLE_AS_LOGISTICS()   EXECUTE AS OWNER
```

Each procedure executes with **its owner's** rights, so `CURRENT_ROLE()` inside resolves
to that persona role and the genuine masking policy applies. The app calls all three from
one session, as the app owner, with only `USAGE` on each procedure.

The masking policies themselves are unchanged — real, role-based, production-grade.

### Division of labour

| Claim | Mechanism | Per-role execution needed? |
|-------|-----------|---------------------------|
| Metrics identical across personas | The three `SP_METRICS_AS_*` procedures above | Yes — proves identical under each persona role |
| Visibility differs across personas | The three `SP_SAMPLE_AS_*` procedures above | Yes — proves masking policies apply |

---

## 7. Governed View Column Names

Claude Code may query these directly for the divergence proof.

From v1.5 (CR-006) the view names, columns and column order are **unchanged**, but the views
read the `CONFORMED` layer instead of the source schemas:
- rows are unique and in scope (no test records, returns or orphans)
- values are standardized to the §4 values
- every amount is in USD
- `V_SOURCING` shows only the sourcing rows valid today

| View | Columns |
|------|---------|
| `GOVERNED.V_SUPPLIER` | `supplier_id`, `supplier_name`, `country`, `region`, `supplier_tier`, `lead_time_days`, `reliability_score`, `payment_terms`, `email` |
| `GOVERNED.V_PART` | `part_id`, `part_name`, `category`, `subcategory`, `unit_cost`, `weight_kg`, `is_critical` |
| `GOVERNED.V_SOURCING` | `source_id`, `supplier_id`, `part_id`, `is_primary`, `contract_price` |
| `GOVERNED.V_PLANT` | `plant_id`, `plant_name`, `country`, `region`, `plant_type`, `capacity_units` |
| `GOVERNED.V_INVENTORY` | `inventory_key`, `plant_id`, `part_id`, `quantity_on_hand`, `quantity_reserved`, `reorder_point`, `daily_usage`, `snapshot_date` |
| `GOVERNED.V_CUSTOMER` | `customer_id`, `customer_name`, `email`, `country`, `region`, `customer_segment`, `credit_limit` |
| `GOVERNED.V_ORDER` | `order_id`, `customer_id`, `order_date`, `order_status`, `order_priority` |
| `GOVERNED.V_ORDER_LINE` | `line_id`, `order_id`, `part_id`, `plant_id`, `quantity_ordered`, `quantity_shipped`, `unit_price` |
| `GOVERNED.V_SHIPMENT` | `shipment_id`, `order_id`, `plant_id`, `carrier`, `ship_date`, `promised_delivery_date`, `actual_delivery_date`, `freight_cost`, `duty_cost`, `handling_cost`, `shipment_status` |

---

## 8. The Divergence Demo (Tab 3)

Claude Code builds this. The two queries below are **contract-guaranteed** to return
different numbers, which is the demo's opening hook.

**Naive — ERP promised date (wrong):**
```sql
SELECT COUNT_IF(s.ACT_DLV_DT <= o.ERDAT) / NULLIFZERO(COUNT_IF(s.ACT_DLV_DT IS NOT NULL))
FROM SUPPLY_CHAIN_FORGE.TMS_SOURCE.VTTK s
JOIN SUPPLY_CHAIN_FORGE.ERP_SOURCE.VBAK o ON s.VBELN = o.VBELN
WHERE s.DPTBG > DATEADD(month, -12, CURRENT_DATE()) AND s.DPTBG <= CURRENT_DATE();
```

**Governed — semantic view metric (authoritative):**
```sql
SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  METRICS shipments.on_time_delivery_rate
  WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
    AND shipments.ship_date <= CURRENT_DATE()
);
```

Both queries use the same 12-month window (§3a), so they cover the same shipments. The naive
query still reads raw source data with the ERP date, which is the point of the demo.
Expected: naive ~0.68–0.74, governed ~0.87, at least 8 points apart (DATA_SPEC §5.4).
Source tables: 10 from v1.5 (`ERP_SOURCE.TCURR` added; columns per DATA_SPEC §1). Only this
naive query reads them.

These are the **only** circumstances under which Claude Code may query source schemas
directly. Everywhere else, go through the semantic view or governed views.

---

## 9. Canonical Questions (pinned as verified queries)

Claude Code uses these as the app's suggested-question chips.

| # | Question |
|---|----------|
| 1 | What is our overall on-time delivery rate? |
| 2 | What is on-time delivery rate by region? |
| 3 | What was on-time delivery rate by quarter? |
| 4 | What is our fill rate? |
| 5 | What is fill rate by product category? |
| 6 | What are days of inventory by plant? |
| 7 | What is average landed cost by region? |
| 8 | Which plants have the worst on-time delivery? |

---

## 10. Mock Mode

Until CoCo signals readiness in `.agents/HANDOFF.md`, Claude Code builds against mocks.

```python
# app/utils/config.py
USE_MOCK_DATA = True   # flip to False when HANDOFF.md shows all items DONE
```

Mock values must sit inside the ranges in §3 so the UI looks correct while offline.
Under CR-006 the practice values below are replaced by the values in the re-captured art 05
(B09), within v1.5:

```python
MOCK_METRICS = {
    "on_time_delivery_rate": 0.8714,
    "fill_rate": 0.9283,
    "days_of_inventory": 28.4,
    "avg_landed_cost": 412.67,
}

MOCK_BY_REGION = {
    "APAC": {"on_time_delivery_rate": 0.8521, "fill_rate": 0.9147,
             "days_of_inventory": 31.2, "avg_landed_cost": 487.20},
    "EMEA": {"on_time_delivery_rate": 0.8893, "fill_rate": 0.9361,
             "days_of_inventory": 26.8, "avg_landed_cost": 398.45},
    "AMER": {"on_time_delivery_rate": 0.8742, "fill_rate": 0.9329,
             "days_of_inventory": 27.1, "avg_landed_cost": 362.10},
}
```

The mock layer stays in the codebase after go-live — it becomes the test fixture and
lets the demo run even if the network drops on stage.

---

## 11. Change Requests

### CR-001 — Persona divergence via stored procedures, not `USE ROLE`
**Requested by**: CoCo
**Raised**: 2026-09-24, before Claude Code began work
**Status**: **ACCEPTED** — folded into v1.1

**Reason**: Streamlit in Snowflake runs with owner's rights. `CURRENT_ROLE()` inside a SiS
app always returns the app owner, so the v1.0 `USE ROLE` approach would have had zero
effect on masking. All three personas would have returned identical unmasked output while
the app appeared to function — a silent failure of the project's central claim.

**Change**:
- §5.4 replaced: call `SP_SAMPLE_AS_{PLANNER,BUYER,LOGISTICS}()` instead of `USE ROLE`
- §6a added: full rationale and the ownership mechanism
- §1 extended with the three procedure FQNs
- §6 extended with proof that no metric references a masked column

**Impact on CoCo**: new build step B7b — create three procedures, transfer ownership to
the respective persona roles, grant `USAGE` to the app owner.

**Impact on Claude Code**: none yet — raised before work began. `forge_data.py` calls
procedures rather than issuing `USE ROLE`.

---

### CR-002 — Persona metric procedures, so the consistency proof is computed per role
**Requested by**: Claude Code
**Raised**: 2026-09-24, during C02
**Status**: **ACCEPTED** (2026-09-24) — folded into v1.2

**Reason**: Under v1.1 (§6a "Division of labour"), metrics are queried once, as the app
owner. The Consistency Proof tab's 4 metrics × 3 personas grid would then show one number
copied three times. A judge who looks closely sees that it proves nothing. The claim
"same answer for every persona" needs values that were actually computed under each role.

**Proposed change**:
- §1: add `SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_{PLANNER,BUYER,LOGISTICS}()`.
- §5.4: add alongside the sample procedures. Each is owned by its persona role,
  `EXECUTE AS OWNER`, and runs the four canonical metrics through `SEMANTIC_VIEW` (§5.1).
  It returns **one row**:

  | Column | Type |
  |--------|------|
  | `PERSONA` | VARCHAR: `PLANNER` / `BUYER` / `LOGISTICS` |
  | `ON_TIME_DELIVERY_RATE` | NUMBER |
  | `FILL_RATE` | NUMBER |
  | `DAYS_OF_INVENTORY` | NUMBER |
  | `AVG_LANDED_COST` | NUMBER |

- §6a "Division of labour": the "Metrics identical" row becomes "the three
  `SP_METRICS_AS_*` procedures, per-role execution: yes".

**Impact on CoCo**: three small procedures, built the same way as the B7b sample
procedures. Persona roles need `SELECT` on `SUPPLY_CHAIN_SV` (and `USAGE` on `FORGE_WH` if
not inherited). Fits naturally in B7b or B11. B11's artifact `09_consistency_proof.json`
can be captured by calling these.

**Impact on Claude Code**: already built. `forge_data.compare_across_personas()` calls
these procedures in live mode. Until they exist, live mode falls back to mock with a
visible notice.

---

### CR-003 — Canonical question 8 has no valid metric × dimension pairing
**Requested by**: Claude Code
**Raised**: 2026-09-24, during C02
**Status**: **ACCEPTED** (2026-09-24) — Option B adopted, folded into v1.2

**Reason**: §9 question 8, "Which suppliers have the worst on-time delivery?", needs
`on_time_delivery_rate` × `suppliers.*`. §4 does not list that pairing, and it can't work
as modelled: `shipments` has no relationship path to `suppliers`. Parts link to suppliers
through M:N `sourcing`, not through shipments or order lines. The pinned verified query
`vq_worst_suppliers_otd` (LLD §6) would fail the granularity rule (error `010234`).

**Adopted change (Option B)**:
- Reworded Q8 in §9 to "Which plants have the worst on-time delivery?" (`shipments.on_time_delivery_rate` × `plants.plant_name`, which is a valid pairing under §4).
- Rename corresponding verified query in B09 to `vq_worst_plants_otd`.

**Impact on CoCo**: Verified query in B09 targets plant delivery rather than supplier.

**Impact on Claude Code**: Suggestion chip for Q8 updated to "Which plants have the worst on-time delivery?".

---

### CR-004 — Sample procedures should return all six masked columns
**Requested by**: Claude Code
**Raised**: 2026-09-25, during C04 (user approved raising it)
**Status**: **ACCEPTED** (2026-09-25) — folded into v1.3

**Reason**: §6 lists **six** masked columns, but the §5.4 sample procedures return only
**four** of them (`UNIT_COST`, `PAYMENT_TERMS`, `CUSTOMER_NAME`, `CREDIT_LIMIT`).
`V_SOURCING.contract_price` and `V_CUSTOMER.email` are never returned under a persona
role, so nothing can prove their masking per persona. The app runs as its owner, so it
can't check them any other way (§6a).

**Proposed change**: §5.4 sample-procedure result shape gains two columns, appended at the
end so the existing order is unchanged:

| Column | Type | Notes |
|--------|------|-------|
| `CONTRACT_PRICE` | NUMBER | from `V_SOURCING` for `SAMPLE_PART_ID`; `NULL` when masked |
| `CUSTOMER_EMAIL` | VARCHAR | from `V_CUSTOMER.email` for `SAMPLE_CUSTOMER_ID`; `*** MASKED ***` when masked |

**Impact on CoCo**: two extra columns in each `SP_SAMPLE_AS_*` procedure at B07b. The
procedures aren't built yet, so there's no rework. Artifact `04_persona_outputs.json`
then shows all six.

**Impact on Claude Code**: `tests/governance/test_masking.py` already has the two checks;
they're enabled with mock sample updated.

---

### CR-005 — Fill rate: define the line population (exclude OPEN and CANCELLED orders)
**Requested by**: CoCo
**Raised**: 2026-09-27, during B07 gate
**Status**: **ACCEPTED** (2026-09-27, by the user) — folded into v1.4

**Reason**: B07's gate computed the four metrics from the governed views under all three
persona roles. They are identical across roles (6 dp), as §6 requires. But fill rate as
§3 literally defines it ("quantity shipped divided by quantity ordered across order
lines") is **0.787449** over all 2,400 lines, which is **outside the §3 range 0.90–0.95**.

Measured on the live data (`V_ORDER_LINE` joined to `V_ORDER`):

| Order status | Lines | Ordered | Shipped | Fill rate |
|---|---|---|---|---|
| DELIVERED | 1,680 | 183,840 | 170,325 | 0.926485 |
| SHIPPED | 360 | 39,420 | 36,522 | 0.926484 |
| OPEN | 240 | 26,340 | 0 | 0 |
| CANCELLED | 120 | 13,080 | 0 | 0 |
| **All lines** | 2,400 | 262,680 | 206,847 | **0.787449** |
| **SHIPPED + DELIVERED** | 2,040 | 223,260 | 206,847 | **0.926485** |

Open orders haven't been due to ship yet, and cancelled orders are no longer an obligation
to fulfil, so counting them as unfilled understates performance. Artifact
`02_raw_metrics.md` (0.9265) and `MOCK_METRICS` (0.9283) already assume this exclusion
without saying so.

**Proposed change**:
- §3 `fill_rate` definition becomes: *"Quantity shipped divided by quantity ordered across
  order lines on shipped or delivered orders. Open and cancelled orders are excluded.
  Partial shipments are pro-rated."*
- The §3 range (0.90–0.95) is unchanged; the live value is 0.926485.
- §6 invariant unaffected: `order_status` is not masked.

**Impact on CoCo**: at B08, `order_lines.fill_rate` gets the filter through the
`order_lines → orders` relationship, e.g. `SUM(IFF(orders.order_status IN ('SHIPPED',
'DELIVERED'), quantity_shipped, 0)) / NULLIFZERO(SUM(IFF(orders.order_status IN
('SHIPPED','DELIVERED'), quantity_ordered, 0)))`. No change to B07's views.

**Impact on Claude Code**: `app/utils/config.py` copies the §3 definition text verbatim,
so that string changes. Values, ranges and tests don't change.

**Related, no CR needed**: `days_of_inventory` computed as §3 defines it (average on-hand
÷ average daily usage) is **28.499215**. `02_raw_metrics.md` shows 28.51 because B05
averaged the per-row ratios (28.511778). The §3 definition stands, and B08 implements it
as written.

---

### CR-006 — Realistic data v2: edge-case metric rules, one time rule, new objects, MCP removed
**Requested by**: CoCo (B08b, 2026-09-29)
**Status**: **ACCEPTED** by the user, 2026-09-29. Applied in the body as **v1.5**: header,
§1, §3, §3a, §4, §5, §7, §8, §10. The §10 practice values are filled in at B09 within v1.5,
as agreed with Claude Code (HANDOFF Q2).
**Detail**: `docs/DATA_SPEC.md` (the mess catalogue §4, the rules §5, the interfaces §7).

**Reason**: ADR-008 replaces the small clean v1 data with 10 years of realistic, messy data
(duplicates, code variants, currencies, test records, edge cases), cleaned once in a new
`CONFORMED` layer. With 10 years of data, "What is our OTD?" needs one defined period, or
the app and the agent can return two different numbers for the same question. The edge
cases also need exact metric rules. The MCP server was dropped (ADR-008).

**Proposed change**:

1. **§3 definitions** (identifiers, labels, formats and **ranges unchanged**). The new
   `definition` strings, verbatim:
   - `on_time_delivery_rate`: *"Share of delivered shipments arriving on or before the TMS
     promised delivery date. Excludes in-transit shipments and shipments with no promised
     date. Without a stated period, covers shipments shipped in the last 12 months."*
   - `fill_rate`: *"Quantity shipped divided by quantity ordered across order lines on
     shipped or delivered orders. Open and cancelled orders are excluded. Partial shipments
     are pro-rated; over-shipments count as fully shipped. Without a stated period, covers
     orders placed in the last 12 months."*
   - `days_of_inventory`: *"Average on-hand quantity divided by average daily usage. Uses
     gross on-hand, not net of reservations; negative on-hand counts as zero. Without a
     stated period, uses the latest inventory snapshot."*
   - `avg_landed_cost`: *"Average total cost to move a shipment to destination, in USD:
     freight plus duties plus handling. Missing duty or handling counts as zero; shipments
     with unknown or implausible cost are excluded. Without a stated period, covers
     shipments shipped in the last 12 months."*

2. **New §3a Time rule** (one rule for the app, the procedures and the agent):

   | Rule | Definition |
   |---|---|
   | Anchor | `CURRENT_DATE()` at query time |
   | Default window (no period named) | trailing 12 months: `date > DATEADD(month, -12, CURRENT_DATE()) AND date <= CURRENT_DATE()`, on `shipments.ship_date` for OTD and landed cost, on `orders.order_date` for fill rate |
   | DOI | the latest snapshot: `inventory.snapshot_date = (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY)`; with a period named, the average over the snapshots in it |
   | As-of date (shown next to every metric) | the latest shipment `ship_date` loaded, from `SP_DATA_HEALTH` (`as_of_date`) |
   | Explicit period | replaces the default; the answer states the period |

3. **§5.1 / §5.2 patterns** gain the §3a `WHERE` clause (verified live on the v1 view). The
   output column names are unchanged. Example:

   ```sql
   SELECT * FROM SEMANTIC_VIEW(
     SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
     DIMENSIONS plants.plant_region
     METRICS shipments.on_time_delivery_rate
     WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
       AND shipments.ship_date <= CURRENT_DATE()
   ) ORDER BY plant_region;
   ```

   `SP_METRICS_AS_*` (§5.4) return the 4 metrics **under §3a** (same shape, same columns).

4. **§1 FQNs**:
   - remove the MCP server row
   - add:

   | Object | FQN |
   |---|---|
   | Data-health procedure (agent tool) | `SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH(ENTITY VARCHAR) RETURNS VARIANT` (shape: DATA_SPEC §7.2) |
   | Name search service | `SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_NAME_SEARCH` (supplier, part, plant and carrier names only; no masked column) |
   | View generator | `SUPPLY_CHAIN_FORGE.SEMANTIC.SP_BUILD_SEMANTIC_VIEW(APPLY BOOLEAN)` + its registry tables in `SEMANTIC` |
   | Cleansing layer | schema `SUPPLY_CHAIN_FORGE.CONFORMED` (dynamic tables; not readable by persona roles) |
   | Operations | schema `SUPPLY_CHAIN_FORGE.OPS` (generator, evaluation set and results, scale results; `FORGE_ADMIN` only) |
   | Column-role tag | `SUPPLY_CHAIN_FORGE.GOVERNED.SEMANTIC_ROLE` (`KEY` / `DIMENSION` / `FACT` / `EXCLUDE`) |

5. **§7**: view names, columns and order are **unchanged**. Behind them:
   - the views read `CONFORMED` instead of the source schemas
   - rows are unique, in scope (no test records, returns, orphans) and standardized to
     the §4 values
   - every amount is in USD
   - `V_SOURCING` shows only the sourcing rows valid today.

6. **§8**: the naive query gets the same window, so both numbers cover the same shipments.
   It still reads raw `SOURCE` with the ERP date, which is the point of the demo:

   ```sql
   SELECT COUNT_IF(s.ACT_DLV_DT <= o.ERDAT) / NULLIFZERO(COUNT_IF(s.ACT_DLV_DT IS NOT NULL))
   FROM SUPPLY_CHAIN_FORGE.TMS_SOURCE.VTTK s
   JOIN SUPPLY_CHAIN_FORGE.ERP_SOURCE.VBAK o ON s.VBELN = o.VBELN
   WHERE s.DPTBG > DATEADD(month, -12, CURRENT_DATE()) AND s.DPTBG <= CURRENT_DATE();
   ```

   Expected: naive ~0.68–0.74, governed ~0.87 (at least 8 points apart; DATA_SPEC §5.4).

7. **Source tables: 9 → 10** (`ERP_SOURCE.TCURR`, FX rates). The source columns change as
   DATA_SPEC §1 describes; only §8 reads them.

8. **Additive, no contract change needed**: B09's extra semantic-view content (IDs,
   descriptive columns, facts, about 10 more named metrics, named filters, instructions,
   verified queries). The §3 and §4 identifiers stay exactly as they are. B09 also adds
   `orders.order_year_quarter` (e.g. `2026-Q3`), because `order_quarter` (`Q1`–`Q4`) mixes
   the same quarter of different years in a 12-month window. §4's values are unchanged.

9. **§10**: the practice values are replaced by the values in the re-captured art 05 (B09).

**Impact on CoCo**:
- B08c: `CONFORMED`, `OPS`, source DDL v2, re-point the views
- B09: the four §3 formulas get the E01/E04/E05/E07/E08 rules via `CONFORMED`; OTD's
  denominator also needs a promised date; `SP_METRICS_AS_*` apply §3a;
  `AI_SQL_GENERATION` states §3a
- B10: the agent states the period in every answer
- B14: audits §3a

**Impact on Claude Code**:
- `app/utils/config.py`: the four §3 definition strings change (verbatim above); remove
  `MCP_SERVER`
- `forge_data.py`:
  - every metric query adds the §3a `WHERE`
  - `get_naive_otd()` adds the window
  - the as-of date comes from `SP_DATA_HEALTH('shipments')` (C09 part B)
- the Data health screen judges DMF results by layer: zero is expected only in `CONFORMED`
  (DATA_SPEC §7.2)
- C11's ground truth and C13's live tests apply §3a.

---

_Open change requests: none. CR-006 accepted 2026-09-29 (v1.5)._

<!--
To propose a change, append:

### CR-00N — <title>
**Requested by**: CoCo | Claude Code
**Reason**:
**Proposed change**:
**Impact on the other agent**:
**Status**: PROPOSED | ACCEPTED | REJECTED
-->
