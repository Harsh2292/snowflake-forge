# DATA_SPEC — Realistic data v2, cleansing rules and interfaces

> **Owner**: CoCo (B08b, 2026-09-29). **Read-only for Claude Code.** This is the exact spec
> for all of Claude Code's Snowflake SQL: C08 (`data_gen/`), C10 (`quality/`), C11
> (`eval/`) and C12 (`tests/scale/`). If something here can't be built as written, raise it
> in `.agents/HANDOFF.md` ("Latest from Claude Code"); CoCo answers there and never changes
> this file silently.
>
> **Binding with**: `docs/CONTRACT.md` (v1.4 + **CR-006**, which this file implements) and
> `docs/references/snowflake_execution_notes.md` (how CoCo runs your files).
> **Supersedes**: LLD §2 (source schemas) and LLD §3 (generation targets).
>
> **Live facts behind this spec** (verified 2026-09-29): Enterprise edition (DMFs and
> dynamic tables available); `RANDOM(seed)` is not reproducible across runs (Snowflake
> docs); the hash recipe in §6 gave the same checksum on 5M rows twice, on two different
> warehouses; `SEMANTIC_VIEW(... WHERE ...)` accepts the §5 time window and a scalar
> subquery for the latest snapshot.

---

## 0. Summary

| Item | Value |
|---|---|
| History | 10 years. Business dates run from `DATEADD(year, -10, END_DATE)` to **`L = END_DATE − 1`** (the last business date: data through yesterday, loaded by the nightly batch on `END_DATE`). `END_DATE` defaults to the run date |
| Volume at `SCALE_FACTOR = 1` | ~650K orders, ~2.0M order lines, ~720K shipments, ~2.2M inventory rows |
| Source tables | **10** (the 9 of v1 plus `ERP_SOURCE.TCURR`, FX rates) |
| Randomness | hash-based only (§6). **No `RANDOM()`, `UNIFORM(..., RANDOM())`, `NORMAL(..., RANDOM())`** |
| Generator | caller's-rights procedures in `SUPPLY_CHAIN_FORGE.OPS`, target database as a parameter (§7.1) |
| Mess | 7 repairable defect types + 13 business-rule edge cases (§4), injected by a separate procedure |
| Cleansing | `CONFORMED` dynamic tables (CoCo, B08c) implement §4 and §5; `GOVERNED` views keep §7 names |
| Time rule | trailing 12 months for flow metrics, latest snapshot for DOI, anchor `CURRENT_DATE()` (§5.2) |

**Layers** (CR-006):

```
SOURCE (ERP/WMS/TMS/SRM_SOURCE)  raw, messy, as landed       ← C08 writes here
   │  dedupe · standardize codes · FX to USD · §4 rules
CONFORMED (dynamic tables)        clean, in-scope rows only   ← CoCo B08c
   │  rename to §7 columns · masking + tags inline
GOVERNED (9 views, §7)            the contract surface        ← unchanged names/columns
   │
SEMANTIC (SUPPLY_CHAIN_SV, SP_DATA_HEALTH, ...)               ← CoCo B09/B09a, C10
OPS (generator, eval, scale harness, logs)                    ← C08, C11, C12 (FORGE_ADMIN-only)
```

---

## 1. Source DDL v2

CoCo applies this DDL at B08c (`sql/02_tables/05_source_v2.sql`, `CREATE OR REPLACE`,
owner `ACCOUNTADMIN` as today). C08 writes **into** these tables and does not create them.

**Rules for every source table**:
- Only the key column is `NOT NULL`. Everything else is nullable: source systems don't
  enforce business rules, and §4 needs `NULL`s.
- PK and FK constraints stay declared, as in v1. Snowflake **doesn't enforce** them, which
  is what allows duplicates and orphans. `NOT NULL` *is* enforced.
- New last column on every table: `LOAD_TS TIMESTAMP_NTZ` (when the row landed; §3.8).
- Column order: the v1 columns in v1 order, then the new business columns, then `LOAD_TS`.

`[new]` marks a new column, `[wider]` a changed type. Unmarked columns are as in v1 (LLD §2).

### 1.1 `SRM_SOURCE`

**`LFA1`** (suppliers)

| Column | Type | Notes |
|---|---|---|
| `LIFNR` | VARCHAR(10) NOT NULL | `SUP00001`… (PK) |
| `NAME1` | VARCHAR(100) | |
| `LAND1` | VARCHAR(3) | ISO-3 country |
| `REGIO` | VARCHAR(20) | `APAC`/`EMEA`/`AMER`, **messy** (§4 M03) |
| `SUPP_TIER` | NUMBER(1) | 1/2/3 |
| `LEAD_TM_DAYS` | NUMBER(3) | |
| `RELIAB_SCR` | NUMBER(3,2) | 0.70–0.99 |
| `ZTERM` | VARCHAR(20) | payment terms (masked downstream) |
| `EMAIL` | VARCHAR(100) | |
| `ERDAT` `[new]` | DATE | created on (onboarding date; supplier churn) |
| `LOAD_TS` `[new]` | TIMESTAMP_NTZ | |

**`MARA`** (parts): `MATNR` VARCHAR(18) NOT NULL (PK), `MAKTX` VARCHAR(100), `MATKL`
VARCHAR(30) (**messy**), `SUBCAT` VARCHAR(30), `STPRS` NUMBER(12,2) (USD, masked
downstream), `BRGEW` NUMBER(10,3), `CRIT_FLG` BOOLEAN, `LOAD_TS` `[new]`.

**`SOURCING`** (supplier ↔ part, with validity: SAP source list `EORD` semantics)

| Column | Type | Notes |
|---|---|---|
| `SOURCE_ID` | VARCHAR(20) NOT NULL | `SRC000001`… (PK) |
| `LIFNR` | VARCHAR(10) | FK → LFA1 |
| `MATNR` | VARCHAR(18) | FK → MARA |
| `IS_PRIMARY` | BOOLEAN | |
| `CONTRACT_PRICE` | NUMBER(12,2) | in `WAERS` |
| `WAERS` `[new]` | VARCHAR(3) | contract currency |
| `VDATU` `[new]` | DATE | valid from |
| `BDATU` `[new]` | DATE | valid to; `NULL` = open-ended |
| `LOAD_TS` `[new]` | TIMESTAMP_NTZ | |

### 1.2 `WMS_SOURCE`

**`T001W`** (plants): as v1 (`WERKS` VARCHAR(4) NOT NULL, `NAME1`, `LAND1`, `REGION_CD`
(**messy**), `PLANT_TYPE`, `CAPACITY_UNITS`) + `LOAD_TS` `[new]`.

**`MARD`** (inventory snapshots): as v1 (`INV_KEY` VARCHAR(40) NOT NULL, `WERKS`, `MATNR`,
`LABST`, `INSME`, `REORD_PT`, `DAILY_USG`, `SNAP_DT`) + `LOAD_TS` `[new]`.

### 1.3 `ERP_SOURCE`

**`KNA1`** (customers): as v1 (`KUNNR` VARCHAR(10) NOT NULL, `NAME1`, `EMAIL`, `LAND1`,
`REGIO` (**messy**), `KTOKD` (**messy**), `KLIMK` (USD)) + `ERDAT` `[new]` DATE (created
on) + `LOAD_TS` `[new]`.

**`VBAK`** (order headers)

| Column | Type | Notes |
|---|---|---|
| `VBELN` `[wider]` | VARCHAR(12) NOT NULL | `ORD000000001`… (PK) |
| `KUNNR` | VARCHAR(10) | FK → KNA1 |
| `AUDAT` | DATE | order date |
| `ERDAT` | DATE | **ERP's promised date** (conflicts with TMS; never exposed downstream) |
| `GBSTK` | VARCHAR(20) | status, **messy** |
| `PRIO` | VARCHAR(10) | priority, **messy** |
| `AUART` `[new]` | VARCHAR(4) | order type: `OR` standard, `RE` return (§4 E03) |
| `WAERK` `[new]` | VARCHAR(3) | document currency for all line prices of the order |
| `LOAD_TS` `[new]` | TIMESTAMP_NTZ | |

**`VBAP`** (order lines): `LINE_ID` VARCHAR(20) NOT NULL (PK), `VBELN` `[wider]`
VARCHAR(12), `MATNR` VARCHAR(18), `WERKS` VARCHAR(4), `KWMENG` NUMBER(12,3), `QTY_SHIPPED`
NUMBER(12,3), `NETPR` NUMBER(14,2) `[wider]` (in `VBAK.WAERK`, JPY/INR need the width),
`LOAD_TS` `[new]`.

**`TCURR`** `[new table]` (daily FX rates, SAP `TCURR` names)

| Column | Type | Notes |
|---|---|---|
| `KURST` | VARCHAR(4) NOT NULL | rate type, always `M` (average) |
| `FCURR` | VARCHAR(3) NOT NULL | from currency |
| `TCURR` | VARCHAR(3) NOT NULL | to currency, always `USD` |
| `GDATU` | DATE NOT NULL | valid-from date |
| `UKURS` | NUMBER(18,9) | USD per 1 unit of `FCURR` |
| `LOAD_TS` | TIMESTAMP_NTZ | |

