# B06 — Governance: Object Tags & Dynamic Masking Policies

| | |
|---|---|
| **Owner** | CoCo |
| **Milestone** | M2 |
| **Prerequisite** | B05 gate passed (raw distributions verified) |
| **Est. effort** | One session |
| **Writes** | `sql/04_governance/01_tags.sql`, `sql/04_governance/02_masking_policies.sql` |

---

## Goal

Create 5 governance object tags and 4 dynamic column masking policies in `SUPPLY_CHAIN_FORGE.GOVERNED` schema to enforce column-level data privacy per `docs/CONTRACT.md` §6 and `docs/LLD.md` §5.

---

## 1. Object Tags (`01_tags.sql`)

Created in `GOVERNED` schema with strict allowed value lists:

| Tag Name | Allowed Values |
|---|---|
| `ENTITY_TYPE` | `'SUPPLIER'`, `'PART'`, `'PLANT'`, `'INVENTORY'`, `'CUSTOMER'`, `'ORDER'`, `'ORDER_LINE'`, `'SHIPMENT'`, `'SOURCING'` |
| `SOURCE_SYSTEM` | `'ERP'`, `'WMS'`, `'TMS'`, `'SRM'` |
| `SENSITIVITY` | `'PUBLIC'`, `'INTERNAL'`, `'CONFIDENTIAL'`, `'RESTRICTED'` |
| `PII` | `'TRUE'`, `'FALSE'` |
| `METRIC_FAMILY` | `'DELIVERY'`, `'FULFILLMENT'`, `'INVENTORY'`, `'COST'` |

---

## 2. Dynamic Masking Policies (`02_masking_policies.sql`)

All masking policies must use **`CURRENT_ROLE()`** or **`IS_ROLE_IN_SESSION()`** (never `INVOKER_ROLE()`, per contract §6a) to ensure owner's-rights persona procedures evaluate the true persona context:

| Policy Name | Target Column Type | Visible To | Masked Value |
|---|---|---|---|
| `MASK_SUPPLIER_COST` | `NUMBER(12,2)` | `FORGE_ADMIN`, `BUYER_ROLE` | `NULL` |
| `MASK_PAYMENT_TERMS` | `VARCHAR` | `FORGE_ADMIN`, `BUYER_ROLE` | `'*** RESTRICTED ***'` |
| `MASK_CUSTOMER_PII` | `VARCHAR` | `FORGE_ADMIN`, `PLANNER_ROLE`, `LOGISTICS_ROLE` | `'*** MASKED ***'` |
| `MASK_CREDIT_LIMIT` | `NUMBER(15,2)` | `FORGE_ADMIN` | `NULL` |

*(Note: Row Access Policy `RAP_PLANT_REGION` is dropped from MVP per `docs/GAPS_RESOLVED.md` GAP-4 to ensure persona metric aggregates remain 100% identical).*

---

## Steps

1. Clean up legacy placeholder files in `sql/04_governance/` (`policies.sql`, `tags.sql`).
2. Write `sql/04_governance/01_tags.sql`:
   - Create all 5 tags with allowed value specifications in `SUPPLY_CHAIN_FORGE.GOVERNED`.
   - Apply tags to the source schemas/tables.
3. Write `sql/04_governance/02_masking_policies.sql`:
   - Create the 4 masking policies in `SUPPLY_CHAIN_FORGE.GOVERNED`.
4. Execute both scripts in Snowflake using `FORGE_ADMIN` / `ACCOUNTADMIN`.
5. Verify tags and masking policy objects exist and are properly authorized.

---

## Gate

All checks must pass before B07:

```sql
USE DATABASE SUPPLY_CHAIN_FORGE;
USE SCHEMA GOVERNED;

-- 1. Verify 5 Tags exist
SHOW TAGS IN SCHEMA GOVERNED; -- expect 5 tags

-- 2. Verify 4 Masking Policies exist
SHOW MASKING POLICIES IN SCHEMA GOVERNED; -- expect 4 policies (MASK_SUPPLIER_COST, MASK_PAYMENT_TERMS, MASK_CUSTOMER_PII, MASK_CREDIT_LIMIT)
```

---

## On Completion

1. Tick B06 as ✅ in `.agents/NEXT.md` and set B07 as NEXT.
2. Author task card `.agents/tasks/coco/B07_governed_views.md`.
3. Update `.agents/HANDOFF.md` marking Governance as `DEPLOYED ✅`.
4. Update `.agents/tasks/COCO_TASKS.md` and log to `docs/SESSION_LOG.md`.
