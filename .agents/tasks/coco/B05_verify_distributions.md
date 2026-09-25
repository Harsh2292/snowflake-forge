# B05 — Distribution Verification & Raw Metrics Artifact

| | |
|---|---|
| **Owner** | CoCo |
| **Milestone** | M1 |
| **Prerequisite** | B04 gate passed (all 9 tables seeded) |
| **Est. effort** | One session |
| **Writes** | `sql/03_sample_data/03_verify_distributions.sql`, `docs/artifacts/02_raw_metrics.md` |

---

## Goal

Run distribution verification queries across the seeded source data to confirm all four canonical metrics land within `docs/CONTRACT.md` §3 targets and capture artifact `docs/artifacts/02_raw_metrics.md` showing the divergent OTD numbers for Tab 3.

---

## What to Verify

1. **On-Time Delivery (OTD)**:
   - Authoritative TMS OTD: `COUNT_IF(ACT_DLV_DT <= PROM_DLV_DT) / COUNT_IF(ACT_DLV_DT IS NOT NULL)` (Target: 0.84 – 0.90, actual ≈ 0.8740)
   - Naive ERP OTD (The Divergence Hook): `COUNT_IF(ACT_DLV_DT <= ERDAT) / COUNT_IF(ACT_DLV_DT IS NOT NULL)` (actual ≈ 0.7836)
2. **Fill Rate**:
   - `SUM(QTY_SHIPPED) / SUM(KWMENG)` across active order lines (Target: 0.90 – 0.95, actual ≈ 0.9265)
3. **Days of Inventory (DOI)**:
   - `AVG(LABST / DAILY_USG)` across all 9,000 snapshots (Target: 15 – 45 days, actual ≈ 28.51)
4. **Average Landed Cost**:
   - `AVG(FREIGHT_AMT + DUTY_AMT + HANDLING_AMT)` across shipments (Target: $150 – $900, actual ≈ $518.97)

---

## Steps

1. Write `sql/03_sample_data/03_verify_distributions.sql`.
2. Execute the verification script in Snowflake.
3. Capture artifact `docs/artifacts/02_raw_metrics.md` containing the baseline metric values and the exact divergence numbers.
4. Verify Gate criteria.

---

## Gate

All checks must pass before B06:

```sql
USE DATABASE SUPPLY_CHAIN_FORGE;

-- 1. All metrics in contract range
SELECT 
    COUNT_IF(ACT_DLV_DT <= PROM_DLV_DT) / NULLIFZERO(COUNT_IF(ACT_DLV_DT IS NOT NULL)) BETWEEN 0.84 AND 0.90 AS otd_in_range,
    (SELECT SUM(QTY_SHIPPED) / SUM(KWMENG) FROM ERP_SOURCE.VBAP WHERE QTY_SHIPPED > 0) BETWEEN 0.90 AND 0.95 AS fill_rate_in_range,
    (SELECT AVG(LABST / NULLIFZERO(DAILY_USG)) FROM WMS_SOURCE.MARD) BETWEEN 15.0 AND 45.0 AS doi_in_range,
    AVG(FREIGHT_AMT + DUTY_AMT + HANDLING_AMT) BETWEEN 150.0 AND 900.0 AS landed_cost_in_range
FROM TMS_SOURCE.VTTK;

-- 2. Artifact docs/artifacts/02_raw_metrics.md exists and is populated
```

---

## On Completion

1. Tick B05 as ✅ in `.agents/NEXT.md` and set B06 as NEXT.
2. Author task card `.agents/tasks/coco/B06_tags_masking.md`.
3. Update `.agents/HANDOFF.md` marking `02_raw_metrics.md` as `DONE ✅`.
4. Update `.agents/tasks/COCO_TASKS.md` and log to `docs/SESSION_LOG.md`.