PK (`KURST`, `FCURR`, `TCURR`, `GDATU`).

### 1.4 `TMS_SOURCE`

**`VTTK`** (shipments)

| Column | Type | Notes |
|---|---|---|
| `TKNUM` `[wider]` | VARCHAR(12) NOT NULL | `SHP000000001`… (PK) |
| `VBELN` `[wider]` | VARCHAR(12) | FK → VBAK |
| `WERKS` | VARCHAR(4) | origin plant |
| `CARRIER_CD` | VARCHAR(30) `[wider]` | **messy** |
| `DPTBG` | DATE | ship date |
| `PROM_DLV_DT` | DATE | **TMS promised date (authoritative)** |
| `ACT_DLV_DT` | DATE | `NULL` while in transit |
| `FREIGHT_AMT` | NUMBER(14,2) `[wider]` | in `WAERS` |
| `DUTY_AMT` | NUMBER(14,2) `[wider]` | in `WAERS` |
| `HANDLING_AMT` | NUMBER(14,2) `[wider]` | in `WAERS` |
| `SHP_STATUS` | VARCHAR(20) | **messy** |
| `WAERS` `[new]` | VARCHAR(3) | currency of the three amounts |
| `LOAD_TS` `[new]` | TIMESTAMP_NTZ | |

### 1.5 ID formats (all zero-padded, deterministic from the row number `n`)

| Key | Format | Example |
|---|---|---|
| `LIFNR` | `'SUP' ‖ LPAD(n, 5, '0')` | `SUP00001` |
| `MATNR` | `'MAT' ‖ LPAD(n, 6, '0')` | `MAT000001` |
| `WERKS` | `PL01`…`PL12` (fixed, §2.1) | `PL04` |
| `KUNNR` | `'CUST' ‖ LPAD(n, 5, '0')` | `CUST00001` |
| `SOURCE_ID` | `'SRC' ‖ LPAD(n, 6, '0')` | `SRC000001` |
| `VBELN` | `'ORD' ‖ LPAD(n, 9, '0')` | `ORD000000001` |
| `LINE_ID` | `VBELN ‖ '-' ‖ LPAD(line_no, 3, '0')` | `ORD000000001-001` |
| `TKNUM` | `'SHP' ‖ LPAD(n, 9, '0')` | `SHP000000001` |
| `INV_KEY` | `WERKS ‖ '-' ‖ MATNR ‖ '-' ‖ TO_CHAR(SNAP_DT, 'YYYYMMDD')` | `PL01-MAT000010-20260826` |
| Test masters | `TEST0001`… (customers), `TESTV001`… (suppliers), `MAT9999nn` (parts) | §4 M04 |

Numbering is gap-free and in business order: orders are numbered by `(AUDAT, then row)`, so
`ORD000000001` is the oldest order. Nine digits cover up to 999M orders (B13).

---

## 2. Volumes, masters and load order

### 2.1 Masters (fixed; `SCALE_FACTOR` does **not** change them)

