# B01 — Database, Schemas, Warehouse

| | |
|---|---|
| **Owner** | CoCo |
| **Milestone** | M1 |
| **Prerequisite** | None — this is the first card |
| **Est. effort** | One session, ~10 minutes |
| **Writes** | `sql/01_setup/01_database.sql` |

---

## Goal

Create the `SUPPLY_CHAIN_FORGE` database with seven schemas and an XSMALL warehouse.

---

## Why seven schemas

Four of them simulate **separate source systems** with deliberately inconsistent naming.
That is the project's core narrative — see `docs/HLD.md` §1–2. Do not collapse them into
one `RAW` schema.

| Schema | Represents |
|--------|-----------|
| `ERP_SOURCE` | Enterprise resource planning — customers, orders, order lines |
| `WMS_SOURCE` | Warehouse management — plants, inventory |
| `TMS_SOURCE` | Transport management — shipments |
| `SRM_SOURCE` | Supplier relationship management — suppliers, parts, sourcing |
| `GOVERNED` | Conformed views, policies, persona procedures |
| `SEMANTIC` | Semantic view, agent, MCP servers |
| `APP` | Streamlit app |

---

## Steps

1. Write `sql/01_setup/01_database.sql` containing:
   - `CREATE DATABASE IF NOT EXISTS SUPPLY_CHAIN_FORGE`
   - `CREATE SCHEMA IF NOT EXISTS` for each of the seven above
   - `CREATE WAREHOUSE IF NOT EXISTS FORGE_WH` with:
     - `WAREHOUSE_SIZE = 'XSMALL'`
     - `AUTO_SUSPEND = 60`
     - `AUTO_RESUME = TRUE`
     - `INITIALLY_SUSPENDED = TRUE`
   - A `COMMENT` on the database and on each schema explaining its role
2. Execute the file
3. Drop the default `PUBLIC` schema if it was auto-created and is unused

---

## Gate

All three must pass before B02:

```sql
-- 1. Seven schemas (plus INFORMATION_SCHEMA)
SHOW SCHEMAS IN DATABASE SUPPLY_CHAIN_FORGE;

-- 2. Warehouse configured correctly
SHOW WAREHOUSES LIKE 'FORGE_WH';
--    expect: size XSMALL, auto_suspend 60, auto_resume true

-- 3. Context switches cleanly
USE DATABASE SUPPLY_CHAIN_FORGE;
USE WAREHOUSE FORGE_WH;
SELECT CURRENT_DATABASE(), CURRENT_WAREHOUSE();
```

---

## Cost note

`AUTO_SUSPEND = 60` is not optional. An XSMALL warehouse left running burns credits for
nothing. Budget discipline is in `docs/HLD.md` §9.

---

## On completion

1. Tick B01 as ✅ in `.agents/NEXT.md` and set B02 as NEXT
2. Update `.agents/HANDOFF.md` → Latest from CoCo → mark database/schemas/warehouse DONE
3. If anything deviated from `docs/CONTRACT.md`, file a Change Request in §11
