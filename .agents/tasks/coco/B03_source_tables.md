# B03 — Source Tables (9)

| | |
|---|---|
| **Owner** | CoCo |
| **Milestone** | M1 |
| **Prerequisite** | B02 gate passed |
| **Est. effort** | One session |
| **Writes** | `sql/02_tables/01_srm_source.sql`, `sql/02_tables/02_wms_source.sql`, `sql/02_tables/03_erp_source.sql`, `sql/02_tables/04_tms_source.sql` |

---

## Goal

Create the 9 source tables across the four source schemas (`SRM_SOURCE`, `WMS_SOURCE`, `ERP_SOURCE`, `TMS_SOURCE`) with deliberately cryptic, SAP-style column naming matching `docs/LLD.md` §2.

---

## The 9 Source Tables

Four disparate source systems simulate real-world enterprise silos:

| Schema | Table | Physical Object | Description |
|--------|-------|-----------------|-------------|
| `SRM_SOURCE` | `LFA1` | `SUPPLY_CHAIN_FORGE.SRM_SOURCE.LFA1` | Suppliers (SAP LFA1) |
| `SRM_SOURCE` | `MARA` | `SUPPLY_CHAIN_FORGE.SRM_SOURCE.MARA` | Parts / Materials (SAP MARA) |
| `SRM_SOURCE` | `SOURCING` | `SUPPLY_CHAIN_FORGE.SRM_SOURCE.SOURCING` | Sourcing contract mapping (M:N) |
| `WMS_SOURCE` | `T001W` | `SUPPLY_CHAIN_FORGE.WMS_SOURCE.T001W` | Plants / Warehouses (SAP T001W) |
| `WMS_SOURCE` | `MARD` | `SUPPLY_CHAIN_FORGE.WMS_SOURCE.MARD` | Daily Inventory Snapshots (SAP MARD) |
| `ERP_SOURCE` | `KNA1` | `SUPPLY_CHAIN_FORGE.ERP_SOURCE.KNA1` | Customers (SAP KNA1) |
| `ERP_SOURCE` | `VBAK` | `SUPPLY_CHAIN_FORGE.ERP_SOURCE.VBAK` | Sales Order Headers (SAP VBAK) |
| `ERP_SOURCE` | `VBAP` | `SUPPLY_CHAIN_FORGE.ERP_SOURCE.VBAP` | Sales Order Lines (SAP VBAP) |
| `TMS_SOURCE` | `VTTK` | `SUPPLY_CHAIN_FORGE.TMS_SOURCE.VTTK` | Shipments & Freight (SAP VTTK) |

*(Note: Table count is 9, perfectly matching the 9 governed views in `docs/CONTRACT.md` §7).*

---

## The Core Design Conflict

- `ERP_SOURCE.VBAK.ERDAT`: ERP's promised delivery date.
- `TMS_SOURCE.VTTK.PROM_DLV_DT`: Transport Management System's promised delivery date (authoritative).
- These two columns will deliberately disagree on 15–25% of orders during data generation in B04.

---

## Steps

1. Clean up legacy placeholder files in `sql/02_tables/` (`customers.sql`, `inventory.sql`, `orders.sql`, `parts.sql`, `plants.sql`, `shipments.sql`, `suppliers.sql`).
2. Write schema-organized SQL files:
   - `sql/02_tables/01_srm_source.sql`: `LFA1`, `MARA`, `SOURCING`
   - `sql/02_tables/02_wms_source.sql`: `T001W`, `MARD`
   - `sql/02_tables/03_erp_source.sql`: `KNA1`, `VBAK`, `VBAP`
   - `sql/02_tables/04_tms_source.sql`: `VTTK`
3. Execute all 4 SQL files against Snowflake in `FORGE_ADMIN` / `ACCOUNTADMIN`.
4. Verify all tables exist with correct schemas, columns, data types, and primary keys.

---

## Gate

All checks must pass before B04:

```sql
USE DATABASE SUPPLY_CHAIN_FORGE;

-- 1. Verify 9 tables across the 4 source schemas
SHOW TABLES IN SCHEMA SRM_SOURCE; -- 3 tables (LFA1, MARA, SOURCING)
SHOW TABLES IN SCHEMA WMS_SOURCE; -- 2 tables (T001W, MARD)
SHOW TABLES IN SCHEMA ERP_SOURCE; -- 3 tables (KNA1, VBAK, VBAP)
SHOW TABLES IN SCHEMA TMS_SOURCE; -- 1 table (VTTK)

-- Total source table count = 9
SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_SCHEMA IN ('SRM_SOURCE', 'WMS_SOURCE', 'ERP_SOURCE', 'TMS_SOURCE')
  AND TABLE_TYPE = 'BASE TABLE';
-- expect: 9
```

---

## On Completion

1. Tick B03 as ✅ in `.agents/NEXT.md` and set B04 as NEXT.
2. Author task card `.agents/tasks/coco/B04_data_generation.md`.
3. Update `.agents/HANDOFF.md` marking 9 Source Tables as `DEPLOYED ✅`.
4. Update `.agents/tasks/COCO_TASKS.md`.
5. Log to `docs/SESSION_LOG.md`.