| Table | Rows (clean) | Content |
|---|---|---|
| `T001W` | 12 | **exactly the v1 plants**: `PL01` Tokyo Advanced DC (JPN, APAC, DC) · `PL02` Shanghai Mega Manufacturing (CHN, APAC, MFG) · `PL03` Singapore Logistics Gateway (SGP, APAC, HUB) · `PL04` Chennai Heavy Production (IND, APAC, MFG) · `PL05` Frankfurt Central Distribution (DEU, EMEA, DC) · `PL06` Rotterdam Freight Hub (NLD, EMEA, HUB) · `PL07` Munich Precision Facility (DEU, EMEA, MFG) · `PL08` London Regional DC (GBR, EMEA, DC) · `PL09` Chicago Industrial Plant (USA, AMER, MFG) · `PL10` Dallas Distribution Center (USA, AMER, DC) · `PL11` Long Beach Maritime Hub (USA, AMER, HUB) · `PL12` Monterrey Assembly Plant (MEX, AMER, MFG). Capacities as v1 |
| `LFA1` | 150 | tier 1/2/3 = 20/50/30%; region AMER/EMEA/APAC = 35/30/35%; `ERDAT`: 70% before the history start, 30% spread over years 3–10 (onboarding). Reliability 0.70–0.99. `ZTERM` ∈ {`NET30`, `NET60`, `2/10 NET30`, `NET45`, `NET90`} |
| `MARA` | 1,200 | 6 categories × 4 subcategories × 50 parts (list below). ~15% critical. `STPRS` (USD) per category range below |
| `SOURCING` | ~2,400 | every part has, on every date of the history, **exactly one** valid primary row, and 0–2 valid secondary rows. 25% of parts change primary supplier once or twice (the old row gets `BDATU`, a new row starts the next day). Suppliers onboarded late only appear from their `ERDAT`; 15 suppliers are phased out (all their rows end before `END_DATE`). `CONTRACT_PRICE` = `STPRS` × U(0.85, 1.05), in `WAERS` |
| `KNA1` | 2,000 | region AMER/EMEA/APAC = 40/35/25%; segment ENTERPRISE/MIDMARKET/SMB = 15/35/50%; countries per region below; `ERDAT`: 50% before history start, the rest spread over the 10 years, **APAC skewed late** (APAC's order share grows from ~20% in year 1 to ~32% in year 10). `KLIMK` USD by segment: 1M–5M / 200K–1M / 20K–200K |
| `TCURR` | ~23,500 | 9 currencies × business days (Mon–Fri) over the history; ~1% of business days missing (holidays). Random walk around the start rates below, daily step ≤ 0.6%, mean-reverting |

**Categories and subcategories** (the §4 `parts.category` values stay exactly these six):

| `MATKL` | `SUBCAT` (4) | `STPRS` USD | `KWMENG` per line |
|---|---|---|---|
| `ELECTRONICS` | `PASSIVES`, `MICROCONTROLLERS`, `SENSORS`, `CONNECTORS` | 2–400 | 10–2,000 |
| `MECHANICAL` | `GEARBOXES`, `SHAFTS`, `BEARINGS`, `VALVES` | 20–1,500 | 2–300 |
| `RAW_MATERIAL` | `STEEL_RODS`, `ALUMINUM_INGOTS`, `COPPER_WIRE`, `POLYMER_RESIN` | 5–300 | 50–5,000 |
| `PACKAGING` | `SEAL_FILM`, `PALLETS`, `CARTONS`, `FOAM_INSERTS` | 0.5–40 | 100–10,000 |
| `CHEMICAL` | `LUBRICANTS`, `COATINGS`, `ADHESIVES`, `SOLVENTS` | 5–250 | 20–2,000 |
| `FASTENERS` | `RIVETS`, `WASHERS`, `BOLTS`, `SCREWS` | 0.05–5 | 500–20,000 |

**Countries and currencies**

| Region | Customer countries (share within region) | Plant countries |
|---|---|---|
| AMER | USA 60%, CAN 15%, MEX 15%, BRA 10% | USA, MEX |
| EMEA | DEU 30%, GBR 25%, FRA 20%, NLD 15%, ESP 10% | DEU, NLD, GBR |
| APAC | CHN 30%, JPN 25%, IND 25%, SGP 20% | JPN, CHN, SGP, IND |

Currency by country: USA→USD, CAN→CAD, MEX→MXN, BRA→BRL, DEU/FRA/NLD/ESP→EUR, GBR→GBP,
JPN→JPY, CHN→CNY, IND→INR, SGP→SGD. FX start rates (USD per unit): EUR 1.10, GBP 1.30,
JPY 0.0090, CNY 0.145, INR 0.0135, SGD 0.73, CAD 0.76, MXN 0.052, BRL 0.25.

### 2.2 Transactions (× `SCALE_FACTOR`)

| Table | Rows at SF = 1 (clean, before §4 mess) | Rule |
|---|---|---|
| `VBAK` | **650,000 × SF** orders over the history | daily volume per §3.1 |
| `VBAP` | ~3.1 lines/order ⇒ ~2.0M × SF | 1–8 lines, mode 2–3; ENTERPRISE orders have more lines |
| `VTTK` | ~1.1 per shipped order ⇒ ~720K × SF | one shipment per distinct (order, plant) among shipped lines; 5% of those split in two |
| `MARD` | ~2.2M (**fixed**, not × SF) | 3,600 stocked (plant, part) pairs (each plant stocks 300 parts) × (weekly Monday snapshots over 10 years + daily for the last 90 days) |

`SCALE_FACTOR` is a positive number (e.g. `0.01` for a dry run, `1`, `50` for B13). It
multiplies only the order count; lines and shipments follow from the orders. Everything
else is fixed. The generator must run in chunks (one statement per history year per
table) so no single statement grows with SF beyond one year's data (§7.1).

### 2.3 Load order (FK order) and staging

1. `T001W`, `LFA1`, `MARA`, `KNA1`, `TCURR`
2. `SOURCING`
3. `VBAK` → `VBAP` → `VTTK` (per year chunk, in this order)
4. `MARD`
5. **Mess injection** (§4), a separate procedure, after all clean rows exist
6. Self-checks (§7.1)

Every stage starts with `TRUNCATE TABLE` of the tables it writes (idempotent re-run).

---

## 3. Realism

### 3.1 Order volume over time

For each calendar day `d` in the history, the expected order count is

```
w(d)    = growth(d) × season(month(d)) × weekday(d) × shock(d)
orders(d) = round( 650,000 × SF × w(d) / Σ w )        -- exact total via largest remainder or cumulative rounding
growth  = 1.08 ^ (years since history start)          -- 8% a year
season  = Jan 0.95 · Feb 0.85 · Mar 1.00 · Apr 0.98 · May 1.00 · Jun 1.02 ·
          Jul 0.97 · Aug 0.98 · Sep 1.05 · Oct 1.10 · Nov 1.18 · Dec 1.05   (Q4 uplift, Feb dip)
weekday = Mon–Fri 1.00 · Sat 0.35 · Sun 0.15
shock   = 0.80 from 2020-04-01 to 2020-06-30, else 1.00      (demand shock)
```

The exact total may differ from `650,000 × SF` by rounding; the self-check tolerance is
±1%. Each order picks a customer active on that date (`KNA1.ERDAT ≤ AUDAT`), weighted by
segment (ENTERPRISE 6, MIDMARKET 2.5, SMB 1).

### 3.2 Order lifecycle (`L` = the last business date = `END_DATE − 1`)

| Step | Rule |
|---|---|
| Priority `PRIO` | HIGH 15%, NORMAL 70%, LOW 15% |
| Type `AUART` | `OR` 98.5%, `RE` 1.5% (§4 E03) |
| Cancelled | 4% of `OR` orders → `CANCELLED`, all lines `QTY_SHIPPED = 0`, no shipment (except §4 E02) |
| Line plant `WERKS` | a plant in the customer's region 85% (weighted by capacity), otherwise any plant; the line's part is one the plant stocks |
| Processing days | HIGH 1–2, NORMAL 2–4, LOW 3–6; ship date `DPTBG = AUDAT + processing` |
| Not yet shipped | if `DPTBG > L`: order `OPEN`, lines `QTY_SHIPPED = 0`, no shipment |
| Transit | carrier SLA days (§3.4); cross-region +5 days. `PROM_DLV_DT = DPTBG + SLA` |
| Delay | per shipment, on-time with probability `p_ot` (§3.5): `ACT = PROM − U{0,1,2}` (early or on the day); else `ACT = PROM + U{1..6}` |
| In transit | if `ACT > L`: `ACT_DLV_DT = NULL` |
| Order status | all its shipments delivered → `DELIVERED`; at least one shipped but not delivered → `SHIPPED` |
| `SHP_STATUS` | `DELIVERED` if delivered on or before the promise; `DELAYED` if delivered late **or** still in transit past the promise; `IN_TRANSIT` otherwise (v1 semantics kept) |
| ERP promised date `VBAK.ERDAT` | equals the first shipment's `PROM_DLV_DT` on 80% of shipped orders; on 20% it is 2–7 days **earlier** (ERP quotes optimistic dates). For unshipped orders: `AUDAT` + 7–14 days |

### 3.3 Quantities, prices and fill

- `KWMENG` per the category range (§2.1), log-uniform, rounded to a whole unit.
- `NETPR` = `STPRS` × U(1.15, 1.60), converted to the order currency `WAERK` at the order
  date's rate, rounded to 2 dp.
- **Fill**: on `SHIPPED`/`DELIVERED` orders, a line is short-shipped with probability
  `p_short` = 0.20 × category factor (ELECTRONICS 0.8, MECHANICAL 1.0, RAW_MATERIAL 0.9,
  PACKAGING 1.2, CHEMICAL 0.9, FASTENERS 1.2); in **2021** use 0.27 × factor (supply
  crisis). A short line ships `KWMENG × U(0.40, 0.95)`; other lines ship exactly `KWMENG`.
  Expected fill ≈ 1 − 0.325 × p_short: **~0.935**, 2021 **~0.912**.

### 3.4 Carriers (canonical codes; churn)

| `CARRIER_CD` | Active | Regions served (preference) | SLA days | On-time offset |
|---|---|---|---|---|
| `DHL_EXPRESS` | whole history | all | 3 | +0.02 |
| `FEDEX_FREIGHT` | whole history | AMER | 4 | +0.01 |
| `MAERSK_LOGISTICS` | whole history | APAC, cross-region | 9 | −0.03 |
| `KUEHNE_NAGEL` | whole history | EMEA | 5 | 0.00 |
| `DB_SCHENKER` | whole history | EMEA | 4 | 0.00 |
| `UPS_SUPPLY_CHAIN` | until 2022-06-30 (exits) | AMER | 4 | +0.01 |
| `XPO_LOGISTICS` | until 2021-12-31 (exits) | AMER | 5 | −0.02 |
| `CEVA_LOGISTICS` | from 2019-01-01 | APAC | 6 | −0.01 |
| `FLEXPORT` | from 2022-07-01 | AMER, cross-region | 7 | +0.01 |

Each shipment picks an active carrier serving its origin region (cross-region shipments
pick `MAERSK_LOGISTICS`, `DHL_EXPRESS` or, when active, `FLEXPORT`).

### 3.5 On-time probability `p_ot` (drives OTD)

`p_ot = base(year) + carrier offset + priority offset (HIGH +0.02, LOW −0.01) + plant offset (±0.015, fixed per plant)`, clamped to [0.70, 0.97].

| Year of `DPTBG` | 2016–2019 | 2020 | 2021 | 2022 | 2023–2026 |
|---|---|---|---|---|---|
| `base` | 0.872 | 0.865 | 0.855 | 0.867 | 0.870 |

The recent-year base is set a little lower on purpose: late shipments are more likely to
still be in transit at `L`, so the observed OTD of the last few weeks runs ~0.5 pt above
`p_ot`.

### 3.6 Costs (TMS, in `VTTK.WAERS`)

Computed in USD, then converted to `WAERS` at the ship date's rate:
- `freight_usd` = base by carrier (150–450) × lane factor (domestic 0.7, in-region 1.0,
  cross-region 1.8) × weight factor U(0.6, 1.6) × fuel index (1.00; 2021-07 → 2022-12 ramps
  to 1.35 and back to 1.10 by 2023-12)
- `duty_usd` = 0 for domestic (origin plant country = customer country), else 8–22% of freight
- `handling_usd` = 40–120
- Expected average landed cost ≈ **USD 450–600** per year (contract §3 range 150–900).
- `WAERS`: USD for US-origin shipments; for other origins, the plant's local currency with
  probability 0.55, else USD (⇒ ~40% non-USD).

### 3.7 Inventory

- Stocked pairs: each plant stocks 300 parts (hash-picked, weighted to the categories the
  plant ships). Daily usage `DAILY_USG` per pair: 5–200 units/day (log-uniform), seasonal
  (× `season(month)`), with ±15% weekly noise.
- On hand `LABST` = `DAILY_USG` × cover days; cover days per pair U(12, 48), +20% in Sep–Oct
  (Q4 build), ±10% noise. `INSME` = 0–10% of `LABST`. `REORD_PT` = `DAILY_USG` × U(7, 14).
- Snapshots: every Monday over the history, plus every day of the last 90 days up to `L`.
  Expected DOI ≈ **~30** over a year, **~35** at a late-September snapshot (range 15–45).
- Zero-usage pairs (§4 E06) keep a positive on-hand of U(50, 500) units (obsolete stock).

### 3.8 Load timestamps

`LOAD_TS` = the row's business date + 1 day, at 02:00 plus a hash-based 0–180 minutes (the
nightly batch). **No `LOAD_TS` may be later than `END_DATE` 05:00:00**; defects that shift
`LOAD_TS` (§4 M01, M06) pick only rows old enough to stay under that cap.

| Table | Business date |
|---|---|
| VBAK | the last status change: `AUDAT` (OPEN, CANCELLED), the first `DPTBG` (SHIPPED), the last `ACT_DLV_DT` (DELIVERED) |
| VBAP | its order's business date |
| VTTK | `COALESCE(ACT_DLV_DT, DPTBG)` (the row is re-sent when delivered) |
| MARD | `SNAP_DT` |
| TCURR | `GDATU` |
| SOURCING | `VDATU` (or the history start, if earlier) |
| Masters | `ERDAT`, or the history start if earlier (T001W, MARA: the history start) |

---

## 4. Mess catalogue

