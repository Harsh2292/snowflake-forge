# B08c run report — v2 source DDL, C08 load, CONFORMED layer

| | |
|---|---|
| **Date** | 2026-09-29 |
| **Account** | `tyduokn-gf25237` (DA53081, AZURE_CENTRALINDIA). The new account was not touched |
| **Role / warehouse** | `ACCOUNTADMIN` for DDL, C08 and CONFORMED; `FORGE_ADMIN` for the semantic view and art 04. `FORGE_WH` XS (MEDIUM for ~6 min during the aborted first C08 SF 1 attempt; back to XS) |
| **Result** | **Gate passed (7/7)** |

## What ran, in order

| # | File | Result |
|---|---|---|
| 1 | `sql/01_setup/03_schemas_v2.sql` | `CONFORMED`, `OPS` created; FORGE_ADMIN SELECT (+ future) on CONFORMED |
| 2 | `sql/02_tables/05_source_v2.sql` | v1 tables dropped; 10 v2 tables, `change_tracking = ON` on all |
| 3 | `sql/04_governance/01_tags.sql` | new tag `SEMANTIC_ROLE`; source tags re-applied (TCURR tagged ERP/INTERNAL) |
| 4 | `data_gen/00 → 10 → 20 → 30 → 99` | see `C08_run.md` (3 small fixes). SF 1 in 130 s |
| 5 | `sql/04_governance/06_conformed_layer.sql` | `CODE_MAP` (static), `CALENDAR` (static), 10 dynamic tables, all **INCREMENTAL** |
| 6 | `sql/04_governance/03_governed_views.sql` | 9 views re-pointed to CONFORMED |
| 7 | `semantic/01_semantic_view.sql` | re-run as-is (COPY GRANTS), OK |
| 8 | art 03, art 04 | re-captured, same shape |

`04_persona_procedures.sql` / `05_persona_metric_procedures.sql` were **not** re-created:
their bodies are unchanged and resolve the views by name at run time; they were called
instead (art 04).

## CONFORMED row counts

| Table | Rows | Notes |
|---|---|---|
| SUPPLIER | 150 | 2 test vendors removed |
| PART | 1,200 | 4 test parts removed |
| PLANT | 12 | |
| CUSTOMER | 2,000 | 5 test customers + 20 M01 duplicates removed |
| SOURCING | 2,501 | source 2,503 (2,489 clean + 12 E11 + 2 test) − 2 test rows; `V_SOURCING` (valid today) 1,965, exactly 1 primary for each of the 1,200 parts |
| INVENTORY | 2,156,400 | M01 duplicates removed |
| SALES_ORDER | 638,198 | 650,000 − returns − test orders − future-dated |
| ORDER_LINE | 2,000,369 | |
| SHIPMENT | 693,241 | |
| FX_RATE | 54,790 | 10 currencies × 5,479 days |

## Gate

| # | Check | Result |
|---|---|---|
| 1 | §7: 65 columns, same names and order as the previous art 03; masking on exactly the 6 §6 columns | ✅ 65 / 9 views; names+order identical; the same 6 policies. Type changes = DATA_SPEC §1 widenings only (order/shipment IDs 10→12, carrier 20→30) and `is_nullable` YES |
| 2 | Repairable defects present in SOURCE (C08 self-checks), **zero** in CONFORMED | ✅ SOURCE: every `RATE_M*` TRUE. CONFORMED: 0 duplicate keys, 0 non-contract codes (7 domains), 0 test records, 0 `UNMAPPED_CODE`, 0 orphans, 0 returns, 0 future-dated, 0 missing FX |
| 3 | Edge-case rules applied; `dq_flags` = the injected rows still in scope | ✅ exact reconciliation against the latest in-scope source versions: E01 5,539 = 5,539 · E04 18,676 = 18,676 · E07c 1,380 = 1,380 · M07 VTTK 2,087 = 2,087. E05 6,469/6,469, E06 72/72, E11 12/12. The rest of the gap to `GEN_MESS_LOG` is rows out of scope (returns, orphans, tests), e.g. E04 913 = 288 returns + 51 orphans + 59 test + 515 lines where `ROUND(KWMENG × 1.05..1.20)` = KWMENG (never over-shipped). No over-shipment, no negative on-hand left; max landed cost 2,166 USD (0 above 25K) |
| 4 | 4 metrics in the §3a windows within §5.4, identical across personas | ✅ FORGE_ADMIN = PLANNER = BUYER = LOGISTICS: **OTD 0.868331 · landed 604.841638 · fill 0.926100 · DOI 36.436790** (latest snapshot 2026-09-29). With the B09 E01 denominator: OTD **0.875262** |
| 5 | §8 naive OTD ≥ 8 pt below governed, wider than art 02 | ✅ naive **0.681651** vs governed 0.868331: **18.7 pt** (19.4 pt with the E01 denominator); art 02 was 9.04 pt |
| 6 | Persona roles: no grants on SOURCE or CONFORMED | ✅ `TABLE_PRIVILEGES`: none (FORGE_ADMIN: CONFORMED 12, OPS 3). Live, as PLANNER_ROLE with secondary roles NONE: CONFORMED and SOURCE denied, `V_PART` works with `unit_cost` masked |
| 7 | Every DT refreshes incrementally, no refresh errors | ✅ `refresh_mode` INCREMENTAL on all 10 (creation would fail otherwise); 27 refreshes, all SUCCEEDED (INCREMENTAL or NO_DATA) |

Also §5.4: OTD by plant region AMER 0.8666 / APAC 0.8607 / EMEA 0.8772; fill by category
0.9209–0.9488; 9 carriers, 3 shipment statuses, 4 order statuses, 3 priorities; 132
plant-years = 12 plants × 11 calendar years.

## Notes

- **Secondary roles.** The user's default secondary roles are ALL, so a session that does
  only `USE ROLE PLANNER_ROLE` can still read CONFORMED. Any persona-isolation check must
  run `USE SECONDARY ROLES NONE` (art 04 does). Masking uses `CURRENT_ROLE()` (the primary
  role), so the metric identity check is unaffected.
- **The CoCo SQL tool splits on `;` in comments.** A chunk that ends in a comment-only piece
  fails with "Empty SQL statement". Semicolons were removed from comments in the new files.
- **OTD formula.** The semantic view (B08) still counts shipments without a promised date in
  the OTD denominator (0.8683). B09 switches to the §5.3 formula (0.8753).
- **Art 04 values changed** with the new data (e.g. MAT000001 unit cost 22.20, supplier
  SUP00107). 4 of Claude Code's replay tests pin the v1 sample rows and now fail
  (`test_offline_demo_shows_exactly_what_snowflake_returned` ×3,
  `test_rows_drawer_shows_each_real_record_masked_per_team`); 59 pass. Claude Code
  re-syncs `mock_data` from art 04.
- Cost (METERING_HISTORY, 29 Sep, whole day): FORGE_WH 1.08 credits, COMPUTE_WH 2.38 (the
  SQL tool's default warehouse, auto-suspend 600 s), CoCo (Cortex Code) itself 35.4 credits.
  The org balance was USD 243.03 (REMAINING_BALANCE_DAILY, 29 Sep).
