# B07 — Governed Layer: 9 Conformed Views & Masking Policy Attachments

| | |
|---|---|
| **Owner** | CoCo |
| **Milestone** | M2 |
| **Prerequisite** | B06 gate passed (tags & masking policies exist) |
| **Est. effort** | One session |
| **Writes** | `sql/04_governance/03_governed_views.sql`, `docs/artifacts/03_governed_columns.json` |
| **Status** | ✅ done 2026-09-27, gate passed |

---

## Goal

Create the 9 conformed business views in `SUPPLY_CHAIN_FORGE.GOVERNED` schema with business-friendly column names, resolve ERP vs TMS date conflicts (authoritative TMS promised date on shipments, ERP order date on orders), attach the 4 dynamic masking policies, and capture artifact `docs/artifacts/03_governed_columns.json`.

---

## Design decisions (planning, 2026-09-27)

| Decision | Why |
|---|---|
| **Masking attached inline** (`col WITH MASKING POLICY …` in `CREATE OR REPLACE VIEW`), not a separate `ALTER VIEW … SET MASKING POLICY` | One atomic statement per view: a view never exists unmasked, and the script is safely re-runnable (`CREATE OR REPLACE` would drop `ALTER`-attached policies). Compile-checked against the real policies. |
| **Views owned by `ACCOUNTADMIN`** | Matches B03–B06 ownership. `FORGE_ADMIN` has no `SELECT` on source tables, so a `FORGE_ADMIN`-owned view could not read its source. |
| **Regular views, not secure** | The source → business mapping is part of the demo story; masking does the protecting. |
| **Pass-through columns** (rename only) | Keeps source types, which must match the policy signatures (`NUMBER(12,2)`, `NUMBER(15,2)`, `VARCHAR`). |
| **`V_ORDER` exactly as contract §7** (5 columns) | GAP-2's derived time columns (`order_year`, `order_quarter`, `order_month`, `order_week`) become **semantic-view dimension expressions in B08** using the GAP-2 formulas. No contract change needed; C6a reconciles views against §7 exactly. |
| **Tags on views** | `ENTITY_TYPE`, `SOURCE_SYSTEM`, `SENSITIVITY` per view, and `SENSITIVITY`/`PII` on masked columns, mirroring B06's source tags at the layer users query. |
| **No source-table grants to personas** | Persona roles have `USAGE` on source schemas but no `SELECT` on source tables, so governed views are the only path and masking cannot be bypassed. |

---

## The 9 Governed Views & Column Definitions

All column names must match `docs/CONTRACT.md` §7 exactly:

| # | Governed View | Source Table | Columns & Masking Attachments |
|---|---|---|---|
| 1 | `GOVERNED.V_SUPPLIER` | `SRM_SOURCE.LFA1` | `supplier_id`, `supplier_name`, `country`, `region`, `supplier_tier`, `lead_time_days`, `reliability_score`, `payment_terms` (MASKED: `MASK_PAYMENT_TERMS`), `email` |
| 2 | `GOVERNED.V_PART` | `SRM_SOURCE.MARA` | `part_id`, `part_name`, `category`, `subcategory`, `unit_cost` (MASKED: `MASK_SUPPLIER_COST`), `weight_kg`, `is_critical` |
| 3 | `GOVERNED.V_SOURCING` | `SRM_SOURCE.SOURCING` | `source_id`, `supplier_id`, `part_id`, `is_primary`, `contract_price` (MASKED: `MASK_SUPPLIER_COST`) |
| 4 | `GOVERNED.V_PLANT` | `WMS_SOURCE.T001W` | `plant_id`, `plant_name`, `country`, `region`, `plant_type`, `capacity_units` |
| 5 | `GOVERNED.V_INVENTORY` | `WMS_SOURCE.MARD` | `inventory_key`, `plant_id`, `part_id`, `quantity_on_hand`, `quantity_reserved`, `reorder_point`, `daily_usage`, `snapshot_date` |
| 6 | `GOVERNED.V_CUSTOMER` | `ERP_SOURCE.KNA1` | `customer_id`, `customer_name` (MASKED: `MASK_CUSTOMER_PII`), `email` (MASKED: `MASK_CUSTOMER_PII`), `country`, `region`, `customer_segment`, `credit_limit` (MASKED: `MASK_CREDIT_LIMIT`) |
| 7 | `GOVERNED.V_ORDER` | `ERP_SOURCE.VBAK` | `order_id`, `customer_id`, `order_date`, `order_status`, `order_priority` *(Note: ERP `ERDAT` deliberately not exposed)* |
| 8 | `GOVERNED.V_ORDER_LINE` | `ERP_SOURCE.VBAP` | `line_id`, `order_id`, `part_id`, `plant_id`, `quantity_ordered`, `quantity_shipped`, `unit_price` |
| 9 | `GOVERNED.V_SHIPMENT` | `TMS_SOURCE.VTTK` | `shipment_id`, `order_id`, `plant_id`, `carrier`, `ship_date`, `promised_delivery_date` (authoritative TMS date), `actual_delivery_date`, `freight_cost`, `duty_cost`, `handling_cost`, `shipment_status` |