Injected by a **separate** procedure (§7.1) after the clean load, so clean vs messy is easy
to check. **Rate** = affected rows ÷ the stated base population (the clean rows, before
injection). **Tolerance**: ±10% relative or ±0.05 percentage points, whichever is larger.
Picks use the §6 hash recipe with the defect code as the attribute (e.g. `'M01'`).

"CONFORMED rule" is what CoCo's B08c dynamic tables do. It's here so C08 injects exactly
what the rules repair, and C10 checks for it. "Moves a metric if uncleaned" shows why it
matters.

### 4.1 Repairable defects (present in `SOURCE`, **absent** in `CONFORMED`)

| Code | Defect | Table(s) · base · rate | How it's injected | CONFORMED rule | Moves a metric if uncleaned |
|---|---|---|---|---|---|
| **M01** | Re-sent duplicates | VBAK 2% · VBAP 1.5% · VTTK 3% · MARD 0.5% · KNA1 1% of rows (rows with business date ≤ `L − 5`) | an identical copy of the row with `LOAD_TS` + 1–5 days | keep one row per key: the latest `LOAD_TS` | OTD, fill, landed cost, DOI (double counting) |
| **M02** | Status-update versions | VBAK: 10% of `SHIPPED`/`DELIVERED` orders · VTTK: 8% of delivered shipments | an **older** copy with the earlier state (`GBSTK = 'OPEN'`; or `SHP_STATUS = 'IN_TRANSIT'`, `ACT_DLV_DT = NULL`) and an earlier `LOAD_TS` (the final row keeps the normal one) | same as M01: the latest `LOAD_TS` wins | OTD, fill |
| **M03** | Code variants | see §4.3 · rates per domain there | replace the canonical value with a listed variant | `canonical = CODE_MAP[domain, UPPER(TRIM(value))]`; the §4 contract values result | every breakdown by region, status, carrier, category, priority, segment |
| **M04** | Test / dummy records | KNA1: +5 customers `TEST0001`–`TEST0005` (names `TEST CUSTOMER 1`…, `DUMMY ACCOUNT`; emails `@example.com`), carrying 0.3% of orders (with lines, shipments) · LFA1: +2 suppliers `TESTV001`–`TESTV002` (`TEST VENDOR`) with 1 sourcing row each · MARA: +4 parts `MAT999901`–`MAT999904` (`DO NOT USE - TEST PART`), on 0.1% of lines | extra rows | a master is test if its ID starts `TEST` or `MAT9999`, or `UPPER(name)` matches `^(TEST|DUMMY)\b` or contains `DO NOT USE`. Drop test masters and all their dependents (orders → lines, shipments; test parts → lines, sourcing, inventory) | all four |
| **M05** | Non-USD amounts | VBAK.WAERK ≠ USD on ~38% of orders · VTTK.WAERS ≠ USD on ~40% of shipments · SOURCING.WAERS ≠ USD on ~30% | **not injected**; set at generation: VBAK.WAERK = the customer's local currency for 50% of non-US customers (hash per customer), else USD; VTTK per §3.6; SOURCING: the supplier country's currency for 30% of rows. The self-check **reports** these rates (no pass/fail) and **gates** that every non-USD amount has a `TCURR` rate on or before its date | `amount_usd = amount × UKURS` of the `TCURR` row with the latest `GDATU ≤ business date` (VBAP → `AUDAT`, VTTK → `DPTBG`, SOURCING → `VDATU`); USD → × 1 | landed cost, revenue |
| **M06** | Late-arriving rows | VBAP 1% · VTTK 1% of rows with business date ≤ `L − 30` | `LOAD_TS` = business date + 3–30 days | none needed (incremental refresh picks them up); freshness is measured on `LOAD_TS` | none after refresh |
| **M07** | ID whitespace / case | VBAP.MATNR 0.5% (`' MAT000123'`, `'mat000123'`) · VTTK.VBELN 0.3% (trailing space) · VBAP.VBELN 0.2% (lower case) | as shown | `UPPER(TRIM(id))` on every ID before joins | fill (lines lose their part/plant/order) |

### 4.2 Business-rule edge cases (the rule is applied; the row may stay visible)

| Code | Case | Table · base · rate | How it's injected | CONFORMED / metric rule | Stays visible? |
|---|---|---|---|---|---|
| **E01** | Missing promised date | VTTK · 0.8% of delivered shipments | `PROM_DLV_DT = NULL` | **excluded from OTD numerator and denominator** (CR-006) | yes, `promised_delivery_date` NULL |
| **E02** | Cancelled after shipping | VBAK · 0.5% of `DELIVERED` orders | `GBSTK = 'CANCELLED'`; lines and shipment kept | shipment counts in OTD and landed cost (the movement happened); lines excluded from fill by CR-005 | yes |
| **E03** | Return orders | VBAK · 1.5% of orders (`AUART = 'RE'`); 60% of them have a return shipment | `AUART = 'RE'`, positive quantities | **out of scope**: the order, its lines and shipments are excluded from `CONFORMED` | no |
| **E04** | Over-shipment | VBAP · 1% of shipped lines | `QTY_SHIPPED = KWMENG × U(1.05, 1.20)`, rounded | `quantity_shipped = LEAST(qty_shipped, qty_ordered)`; flag `OVERSHIP_CAPPED` | yes, capped |
| **E05** | Negative on-hand | MARD · 0.3% of rows | `LABST = −U(1, 50)` | `quantity_on_hand = GREATEST(labst, 0)`; flag `NEG_ON_HAND_ZEROED` | yes, as 0 |
| **E06** | Zero daily usage | MARD · 2% of stocked pairs (all their snapshots) | `DAILY_USG = 0` (obsolete stock) | kept; DOI is a ratio of averages, so a group whose usage is all zero returns `NULL` | yes |
| **E07a** | NULL duty | VTTK · 60% of **domestic** shipments | `DUTY_AMT = NULL` | `duty_cost = COALESCE(duty, 0)`; flag `DUTY_DEFAULTED` | yes, as 0 |
| **E07b** | NULL handling | VTTK · 1% of shipments | `HANDLING_AMT = NULL` | `handling_cost = COALESCE(handling, 0)`; flag `HANDLING_DEFAULTED` | yes, as 0 |
| **E07c** | NULL freight | VTTK · 0.2% of shipments | `FREIGHT_AMT = NULL` | cost unknown: **all three cost columns `NULL`** (excluded from avg landed cost; OTD unaffected); flag `COST_UNKNOWN` | yes, costs NULL |
| **E08** | Cost outliers | VTTK · 0.1% of shipments, picked among those with `freight_usd ≥ 300` (so every outlier exceeds USD 30,000) | `FREIGHT_AMT × 100` (decimal shift) | if `freight_usd + duty_usd + handling_usd > 25,000` → all three cost columns `NULL`; flag `COST_OUTLIER`. (Normal shipments stay below USD 10,000 by §3.6) | yes, costs NULL |
| **E09a** | Orphan lines | VBAP · 0.2% of lines | `VBELN` of an order that doesn't exist (`ORD9…`) | dropped | no |
| **E09b** | Orphan shipments | VTTK · 0.2% of shipments | same | dropped | no |
| **E10** | ERP/TMS date conflict | VBAK vs VTTK · 20% of shipped orders | §3.2 (not injected) | **preserved**; `ERDAT` never reaches `CONFORMED` or `GOVERNED` | ERDAT no; TMS date yes |
| **E11** | Two valid primaries | SOURCING · 1% of parts | a second `IS_PRIMARY = TRUE` row overlapping the valid one | the primary with the latest `VDATU` wins; the other becomes secondary. Resolved per date in `GOVERNED.V_SOURCING` among the rows valid that day, so a replacement that starts later, nests inside, or has ended leaves exactly one primary (`CONFORMED` keeps the source flag + `PRIMARY_SUPERSEDED`; CoCo, 2026-10-01) | yes, as secondary |
| **E12** | Future-dated orders | VBAK · 0.02% of orders | `AUDAT = LOAD_TS::DATE + 1..400` (clock error; `LOAD_TS` unchanged), with their lines; no shipments | excluded: an order dated after it was loaded (`AUDAT > LOAD_TS::DATE`). Deterministic, so it suits an incremental dynamic table | no |

`CONFORMED` rows carry a `dq_flags ARRAY` of the flag names above (empty when clean), so
C10's DMFs and `SP_DATA_HEALTH` can count what was repaired.

### 4.3 Code map (M03): the only variants C08 may inject

The map is keyed on `UPPER(TRIM(raw))`. CoCo loads it into `CONFORMED.CODE_MAP (DOMAIN,
VARIANT, CANONICAL)` at B08c. Canonical values map to themselves. Injection rate per
domain in brackets; pick the variant uniformly from its list.

