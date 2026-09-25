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
> **Version**: 1.3 · **Frozen**: 2026-09-25
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
| MCP server | `SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_MCP` |
| Streamlit app | `SUPPLY_CHAIN_FORGE.APP.FORGE_DEMO` |
| Warehouse | `FORGE_WH` |
| Persona proc — Planner | `SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_PLANNER()` |
| Persona proc — Buyer | `SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_BUYER()` |
| Persona proc — Logistics | `SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_LOGISTICS()` |
| Persona metric proc — Planner | `SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_PLANNER()` |
| Persona metric proc — Buyer | `SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_BUYER()` |
| Persona metric proc — Logistics | `SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_LOGISTICS()` |

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
                      "promised delivery date. Excludes in-transit shipments.",
    },
    "fill_rate": {
        "id": "order_lines.fill_rate",
        "label": "Fill Rate",
        "format": "percent",
        "definition": "Quantity shipped divided by quantity ordered across order "
                      "lines. Partial shipments are pro-rated.",
    },
    "days_of_inventory": {
        "id": "inventory.days_of_inventory",
        "label": "Days of Inventory",
        "format": "number",
        "definition": "Average on-hand quantity divided by average daily usage. "
                      "Uses gross on-hand, not net of reservations.",
    },
    "avg_landed_cost": {
        "id": "shipments.avg_landed_cost",
        "label": "Avg Landed Cost",
        "format": "currency",
        "definition": "Average total cost to move a shipment to destination: "
                      "freight plus duties plus handling.",
    },
}
```

---

## 4. Dimensions

Exact identifiers usable in the `DIMENSIONS` clause.

| Entity | Dimension identifiers |
|--------|----------------------|
| suppliers | `suppliers.supplier_name`, `suppliers.supplier_region`, `suppliers.supplier_tier` |
| parts | `parts.part_name`, `parts.category`, `parts.subcategory`, `parts.is_critical` |
| plants | `plants.plant_name`, `plants.plant_region`, `plants.plant_country`, `plants.plant_type` |
| customers | `customers.customer_segment`, `customers.customer_region` |
| orders | `orders.order_date`, `orders.order_month`, `orders.order_quarter`, `orders.order_year`, `orders.order_status`, `orders.order_priority` |
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

### 5.1 Metric only

```sql
SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  METRICS shipments.on_time_delivery_rate
);
```
Returns: one row, one column `ON_TIME_DELIVERY_RATE`.

### 5.2 Metric by dimension

```sql
SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  DIMENSIONS plants.plant_region
  METRICS shipments.on_time_delivery_rate
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

**Metric procedures (CR-002)** return a single row with this shape:

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
JOIN SUPPLY_CHAIN_FORGE.ERP_SOURCE.VBAK o ON s.VBELN = o.VBELN;
```

**Governed — semantic view metric (authoritative):**
```sql
SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  METRICS shipments.on_time_delivery_rate
);
```

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

Mock values must sit inside the ranges in §3 so the UI looks correct while offline:

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

_Open change requests: none (all resolved)._

<!--
To propose a change, append:

### CR-00N — <title>
**Requested by**: CoCo | Claude Code
**Reason**:
**Proposed change**:
**Impact on the other agent**:
**Status**: PROPOSED | ACCEPTED | REJECTED
-->
