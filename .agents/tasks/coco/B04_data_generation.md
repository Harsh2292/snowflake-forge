# B04 — Data Generation (Masters & Transactions)

| | |
|---|---|
| **Owner** | CoCo |
| **Milestone** | M1 |
| **Prerequisite** | B03 gate passed (9 source tables exist) |
| **Est. effort** | One session |
| **Writes** | `sql/03_sample_data/01_generate_masters.sql`, `sql/03_sample_data/02_generate_transactions.sql` |

---

## Goal

Populate all 9 source tables with realistic, statistically calibrated supply chain sample data using native Snowflake table generators (`GENERATOR`, `UNIFORM`, `NORMAL`, `RANDOM`).

---

## Target Volumes & Distribution Controls

Data must be inserted in strict **Foreign Key order** per `docs/LLD.md` §3 and `docs/GAPS_RESOLVED.md` GAP-6:

### 1. Master Entities (`01_generate_masters.sql`)
| Table | Schema | Target Rows | Key Constraints & Distribution Rules |
|---|---|---|---|
| `LFA1` | `SRM_SOURCE` | 60 | Tier 1 (20%), Tier 2 (50%), Tier 3 (30%). Reliability 0.70–0.99 |
| `MARA` | `SRM_SOURCE` | 250 | 6 categories × 4 subcategories. ~15% critical parts (`CRIT_FLG = TRUE`) |
| `SOURCING` | `SRM_SOURCE` | 400 | Exactly one `IS_PRIMARY = TRUE` per part (`MATNR`); remaining suppliers secondary |
| `T001W` | `WMS_SOURCE` | 12 | 4 APAC, 4 EMEA, 4 AMER. Mix of `MFG`, `DC`, `HUB` |
| `KNA1` | `ERP_SOURCE` | 120 | 3 segments (`ENTERPRISE`, `MIDMARKET`, `SMB`), 3 regions (`APAC`, `EMEA`, `AMER`) |

### 2. Transactional Entities (`02_generate_transactions.sql`)
| Table | Schema | Target Rows | Key Constraints & Distribution Rules |
|---|---|---|---|
| `VBAK` | `ERP_SOURCE` | 800 | 12 months order history with Q4 seasonal uplift. ~5% cancelled |
| `VBAP` | `ERP_SOURCE` | ~2,400 | Avg 3 lines/order. `QTY_SHIPPED <= KWMENG` always. Target Fill Rate ≈ 93% |
| `VTTK` | `TMS_SOURCE` | ~900 | ~1.1 shipments/order. Target OTD ≈ 87%. ~8% `IN_TRANSIT` (`ACT_DLV_DT IS NULL`) |
| `MARD` | `WMS_SOURCE` | ~9,000 | 12 plants × 250 parts sampled × 30 daily snapshots. DOI range 15–45 days |

---

## The Deliberate Date Discrepancy Hook

- In `ERP_SOURCE.VBAK`, `ERDAT` (ERP promised date) is generated.
- In `TMS_SOURCE.VTTK`, `PROM_DLV_DT` (TMS authoritative promised delivery date) is generated.
- On **15–25% of orders**, `ERDAT` deliberately differs from `PROM_DLV_DT` by ±1 to 5 days to demonstrate ERP vs TMS semantic conflict in the divergence demo (Tab 3).

---

## Steps

1. Clean up legacy placeholder file `sql/03_sample_data/seed_data.sql`.
2. Write `sql/03_sample_data/01_generate_masters.sql`:
   - Generate `LFA1`, `MARA`, `SOURCING`, `T001W`, `KNA1`.
3. Write `sql/03_sample_data/02_generate_transactions.sql`:
   - Generate `VBAK`, `VBAP`, `VTTK`, `MARD`.
4. Execute both scripts in Snowflake using `FORGE_ADMIN` / `ACCOUNTADMIN` on warehouse `FORGE_WH`.
5. Verify row counts and foreign key integrity.

---

## Gate

All checks must pass before B05:

```sql
USE DATABASE SUPPLY_CHAIN_FORGE;

-- 1. Verify row counts are within 10% of targets
SELECT 'LFA1' AS tbl, COUNT(*) AS cnt, 60 AS target FROM SRM_SOURCE.LFA1
UNION ALL SELECT 'MARA', COUNT(*), 250 FROM SRM_SOURCE.MARA
UNION ALL SELECT 'SOURCING', COUNT(*), 400 FROM SRM_SOURCE.SOURCING
UNION ALL SELECT 'T001W', COUNT(*), 12 FROM WMS_SOURCE.T001W
UNION ALL SELECT 'KNA1', COUNT(*), 120 FROM ERP_SOURCE.KNA1
UNION ALL SELECT 'VBAK', COUNT(*), 800 FROM ERP_SOURCE.VBAK
UNION ALL SELECT 'VBAP', COUNT(*), 2400 FROM ERP_SOURCE.VBAP
UNION ALL SELECT 'VTTK', COUNT(*), 900 FROM TMS_SOURCE.VTTK
UNION ALL SELECT 'MARD', COUNT(*), 9000 FROM WMS_SOURCE.MARD;

-- 2. Verify primary sourcing integrity (every part has exactly 1 primary supplier)
SELECT COUNT(DISTINCT MATNR) FROM SRM_SOURCE.MARA;
SELECT COUNT(*) FROM SRM_SOURCE.SOURCING WHERE IS_PRIMARY = TRUE;
-- Both counts must match exactly (250)

-- 3. Verify no overshipping (QTY_SHIPPED <= KWMENG)
SELECT COUNT(*) FROM ERP_SOURCE.VBAP WHERE QTY_SHIPPED > KWMENG;
-- expect: 0

-- 4. Verify ERP vs TMS date conflict rate is between 15% and 25%
SELECT 
  COUNT_IF(s.PROM_DLV_DT != o.ERDAT) / COUNT(*) AS date_conflict_rate
FROM TMS_SOURCE.VTTK s
JOIN ERP_SOURCE.VBAK o ON s.VBELN = o.VBELN;
-- expect: 0.15 - 0.25
```

---

## On Completion

1. Tick B04 as ✅ in `.agents/NEXT.md` and set B05 as NEXT.
2. Author task card `.agents/tasks/coco/B05_verify_distributions.md`.
3. Update `.agents/HANDOFF.md` marking Sample Data as `DEPLOYED ✅`.
4. Update `.agents/tasks/COCO_TASKS.md` and log to `docs/SESSION_LOG.md`.