| Domain (columns) [rate] | Canonical ← raw variants (as they appear in `SOURCE`) |
|---|---|
| `REGION` (LFA1.REGIO, KNA1.REGIO [8% of rows]; T001W.REGION_CD [`PL03` and `PL11` only]) | `APAC` ← `Apac`, `apac `, `ASIA-PAC`, `Asia Pacific` · `EMEA` ← `emea`, ` EMEA`, `Europe`, `EU` · `AMER` ← `Amer`, `NA`, `North America`, `Americas` |
| `ORDER_STATUS` (VBAK.GBSTK [3%]) | `OPEN` ← `Open`, `OPN` · `SHIPPED` ← `Shipped`, `SHP` · `DELIVERED` ← `Delivered`, `DLV`, `delivered ` · `CANCELLED` ← `Cancelled`, `CANCELED`, `CNL` |
| `PRIORITY` (VBAK.PRIO [2%]) | `HIGH` ← `High`, `H`, `URGENT` · `NORMAL` ← `Normal`, `MED`, `MEDIUM` · `LOW` ← `Low`, `L` |
| `SHIPMENT_STATUS` (VTTK.SHP_STATUS [3%]) | `IN_TRANSIT` ← `In Transit`, `IN-TRANSIT`, `INTRANSIT` · `DELIVERED` ← `Delivered`, `DLV` · `DELAYED` ← `Delayed`, `LATE` |
| `CARRIER` (VTTK.CARRIER_CD [6%]) | `DHL_EXPRESS` ← `DHL`, `DHL Express`, `dhl_express` · `FEDEX_FREIGHT` ← `FedEx`, `FEDEX FREIGHT` · `MAERSK_LOGISTICS` ← `Maersk`, `MAERSK` · `KUEHNE_NAGEL` ← `K+N`, `Kuehne+Nagel`, `KUEHNE + NAGEL` · `DB_SCHENKER` ← `DB Schenker`, `SCHENKER` · `UPS_SUPPLY_CHAIN` ← `UPS`, `UPS SCS` · `XPO_LOGISTICS` ← `XPO` · `CEVA_LOGISTICS` ← `CEVA` · `FLEXPORT` ← `Flexport` |
| `CATEGORY` (MARA.MATKL [5%]) | `ELECTRONICS` ← `Electronics`, `ELECTRONIC` · `MECHANICAL` ← `Mechanical`, `MECH` · `RAW_MATERIAL` ← `RAW MATERIAL`, `Raw-Material`, `RAW_MATERIALS` · `PACKAGING` ← `Packaging`, `PKG` · `CHEMICAL` ← `Chemical`, `CHEMICALS` · `FASTENERS` ← `Fasteners `, `FASTENER` |
| `SEGMENT` (KNA1.KTOKD [3%]) | `ENTERPRISE` ← `Enterprise`, `ENT` · `MIDMARKET` ← `MID-MARKET`, `Mid Market`, `MM` · `SMB` ← `Small Business`, `smb` |

`PLANT_TYPE` and `SUPP_TIER` are never messy. An unmapped value in `CONFORMED` is a bug;
C10 has a check that counts values outside the §4 contract sets.

---

## 5. Metric and time rules (CR-006)

### 5.1 What "clean" means: the `CONFORMED` contract

A `CONFORMED` row is **in scope, unique, standardized and in USD**:
1. one row per business key (M01/M02: latest `LOAD_TS`)
2. no test/dummy masters and none of their dependents (M04)
3. no return orders or their lines and shipments (E03), no orphans (E09), no future-dated
   orders (E12)
4. every code is a §4 contract value (M03); IDs are `UPPER(TRIM())` (M07)
5. every amount is USD (M05); the source currency is kept as `source_currency`
6. edge-case rules E01–E08, E11 applied, each recorded in `dq_flags`
7. `VBAK.ERDAT` is not carried

`CONFORMED` table names (B08c; C10 attaches DMFs to them): `CONFORMED.SUPPLIER`, `PART`,
`SOURCING`, `PLANT`, `INVENTORY`, `CUSTOMER`, `SALES_ORDER`, `ORDER_LINE`, `SHIPMENT`,
`FX_RATE`, `CODE_MAP`. Columns: the §7 governed-view column names in §7 order, then
`source_currency` (money-bearing tables), `valid_from`/`valid_to` (SOURCING), `dq_flags`
(ARRAY) and `load_ts`. **`GOVERNED.V_SOURCING` shows only rows valid on `CURRENT_DATE()`.**

### 5.2 Time rule (one rule for the app and the agent)

| Rule | Definition |
|---|---|
| **Anchor** | `CURRENT_DATE()` at query time. "Last quarter", "this year" etc. are relative to it |
| **As-of date (shown)** | the latest business date loaded: `MAX(ship_date)` of `V_SHIPMENT`, reported by `SP_DATA_HEALTH` (§7.2) and shown by the app next to every metric |
| **Default window** (the question names no period) | **trailing 12 months**: `date > DATEADD(month, -12, CURRENT_DATE()) AND date <= CURRENT_DATE()` |
| Window date per metric | `on_time_delivery_rate`, `avg_landed_cost` → `shipments.ship_date` · `fill_rate` → `orders.order_date` |
| **DOI** (a stock metric) | the **latest snapshot**: `inventory.snapshot_date = (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY)`. With a period named, DOI averages the snapshots inside it |
| Explicit period | replaces the default window; the answer states the period used |
| "All time" | only when asked; no filter |

Verified patterns (live, 2026-09-29, on the v1 view):

```sql
-- Flow metric, default window
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  METRICS shipments.on_time_delivery_rate, shipments.avg_landed_cost
  WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
    AND shipments.ship_date <= CURRENT_DATE());

-- Fill rate, default window (filter on the related orders table)
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  METRICS order_lines.fill_rate
  WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE())
    AND orders.order_date <= CURRENT_DATE());

-- DOI, latest snapshot
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  DIMENSIONS plants.plant_region
  METRICS inventory.days_of_inventory
  WHERE inventory.snapshot_date =
        (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY));
```

A query can't mix a shipment window and an order window in one `WHERE` for different
metrics; ask for them separately (the app already queries one metric at a time).

### 5.3 Metric rules after CR-006

| Metric | Formula (semantic view, B09) | Edge-case rules |
|---|---|---|
| `shipments.on_time_delivery_rate` | `COUNT_IF(actual <= promised) / NULLIFZERO(COUNT_IF(actual IS NOT NULL AND promised IS NOT NULL))` | in-transit excluded; **missing promised date excluded** (E01); cancelled-after-shipping included (E02) |
| `order_lines.fill_rate` | `SUM(shipped on SHIPPED/DELIVERED orders) / NULLIFZERO(SUM(ordered on SHIPPED/DELIVERED orders))` (CR-005) | over-shipment capped per line (E04); returns out of scope (E03) |
| `inventory.days_of_inventory` | `AVG(quantity_on_hand) / NULLIFZERO(AVG(daily_usage))` | negative on-hand = 0 (E05); all-zero-usage groups → `NULL` (E06); latest snapshot by default |
| `shipments.avg_landed_cost` | `AVG(freight_cost + duty_cost + handling_cost)`, USD | NULL duty/handling = 0 (E07a/b); unknown cost and outliers excluded (E07c, E08) |

### 5.4 Targets that must hold after cleaning (checked at B08c)