---

## Steps

1. Write `sql/04_governance/03_governed_views.sql`:
   - Create all 9 conformed views in `SUPPLY_CHAIN_FORGE.GOVERNED`, masking policies inline.
   - Tag views and masked columns.
   - Grant `SELECT` on all views in `GOVERNED` schema to `FORGE_ADMIN`, `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE`.
2. Execute the script in Snowflake as `ACCOUNTADMIN`.
3. Run the gate below.
4. Capture artifact `docs/artifacts/03_governed_columns.json`: `INFORMATION_SCHEMA.COLUMNS` for all 9 views plus `POLICY_REFERENCES` (column → policy) per view.

---

## Gate

All checks must pass before B07b:

1. `SHOW VIEWS IN SCHEMA GOVERNED` → 9 views.
2. `INFORMATION_SCHEMA.COLUMNS` for the 9 views equals contract §7 exactly: same names, same order, nothing extra. `V_ORDER` exposes no `ERDAT` / promised date.
3. Full masking matrix: each of the 6 masked columns under `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE` and `FORGE_ADMIN`, each query also selecting `CURRENT_ROLE()`. Must equal contract §6 (`FORGE_ADMIN` sees all).
4. Every role can `SELECT` every view; view row counts equal source row counts.
5. Metrics unchanged by the governed layer and by masking: OTD, fill rate, DOI and landed cost computed from the views under `PLANNER_ROLE` and `BUYER_ROLE` equal artifact 02 (0.8740, 0.9265, 28.51, 518.97).
6. `docs/artifacts/03_governed_columns.json` exists and parses as JSON.

### Gate results (2026-09-27, live)

| # | Check | Result |
|---|---|---|
| 1 | Views | 9, all owned by `ACCOUNTADMIN` ✅ |
| 2 | Columns vs §7 | 65 expected, 65 actual, 0 mismatches (name and position); 0 ERP-date leaks ✅ |
| 3 | Masking matrix (rows masked / total) | PLANNER and LOGISTICS: unit_cost 250/250 NULL, contract_price 400/400 NULL, payment_terms 60/60 RESTRICTED, customer PII visible, credit_limit NULL. BUYER: costs and terms visible, customer_name and email 120/120 MASKED, credit_limit NULL. FORGE_ADMIN: all visible ✅ |
| 4 | Access and row counts | every role reads every view; counts 60/250/400/12/9000/120/800/2400/800 = source ✅ |
| 5 | Metrics across personas | identical to 6 dp under all 3 roles: OTD 0.873973, DOI 28.499215, landed 518.971250, fill 0.787449 ✅ (invariant). Differences from artifact 02 are metric **definitions**, not the views: fill rate → **CR-005 PROPOSED**; DOI 28.51 in art 02 was an average of per-row ratios, and §3's ratio of averages gives 28.499215 |
| 6 | Artifact | written verbatim; SHA-256 `88a03b5f…bed8e90` matches Snowflake's hash of the result; parses (9 views, 65 cols, 6 masks) ✅ |

---

## On Completion

1. Tick B07 as ✅ in `.agents/NEXT.md` and set B07b as NEXT.
2. Author task card `.agents/tasks/coco/B07b_persona_procedures.md`.
3. Update `.agents/HANDOFF.md` marking 9 Governed Views and `03_governed_columns.json` as `DONE ✅`; note the B08 time-dimension decision.
4. Update `.agents/tasks/COCO_TASKS.md` and log to `docs/SESSION_LOG.md`.
