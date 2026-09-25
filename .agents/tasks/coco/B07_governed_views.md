# B07 — Governed Layer: 9 Conformed Views & Masking Policy Attachments

| | |
|---|---|
| **Owner** | CoCo |
| **Milestone** | M2 |
| **Prerequisite** | B06 gate passed (tags & masking policies exist) |
| **Est. effort** | One session |
| **Writes** | `sql/04_governance/03_governed_views.sql`, `docs/artifacts/03_governed_columns.json` |

---

## Goal

Create the 9 conformed business views in `SUPPLY_CHAIN_FORGE.GOVERNED` schema with business-friendly column names, resolve ERP vs TMS date conflicts (authoritative TMS promised date on shipments, ERP order date on orders), attach the 4 dynamic masking policies, and capture artifact `docs/artifacts/03_governed_columns.json`.

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
   - Create all 9 conformed views in `SUPPLY_CHAIN_FORGE.GOVERNED`.
   - Attach masking policies using `ALTER VIEW ... MODIFY COLUMN ... SET MASKING POLICY ...`.
   - Grant `SELECT` on all views in `GOVERNED` schema to `FORGE_ADMIN`, `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE`.
2. Execute the script in Snowflake.
3. Test that each persona role sees their expected masked/unmasked values.
4. Capture artifact `docs/artifacts/03_governed_columns.json` (`INFORMATION_SCHEMA.COLUMNS` dump for all 9 views).
5. Verify Gate criteria.

---

## Gate

All checks must pass before B07b:

```sql
USE DATABASE SUPPLY_CHAIN_FORGE;
USE SCHEMA GOVERNED;

-- 1. All 9 views exist
SHOW VIEWS IN SCHEMA GOVERNED; -- expect 9 views

-- 2. Test Selects as each persona role
USE ROLE PLANNER_ROLE;
SELECT unit_cost FROM GOVERNED.V_PART LIMIT 1; -- expect NULL (masked)
SELECT customer_name FROM GOVERNED.V_CUSTOMER LIMIT 1; -- expect visible (unmasked)

USE ROLE BUYER_ROLE;
SELECT unit_cost FROM GOVERNED.V_PART LIMIT 1; -- expect visible (unmasked)
SELECT customer_name FROM GOVERNED.V_CUSTOMER LIMIT 1; -- expect '*** MASKED ***' (masked)

USE ROLE LOGISTICS_ROLE;
SELECT payment_terms FROM GOVERNED.V_SUPPLIER LIMIT 1; -- expect '*** RESTRICTED ***' (masked)

USE ROLE ACCOUNTADMIN;

-- 3. Artifact docs/artifacts/03_governed_columns.json exists
```

---

## On Completion

1. Tick B07 as ✅ in `.agents/NEXT.md` and set B07b as NEXT.
2. Author task card `.agents/tasks/coco/B07b_persona_procedures.md`.
3. Update `.agents/HANDOFF.md` marking 9 Governed Views and `03_governed_columns.json` as `DONE ✅`.
4. Update `.agents/tasks/COCO_TASKS.md` and log to `docs/SESSION_LOG.md`.