| Metric | §3 range | Each calendar year (complete years) | Default window | 10-year |
|---|---|---|---|---|
| OTD | 0.84–0.90 | 0.845–0.895 | 0.855–0.885 | 0.855–0.885 |
| Fill rate | 0.90–0.95 | 0.905–0.945 | 0.915–0.945 | 0.915–0.945 |
| DOI | 15–45 | 18–42 (average of the year's snapshots) | latest snapshot 20–40 | — |
| Avg landed cost (USD) | 150–900 | 300–750 | 400–700 | 400–700 |

Also: every plant has shipments in every year; every §4 dimension value occurs; OTD by
plant region, and fill rate by category, differ by region/category (none is exactly 1.000).
The §8 naive OTD (raw `SOURCE`, ERP date, same window) is **at least 8 points below** the
governed OTD. Expected: ~0.68–0.74 vs ~0.87 (on the 20% conflicting orders the ERP date is
2–7 days early, so almost all of them count as late).

---

## 6. Seed, determinism and idempotency

**Rule 1 — hash-based randomness only.** A uniform number in [0, 1] for row `n`, attribute
`attr`, and seed `s`:

```sql
BITAND(HASH(:seed, 'VBAK', n, 'prio'), 4294967295) / 4294967295.0     -- u in [0, 1]
```

- Always pass the same types in the same order: `seed` NUMBER, the table name as a string
  literal, `n` NUMBER, `attr` a string literal. `HASH(10)` and `HASH('10')` differ.
- Derive **every** attribute from `(seed, table, n, attr)`: never from `RANDOM()`, never
  from row order, and never from `SEQ8()` directly.
- Child rows hash on the parent key plus their own number, e.g. `HASH(:seed, 'VBAP',
  order_n, line_no, 'qty')`, so an order's lines don't change when SF changes other orders.
- Weighted pick: compare `u` with cumulative weights (`CASE WHEN u < 0.15 THEN 'HIGH' WHEN
  u < 0.85 THEN 'NORMAL' ELSE 'LOW' END`).
- Normal-like values: the average of 4 uniforms, or a triangular draw `(u1 + u2) / 2`.
  Log-uniform: `EXP(LN(lo) + u × (LN(hi) − LN(lo)))`.

**Rule 2 — gap-free numbering.** `SEQ*` values can have gaps. Use
`ROW_NUMBER() OVER (ORDER BY SEQ8())` over `GENERATOR`, or `ROW_NUMBER()` over a business
order (e.g. orders by `AUDAT` then per-day number).

**Rule 3 — the only inputs** are `SEED` (default `20260929`), `SCALE_FACTOR` and `END_DATE`.
No `CURRENT_DATE()`/`CURRENT_TIMESTAMP()` inside the generator (`END_DATE` is passed in;
`LOAD_TS` derives from business dates). Same inputs ⇒ the same rows, byte for byte.

**Rule 4 — idempotent.** Each stage `TRUNCATE`s what it writes, then inserts. Re-running any
stage, or all of them, gives identical tables.

**Verified determinism** (live, 2026-09-29): this query gave `HASH_AGG`
`5241903297775745443` twice, once on `COMPUTE_WH` and once on `FORGE_WH`, with the result
cache off:

```sql
WITH ids AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ8()) AS n
             FROM TABLE(GENERATOR(ROWCOUNT => 5000000))),
u AS (SELECT n,
        BITAND(HASH(20260929, 'VBAK', n, 'date'), 4294967295) / 4294967295.0 AS u_date,
        BITAND(HASH(20260929, 'VBAK', n, 'prio'), 4294967295) / 4294967295.0 AS u_prio
      FROM ids)
SELECT COUNT(*), HASH_AGG(n, 'ORD' || LPAD(n, 9, '0'),
         DATEADD(day, -FLOOR(u_date * 3653)::INT, '2026-09-29'::DATE),
         CASE WHEN u_prio < 0.15 THEN 'HIGH' WHEN u_prio < 0.85 THEN 'NORMAL' ELSE 'LOW' END)
FROM u;
```

---

## 7. Interfaces

All new objects live in `SUPPLY_CHAIN_FORGE`. CoCo creates the schemas `CONFORMED` and
`OPS` at B08c (before running C08). `OPS` is private: `FORGE_ADMIN` and `ACCOUNTADMIN`
only; persona roles get nothing in it.

### 7.1 Data generator (C08, `data_gen/`)

Procedures, `LANGUAGE SQL`, **`EXECUTE AS CALLER`**, created in `SUPPLY_CHAIN_FORGE.OPS`.
Each one starts with `EXECUTE IMMEDIATE 'USE DATABASE ' || :TARGET_DB;` and then uses
**schema-qualified** names (`ERP_SOURCE.VBAK`), so B13 can point them at a clone (verified
live). CoCo calls them as `ACCOUNTADMIN` (the source-table owner).

| Procedure | Signature | Returns |
|---|---|---|
| `OPS.SP_GENERATE_DATA` | `(TARGET_DB VARCHAR, SCALE_FACTOR FLOAT, SEED NUMBER, END_DATE DATE)` | VARIANT: `{"target_db", "scale_factor", "seed", "end_date", "rows": {"<TABLE>": n, ...}, "elapsed_s", "stages": [{"stage", "table", "chunk", "rows", "elapsed_s"}]}` |
| `OPS.SP_INJECT_MESS` | `(TARGET_DB VARCHAR, SEED NUMBER, END_DATE DATE)` | VARIANT: `{"injected": {"M01": {"VBAK": n, ...}, ..., "E12": {...}}, "elapsed_s"}` |
| `OPS.SP_GEN_SELF_CHECKS` | `(TARGET_DB VARCHAR)` | `TABLE (CHECK_ID VARCHAR, TABLE_NAME VARCHAR, EXPECTED FLOAT, ACTUAL FLOAT, TOLERANCE FLOAT, PASSED BOOLEAN, DETAIL VARCHAR)` |

- `SP_GENERATE_DATA` runs §2.3 stages 1–4 and writes only clean rows. Transactional tables
  are written **one history year per statement**, so no single statement grows past one
  year of data at any SF.
- Each stage appends a row to `OPS.GEN_LOG (RUN_ID, TARGET_DB, STAGE, TABLE_NAME, CHUNK,
  ROWS_WRITTEN, STARTED_AT, ENDED_AT, PARAMS VARIANT)`, created by your script if it
  doesn't exist. So a long run can be followed from another session.
- Self-checks cover at least: row counts per table vs §2 (±1%); each §4 rate vs its target
  (§4 tolerance); the E10 conflict rate (20% ± 2 pp); every plant has shipments every year;
  `COUNT(*) = COUNT(DISTINCT key)` in the clean load before injection; and a table checksum
  (`HASH_AGG(*)`) per table, which must repeat on a second run.
- File layout is yours. The `CALL`s CoCo runs go in one driver file (e.g.
  `data_gen/99_run.sql`) with the parameters in its header. This replaces the "session
  variables in `00_params.sql`" idea in CLAUDE_TASKS C08: session variables don't survive
  between CoCo's calls (§8).

### 7.1a Nightly day-append (added 2026-09-30, "freshness fix 2")

Why: `LOAD_TS` stops at `END_DATE` 05:00, so without new data the daily entities read `WARN`
36 h later and `FAIL` after 72 h (the video on 2 Oct, the judges after 4 Oct). The
trailing-12-month window (§5.2) also moves every day, so without new days it loses its last
days of data. A nightly feed fixes both, and it's what a real ERP/TMS/WMS does.

| Procedure | Signature | Returns |
|---|---|---|
| `OPS.SP_APPEND_DAY` | `(TARGET_DB VARCHAR, SCALE_FACTOR FLOAT, SEED NUMBER, NEW_END_DATE DATE)` | VARIANT: `{"target_db", "from_end_date", "new_end_date", "days_added", "rows": {"<TABLE>": n, ...}, "injected": {...}, "elapsed_s"}` |

Rules (the same generator, one day at a time):
1. **Current end**: `from_end_date` = `MAX(LOAD_TS)::DATE` over `VBAK`, the day the last
   nightly batch ran. If `NEW_END_DATE <= from_end_date`, return `days_added: 0` and write
   nothing (idempotent, safe to re-run). Otherwise add every missing day in order, one
   business day per loop (catch-up after a missed night, or after the B08m cutover, which
   loads with `END_DATE '2026-09-30'`).
2. **New business day `D`**: for each new end date `e` (from `from_end_date + 1` to
   `NEW_END_DATE`), `D = e − 1`, the new `L`. New orders with `AUDAT = D` and their lines, at the
   §3.1 volume for that date × `SCALE_FACTOR`, with IDs continuing after the current maximum.
   Same hash recipe as §6, keyed on `(SEED, table, n)`, so a given day always produces the
   same rows.
3. **Lifecycle updates, as new row versions (the M02 pattern)**, never `UPDATE`:
   - orders that ship on `D`: a new VBAK row with the new `GBSTK`, the line quantities
     shipped, and the new VTTK shipment rows
   - shipments delivered on `D`: a new VTTK row with `ACT_DLV_DT` and the new `SHP_STATUS`
   - orders whose shipments are all delivered: a new VBAK row with `GBSTK = 'DELIVERED'`

   Follow §3.2 exactly, as the full generator would have for `END_DATE = D + 1`. The
   `CONFORMED` "latest `LOAD_TS` wins" rule (§5.1) then shows the current state.
4. **Inventory**: a MARD snapshot for `D` (a daily snapshot, §3.7), from the pair's previous
   snapshot plus the §3.7 noise.
5. **Mess at the §4 rates** on the new rows only (M01, M03, E01, E04, E09 and so on), so the
   DMFs keep seeing realistic defects. Rows are never older than the rules allow.
6. **`LOAD_TS`** = `D + 1` at 02:00 plus 0–180 hash minutes (§3.8). The cap becomes
   `NEW_END_DATE` 05:00. Masters (`LFA1`, `MARA`, `T001W`, `SOURCING`, `KNA1`, `TCURR`) are
   unchanged, except one `TCURR` rate row per currency for `D`.
7. Runs as `ACCOUNTADMIN` (the owner of the source tables), `EXECUTE AS CALLER`, schema
   qualified, with a `GEN_LOG` row per stage like `SP_GENERATE_DATA`. One day at SF 1 is
   ~180 orders, so each day takes seconds on XS.
8. **Self-check**: `OPS.SP_GEN_SELF_CHECKS` still passes after a day-append (row counts
   within ±1% of §2 for the longer history; one primary sourcing row per part; no
   `LOAD_TS` above the cap). Plus an append check: calling
   `SP_APPEND_DAY` twice with the same `NEW_END_DATE` adds nothing the second time.

CoCo schedules it (B12a): a serverless task at 05:30 UTC calls
`SP_APPEND_DAY('SUPPLY_CHAIN_FORGE', 1, 20260929, CURRENT_DATE())`, with the root task's
`SUSPEND_TASK_AFTER_NUM_FAILURES`, in `sql/` (re-runnable). `CONFORMED` refreshes
incrementally, and the DMFs run on change.

### 7.2 `SEMANTIC.SP_DATA_HEALTH` (C10, `quality/`; the agent's custom tool)

```sql
SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH(ENTITY VARCHAR) RETURNS VARIANT
  LANGUAGE SQL  EXECUTE AS OWNER   -- owner FORGE_ADMIN; USAGE to FORGE_ADMIN + the 3 persona roles
```

- `ENTITY`: one of `suppliers`, `parts`, `sourcing`, `plants`, `inventory`, `customers`,
  `orders`, `order_lines`, `shipments` (the semantic-view table names), or `ALL`. Case-
  insensitive. Anything else returns `status = "ERROR"` with a message, and doesn't raise.
- Reads: `SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS` (latest result per DMF
  association), plus `COUNT(*)`, `MAX(load_ts)` and `MAX(<business date>)` on the
  `CONFORMED` table. **Never** returns row values or any masked column; counts and rates
  only. Output stays under 16 KB.
- Returns exactly this shape (keys always present; `null` where unknown):

```json
{
  "entity": "shipments",
  "generated_at": "2026-09-30T08:00:00Z",
  "as_of_date": "2026-09-29",
  "status": "OK | WARN | FAIL | UNKNOWN | ERROR",
  "summary": "Shipments are fresh (loaded 6 h ago). 2 edge cases handled; no repairable defects left.",
  "entities": [
    {
      "entity": "shipments",
      "table": "SUPPLY_CHAIN_FORGE.CONFORMED.SHIPMENT",
      "row_count": 712345,
      "latest_business_date": "2026-09-29",
      "latest_load_ts": "2026-09-30T02:41:00",
      "freshness_hours": 5.3,
      "freshness_status": "OK",
      "status": "OK",
      "checks": [
        {
          "check": "missing_promised_date",
          "code": "E01",
          "layer": "SOURCE",
          "dmf": "SNOWFLAKE.CORE.NULL_COUNT",
          "table": "SUPPLY_CHAIN_FORGE.TMS_SOURCE.VTTK",
          "columns": ["PROM_DLV_DT"],
          "value": 5712,
          "rate": 0.0079,
          "threshold_rate": 0.016,
          "status": "OK",
          "handled_by": "Excluded from on-time delivery",
          "measured_at": "2026-09-30T06:00:00Z"
        }
      ]
    }
  ]
}
```

Status rules:
- **Freshness** (revised 2026-09-30 after B12, "freshness fix 1"): only for the **daily
  entities** `orders`, `order_lines`, `shipments`, `inventory`: `OK` if `latest_load_ts` is
  within 36 h of `generated_at`, `WARN` 36–72 h, `FAIL` over 72 h.
  **Reference entities** (`suppliers`, `parts`, `sourcing`, `plants`, `customers`) change
  rarely by nature (parts and plants were loaded in 2016), so their `freshness_status` is
  **`REFERENCE`**: never judged on age, and it doesn't count toward `status`. They still
  report `latest_load_ts` and `freshness_hours`, and all their checks still run. With the
  nightly day-append (§7.1a) the daily entities stay `OK`; without it, they read `WARN`/`FAIL`
  a few days after the load, and that's true, not a bug.
- **SOURCE edge-case checks** (E-codes): `OK` if `rate ≤ threshold_rate` (twice the §4 rate),
  else `WARN`.
- **SOURCE repairable checks** (M-codes): always `OK`. They are *expected* in raw data; the
  check shows the repair is needed.
- **CONFORMED repairable checks**: must be 0, else `FAIL`.
- `UNKNOWN` if a DMF has no result yet.
- The entity's `status` = the worst of its checks and freshness; the top-level `status` =
  the worst entity. `as_of_date` = `latest_business_date` for one entity; for `ALL`, the
  shipments' date (§5.2).
- `ALL` returns all 9 entities, in the order above.

**DMFs** (C10): custom DMFs in `SUPPLY_CHAIN_FORGE.OPS`, named `DMF_<WHAT>_COUNT`, returning
`NUMBER`. `DMF_OVERSHIP_COUNT` (the name the app expects) and `DMF_ORPHAN_ORDER_LINES` are
kept. **Layering**: attach each check to both `SOURCE` (where the §4 defects are expected
to be non-zero) and `CONFORMED` (where repairable ones must be 0). The app's Data health
screen (`_QUALITY_EXPECT_ZERO` in `forge_data.py`) must judge by layer (`table_schema`):
zero is expected only in `CONFORMED`. That's a C09/C10 change for Claude Code. Minimum set:

| Check | Code | SOURCE table | CONFORMED table | DMF |
|---|---|---|---|---|
| duplicate keys | M01/M02 | VBAK.VBELN, VBAP.LINE_ID, VTTK.TKNUM, MARD.INV_KEY, KNA1.KUNNR | same keys | `SNOWFLAKE.CORE.DUPLICATE_COUNT` |
| non-contract codes | M03 | the 7 domains | same | custom `DMF_NONCONTRACT_CODE_COUNT` (per domain) |
| test records | M04 | KNA1, LFA1, MARA | same | custom `DMF_TEST_RECORD_COUNT` |
| missing promised date | E01 | VTTK.PROM_DLV_DT | SHIPMENT.promised_delivery_date | `NULL_COUNT` |
| over-shipment | E04 | VBAP | ORDER_LINE (0 after cap) | `DMF_OVERSHIP_COUNT` |
| negative on-hand | E05 | MARD.LABST | INVENTORY (0) | `DMF_NEGATIVE_ON_HAND_COUNT` |
| cost outliers | E08 | — (needs FX) | SHIPMENT `dq_flags` | `DMF_COST_OUTLIER_COUNT` |
| orphan lines / shipments | E09 | VBAP vs VBAK, VTTK vs VBAK | ORDER_LINE, SHIPMENT (0) | `DMF_ORPHAN_ORDER_LINES`, `DMF_ORPHAN_SHIPMENTS` |
| freshness | — | `LOAD_TS` of the 5 transactional tables | `load_ts` | `SNOWFLAKE.CORE.FRESHNESS` |
| row count | — | all 10 | all | `SNOWFLAKE.CORE.ROW_COUNT` |

Schedule: `TRIGGER_ON_CHANGES` where supported, otherwise `USING CRON 0 6 * * * UTC`.
CoCo confirms what attaches to dynamic tables in the B12 run report.

**Agent tool definition** (B10 uses it; for C10's header comment):

```yaml
- tool_spec:
    type: generic
    name: data_health
    description: >
      Freshness and data-quality status of one supply chain entity (or ALL): when it was
      last loaded, the as-of date, and which data-quality checks pass. Call it when the user
      asks whether data is up to date or trustworthy, or before answering if a result looks
      incomplete. Returns counts and rates only, never row values.
    input_schema:
      type: object
      properties:
        entity:
          type: string
          description: "suppliers, parts, sourcing, plants, inventory, customers, orders, order_lines, shipments, or ALL"
      required: [entity]
tool_resources:
  data_health:
    type: procedure
    identifier: SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH(VARCHAR)   # FQN + argument types
    execution_environment: {type: warehouse, warehouse: FORGE_WH}
```

(Shape per `docs/references/agent_custom_tools.md` §4: the tool is `type: generic`, its
resource `type: procedure`, and the `identifier` carries the argument type signature. B10
confirms it live; if Snowflake differs, the live result wins and CoCo updates this block.
`ENTITY` is a plain string: procedures with `OBJECT`-type parameters aren't supported as
agent tools.)

### 7.3 Evaluation set (C11, `eval/`)

**Table** `SUPPLY_CHAIN_FORGE.OPS.EVAL_QUESTIONS` (your script creates it `CREATE OR
REPLACE` and inserts the rows; `eval/questions.sql`):

| Column | Type | Notes |
|---|---|---|
| `QUESTION_ID` | VARCHAR | `Q01`…; stable forever |
| `CATEGORY` | VARCHAR | `CANONICAL`, `LOOKUP`, `COUNT_TOTAL`, `SUPPLIER`, `INVENTORY`, `COST`, `CROSS_SYSTEM`, `REVENUE`, `MULTI_PART`, `OUT_OF_SCOPE`, `AMBIGUOUS`, `MULTILINGUAL` |
| `INPUT_QUERY` | VARCHAR | the question, exactly as a user types it |
| `EXPECTED_BEHAVIOUR` | VARCHAR | `ANSWER`, `REFUSE` or `CLARIFY` |
| `GROUND_TRUTH_SQL` | VARCHAR | `ANSWER` only: a `SELECT` over `SEMANTIC_VIEW(...)` (or the `GOVERNED` views for record lookups) **applying §5.2** when the question names no period. Never a masked column. `NULL` otherwise |
| `COMPARE_MODE` | VARCHAR | `SCALAR` (first numeric value), `SET` (rows matched on the key columns, values within tolerance), `TOP_N` (the same top-N keys, any order), `ORDERED` (the same keys in the same order) |
| `KEY_COLUMNS` | ARRAY | key column names for `SET`/`TOP_N`/`ORDERED`, matched `UPPER(TRIM())`, e.g. `['PLANT_REGION']` |
| `TOP_N` | NUMBER | for `TOP_N` |
| `TOLERANCE_ABS` | FLOAT | e.g. `0.001` for rates |
| `TOLERANCE_REL` | FLOAT | e.g. `0.005`; a value passes if within either |
| `EXPECTED_TOOLS` | ARRAY | e.g. `['cortex_analyst_text_to_sql']`, `['data_health']`, `[]` for refusals |
| `RUBRIC` | VARCHAR | a plain-language rubric for LLM judging; `{{GT}}` is replaced with the ground-truth result as text |
| `CONTRACT_REF` | VARCHAR | e.g. `§9 Q1`, `GAP-5` |
| `ACTIVE` | BOOLEAN | |

About 25–30 questions, covering at least: the 8 §9 questions; 2 record lookups by ID; counts
and totals; supplier performance (via `lead_time`/`reliability`, not supplier-level metric
breakdowns: fan-out); inventory health (below reorder point); cost breakdown; one
cross-system question (for example shipments late vs order priority); revenue; 2 numbered
multi-part questions; 2 out of scope (`REFUSE`); 2 ambiguous (`CLARIFY`); 1 Hindi (the
same ground truth as §9 Q1).

**Runner** `SUPPLY_CHAIN_FORGE.OPS.SP_RUN_EVAL(RUN_LABEL VARCHAR, QUESTION_FILTER VARCHAR)`
(`EXECUTE AS CALLER`; CoCo calls it as `FORGE_ADMIN`, the role the app calls the agent
with; `QUESTION_FILTER` `NULL` = all active, else a `LIKE` pattern on `QUESTION_ID`):
1. For each question, call `SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT', <request>)`,
   as in contract §5.3 (non-streaming), and time it.
2. Extract the answer text, the tool names used, and the generated SQL (the Analyst
   `tool_result`; see `docs/references/data_agent_run.md`; art 07 is ground truth once it
   exists).
3. Pass rules:
   - `ANSWER`: the agent produced SQL; re-run it (only if it starts with `SELECT` or
     `WITH`) and `GROUND_TRUTH_SQL`, then compare by `COMPARE_MODE` and tolerance
   - `REFUSE`: no SQL was run
   - `CLARIFY`: no SQL was run, and the answer contains a question
   - every question: no e-mail address (`[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+`) in the answer
     text (masked-leak guard)
4. Write one row per question to `OPS.EVAL_RESULTS (RUN_LABEL, RUN_TS, QUESTION_ID,
   CATEGORY, EXPECTED_BEHAVIOUR, OBSERVED_BEHAVIOUR, PASSED, FAIL_REASON, ANSWER_TEXT,
   AGENT_SQL, GT_RESULT VARIANT, AGENT_RESULT VARIANT, TOOLS_USED ARRAY, LATENCY_MS,
   RESPONSE VARIANT)`.
5. Return VARIANT `{"run_label", "questions", "passed", "pass_rate", "by_category":
   {cat: {"n", "passed"}}, "latency_ms": {"p50", "p95", "max"}}`.

One question failing (agent error, bad SQL) is recorded as a failure with the error text;
the run continues.

**Native Snowflake evaluations** (optional, if `docs/references/agent_evaluations.md`
shows it fits): `OPS.SP_BUILD_EVAL_DATASET()` runs each `GROUND_TRUTH_SQL`, fills `{{GT}}`
in `RUBRIC`, and writes `OPS.EVAL_DATASET (INPUT_QUERY VARCHAR, GROUND_TRUTH VARIANT)` with
`{"ground_truth_output": <rubric>, "ground_truth_invocations": [...]}`, ready for
`SYSTEM$CREATE_EVALUATION_DATASET`.

### 7.4 Scale harness (C12, `tests/scale/`)

**Procedure** `SUPPLY_CHAIN_FORGE.OPS.SP_SCALE_RUN(TARGET_DB VARCHAR, RUN_LABEL VARCHAR,
RESULTS_TABLE VARCHAR)` (`EXECUTE AS CALLER`; CoCo runs it as `FORGE_ADMIN` on the clone,
with a larger warehouse set on the session; `RESULTS_TABLE` defaults to
`'SUPPLY_CHAIN_FORGE.OPS.SCALE_RESULTS'`, so the results survive dropping the clone):
- `ALTER SESSION SET USE_CACHED_RESULT = FALSE` and `QUERY_TAG = 'forge_scale:<RUN_LABEL>'`
  first.
- Builds every query as a string with `TARGET_DB` substituted, and runs it with `EXECUTE
  IMMEDIATE`. The query list:
  - the 4 metrics, both all-time and in the §5.2 default window
  - the 55 contract §4 pairings, default window
  - `SP_METRICS_AS_{PLANNER,BUYER,LOGISTICS}` (in `TARGET_DB`)
  - the §8 naive query
  - optionally 5 evaluation questions (flagged; the agent needs a clone-local agent, which
    CoCo handles at B13)
- After each query: `LAST_QUERY_ID()`, then:
  - timings from `TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION())`: `TOTAL_ELAPSED_TIME`,
    `COMPILATION_TIME`, `EXECUTION_TIME`, `BYTES_SCANNED`, `ROWS_PRODUCED`,
    `WAREHOUSE_SIZE`
  - pruning from `TABLE(GET_QUERY_OPERATOR_STATS(:qid))`: the sum of
    `operator_statistics:pruning:partitions_scanned` and `:partitions_total` over
    `TableScan` operators (verified live 2026-09-29)
- Writes rows `(RUN_LABEL, RUN_TS, TARGET_DB, WAREHOUSE_NAME, WAREHOUSE_SIZE, QUERY_NAME,
  PATH ['SEMANTIC_VIEW'|'PROCEDURE'|'NAIVE'|'AGENT'], METRIC, DIMENSION, TIME_WINDOW
  ['ALL'|'T12M'|'LATEST'], QUERY_ID, ELAPSED_MS, COMPILATION_MS, EXECUTION_MS,
  BYTES_SCANNED, PARTITIONS_SCANNED, PARTITIONS_TOTAL, ROWS_PRODUCED, RESULT_HASH, SQL_HASH,
  ERROR)`:
  - `RESULT_HASH` = `HASH_AGG` of the result, rounded to 6 dp
  - `SQL_HASH` = `HASH(<query text with TARGET_DB replaced by a placeholder>)`. It proves
    the SQL shape is identical at every scale.
- Returns VARIANT `{"run_label", "queries", "failed", "total_elapsed_ms", "max_elapsed_ms"}`.

`tests/scale/report_template.md` is the outline of art 12: the XS vs large-warehouse
timings per path, pruning ratios, credits (CoCo adds them from `WAREHOUSE_METERING_HISTORY`),
dynamic-table refresh times, identical `SQL_HASH` across scales, and personas identical.

**Clone note for C12**: the semantic view, the governed views and `SP_METRICS_AS_*` hard-code
`SUPPLY_CHAIN_FORGE.…`. In a clone they would still read the original. CoCo regenerates them
inside the clone at B13 (`SP_BUILD_SEMANTIC_VIEW`, B09a). The harness only needs `TARGET_DB`.

---

## 8. How CoCo runs your files

Full detail, with the live-verified behaviour: `docs/references/snowflake_execution_notes.md`.
In short:
- CoCo runs each file statement by statement, or a whole Scripting block as one call.
  **Session state (variables, `USE ROLE`, `USE WAREHOUSE`) is not guaranteed between
  calls**, so procedures take parameters and set their own context.
- The role and warehouse CoCo uses:

  | Files | Role | Warehouse |
  |---|---|---|
  | `data_gen/` | `ACCOUNTADMIN` | `FORGE_WH` (XS) at SF ≤ 1; a larger warehouse at B13 |
  | `quality/` | `ACCOUNTADMIN` creates the DMFs and attaches them; `SP_DATA_HEALTH` is owned by `FORGE_ADMIN` | `FORGE_WH` |
  | `eval/`, `tests/scale/` | `FORGE_ADMIN` | `FORGE_WH`; B13 per its card |

- **Runtime budget**: each call ≤ 15 min; at SF = 1 the whole C08 run should finish in
  ≤ 20 min on XS (3M hash rows took 0.4 s). B13 runs in yearly chunks on a larger warehouse.
- Every file has a header comment: the card, the role, the warehouse, the parameters, the
  run order and the expected results. Fully qualified names; `CREATE OR REPLACE` or
  `IF NOT EXISTS`; every statement ends with `;`.
- CoCo compiles first (`only_compile`), then runs. It fixes only run-blocking issues of a
  few lines, as a diff in `docs/artifacts/runs/<card>_run.md`.
