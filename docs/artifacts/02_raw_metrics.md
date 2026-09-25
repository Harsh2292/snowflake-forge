# Artifact 02 — Raw Baseline Metrics & Divergence Sanity Check

- **Build Step**: `B05`
- **Captured At**: `2026-09-25 08:25:00 UTC`
- **Captured By**: CoCo
- **Source Database**: `SUPPLY_CHAIN_FORGE`
- **Purpose**: Record live raw metrics computed directly from source tables (`ERP_SOURCE`, `WMS_SOURCE`, `TMS_SOURCE`, `SRM_SOURCE`) prior to the semantic layer. Provides exact baseline figures for Claude Code's demo script and Tab 3 divergence proof.

---

## 1. Canonical Metrics Baseline (Target vs Measured)

| Metric | Business Definition | Target Range | Measured Value | Conformance Status |
|---|---|---|---|---|
| **On-Time Delivery (OTD)** | Share of delivered shipments arriving on or before TMS promised delivery date | `0.8400 – 0.9000` | **`0.8740` (87.40%)** | PASS (Target ~87%) |
| **Order Fill Rate** | Total units shipped divided by total units ordered | `0.9000 – 0.9500` | **`0.9265` (92.65%)** | PASS (Target ~93%) |
| **Days of Inventory (DOI)** | Average stock on hand divided by average daily usage | `15.0 – 45.0 days` | **`28.51 days`** | PASS (Target ~28.4 days) |
| **Average Landed Cost** | Average total shipping cost (Freight + Duties + Handling) per shipment | `$150.00 – $900.00` | **`$518.97`** | PASS (Target ~$412) |

---

## 2. Problem Statement Divergence Proof (Tab 3 Demo Hook)

The core hackathon narrative demonstrates the **semantic disagreement** between ERP and Transport (TMS) systems before the governed semantic layer resolves it:

```sql
SELECT 
    -- Authoritative TMS metric:
    COUNT_IF(s.ACT_DLV_DT <= s.PROM_DLV_DT) / NULLIFZERO(COUNT_IF(s.ACT_DLV_DT IS NOT NULL)) AS authoritative_tms_otd,
    -- Naive ERP metric:
    COUNT_IF(s.ACT_DLV_DT <= o.ERDAT) / NULLIFZERO(COUNT_IF(s.ACT_DLV_DT IS NOT NULL)) AS naive_erp_otd
FROM TMS_SOURCE.VTTK s
JOIN ERP_SOURCE.VBAK o ON s.VBELN = o.VBELN;
```

### Measured Divergence Results

| Metric Query Type | Definition Used | Measured OTD Rate | Interpretation |
|---|---|---|---|
| **Governed / Authoritative (TMS)** | `ACT_DLV_DT <= PROM_DLV_DT` | **`87.40%`** | **True Performance**: Carrier met logistics promised SLA |
| **Naive / Siloed (ERP)** | `ACT_DLV_DT <= ERDAT` | **`78.36%`** | **False Alarm**: Sales order date differs from logistics schedule |
| **Divergence Delta** | Discrepancy | **`9.04%`** | **The Semantic Conflict**: Proves why departments disagree |
| **Date Conflict Frequency** | `PROM_DLV_DT != ERDAT` | **`20.00%`** | 160 of 800 orders experience conflicting promised dates |

---

## 3. Dimensional Metric Breakdowns

### A. On-Time Delivery by Region (`plants.plant_region`)
| Region | Total Shipments | Delivered Shipments | On-Time Delivery Rate |
|---|---|---|---|
| **APAC** | 266 | 242 | **`88.02%`** |
| **AMER** | 267 | 241 | **`87.14%`** |
| **EMEA** | 267 | 247 | **`87.04%`** |
| **Total / Overall** | **800** | **730** | **`87.40%`** |

*(Note: 70 shipments [8.75%] are currently `IN_TRANSIT` with `ACT_DLV_DT = NULL`).*

---

### B. Order Fill Rate by Material Category (`parts.category`)
| Product Category | Units Ordered | Units Shipped | Category Fill Rate |
|---|---|---|---|
| **CHEMICAL** | 37,567 | 37,567 | **`100.00%`** |
| **RAW_MATERIAL** | 37,793 | 37,793 | **`100.00%`** |
| **ELECTRONICS** | 36,660 | 36,660 | **`100.00%`** |
| **FASTENERS** | 36,698 | 31,340 | **`85.40%`** |
| **PACKAGING** | 37,304 | 31,781 | **`85.19%`** |
| **MECHANICAL** | 37,238 | 31,706 | **`85.14%`** |
| **Overall Total** | **223,260** | **206,847** | **`92.65%`** |

---

### C. Days of Inventory (DOI) by Plant (`plants.plant_name`)
| Plant ID | Facility Name | Region | Type | Measured Avg DOI |
|---|---|---|---|---|
| `PL01` | Tokyo Advanced DC | APAC | DC | **28.73 days** |
| `PL02` | Shanghai Mega Manufacturing | APAC | MFG | **28.16 days** |
| `PL03` | Singapore Logistics Gateway | APAC | HUB | **28.76 days** |
| `PL04` | Chennai Heavy Production | APAC | MFG | **28.33 days** |
| `PL05` | Frankfurt Central Distribution | EMEA | DC | **28.96 days** |
| `PL06` | Rotterdam Freight Hub | EMEA | HUB | **28.39 days** |
| `PL07` | Munich Precision Facility | EMEA | MFG | **28.57 days** |
| `PL08` | London Regional DC | EMEA | DC | **28.50 days** |
| `PL09` | Chicago Industrial Plant | AMER | MFG | **28.43 days** |
| `PL10` | Dallas Distribution Center | AMER | DC | **28.61 days** |
| `PL11` | Long Beach Maritime Hub | AMER | HUB | **28.04 days** |
| `PL12` | Monterrey Assembly Plant | AMER | MFG | **28.67 days** |
| **Overall** | **12 Facilities Worldwide** | **Global** | **All** | **`28.51 days`** |

---

### D. Landed Cost Breakdown by Region (`plants.plant_region`)
| Region | Avg Freight Cost | Avg Customs Duty | Avg Terminal Handling | Avg Total Landed Cost |
|---|---|---|---|---|
| **APAC** | $340.44 | $107.01 | $67.92 | **`$515.37`** |
| **AMER** | $342.14 | $107.92 | $68.34 | **`$518.40`** |
| **EMEA** | $348.35 | $105.70 | $69.07 | **`$523.12`** |
| **Overall** | **$343.65** | **$106.87** | **$68.44** | **`$518.97`** |

---

## 4. Data Quality & Referential Integrity Status

* **Overshipping Violations (`QTY_SHIPPED > KWMENG`)**: **`0 rows`** (Zero data quality defects).
* **Primary Sourcing Coverage**: **`250 of 250 parts`** have exactly 1 primary supplier (`IS_PRIMARY = TRUE`).
* **Foreign Key Integrity**: All transactional records (`VBAP`, `VTTK`, `MARD`) resolve cleanly to existing master entities with zero orphan keys.
