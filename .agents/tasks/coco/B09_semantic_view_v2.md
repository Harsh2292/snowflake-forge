# B09 — Semantic View v2 → artifacts 05, 06, 09

| | |
|---|---|
| **Owner** | CoCo |
| **Milestone** | M3 |
| **Prerequisite** | B08c gate passed (C08 data loaded, `CONFORMED` layer, governed views re-pointed) |
| **Est. effort** | One session |
| **Writes** | `semantic/01_semantic_view.sql`, `sql/04_governance/05_persona_metric_procedures.sql`, `docs/artifacts/05_metric_values.json`, `docs/artifacts/06_dimension_matrix.md`, `docs/artifacts/09_consistency_proof.json`, `docs/CONTRACT.md` §10 (mock values only, per CR-006) |
| **Status** | ✅ done 2026-09-29, gate 7/7 |

---

## Goal

Rebuild `SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV` so that Cortex Analyst can answer
everyday supply chain questions from it alone, while the 4 canonical metrics stay the single
definition (core rules 4, 5, 6, 7). Then capture art 05, 06 and 09 on the B08c data, which
unblocks Claude Code's C6b and C6c.

## Carried in

| Item | From | Implementation |
|---|---|---|
| E01 OTD denominator | CR-006, DATA_SPEC §5.3 | `COUNT_IF(actual <= promised) / NULLIFZERO(COUNT_IF(actual IS NOT NULL AND promised IS NOT NULL))` |
| Revenue definition | HANDOFF (C11 agreement) | shipped quantity × unit price, on SHIPPED/DELIVERED orders, by order date |
| `orders.order_year_quarter` | CR-006 §4 | `YEAR || '-Q' || QUARTER`, e.g. `2026-Q3` |
| Below reorder point | HANDOFF (C11) | `quantity_on_hand < reorder_point`, on the latest snapshot |
| Q08 | CR-003, C11 | `vq_worst_plants_otd`: the bottom 3 plants by OTD |
| Supplier fan-out | B08 finding | primary-sourcing logical table (one supplier per part; verified live: 0 parts with 2+ primaries, 0 with none) |
| §3a time rule | CR-006 | stated in `AI_SQL_GENERATION`; applied in `SP_METRICS_AS_*` |

## Design

| Decision | Why |
|---|---|
| `primary_sourcing AS (SELECT … FROM V_SOURCING WHERE is_primary)`, PK `part_id`; `parts → primary_sourcing → suppliers` | Supplier dimensions reach parts-based metrics many-to-one, so there's no fan-out. It's a SQL-query logical table, so no new governed view is needed |
| Fall back to the `AI_SQL_GENERATION` ban if Snowflake rejects the two paths to `suppliers` | COCO_TASKS B9 carry-in |
| `line_revenue` = `IFF(status IN (SHIPPED, DELIVERED), quantity_shipped × unit_price, 0)` | Any ad-hoc `SUM(line_revenue)` equals the `total_revenue` metric |
| Every business column exposed once; never `unit_cost`, `contract_price`, `payment_terms`, `credit_limit` or either `email` | Core rule 4, §6. `customer_name` is a label only; group by `customer_id` |
| Named filters via `LABELS = (FILTER)` on boolean dimensions | Late, delivered, critical, open |
| Verified-query SQL = the exact `SEMANTIC_VIEW(...)` SQL the app runs, with the §3a `WHERE` | One question, one number (core rule 5) |
| Existing names unchanged (all §3/§4 ids, the `total_landed_cost` and `is_on_time` facts) | Contract; never rename |

## Steps

1. Baseline v1: DDL token estimate, and Analyst latency on 5 test questions.
2. Write v2 and build it incrementally, checking with `SEMANTIC_VIEW()`.
3. Update `SP_METRICS_AS_*` to apply §3a (3 windowed calls, cross-joined). Same shape and owners.
4. Run the gate.
5. Capture art 05, 06 and 09. Update contract §10 with the art 05 values.
6. Update NEXT, HANDOFF, SESSION_LOG, COCO_TASKS and tasks/README.

## Gate

1. Fill 0.9261, DOI 36.44 and landed cost 604.84 are unchanged from B08c to 6 dp; OTD = the E01 value (≈ 0.8753); all inside §3.
2. Every §4 valid pairing returns rows (incl. `order_year_quarter`); DOI × `orders.*`/`shipments.*` is still rejected.
3. Fill rate and DOI by supplier: no fan-out (the grouped sums tie to the ungrouped totals).
4. All verified queries run.
5. Each persona role alone (secondary roles NONE) gets the same values; `SP_METRICS_AS_*` are identical to 6 dp.
6. Fast: under a 25K-token estimate, and Analyst latency on the 5 questions no worse than v1.
7. Art 05/06/09 written; art 05 parses; art 09 identical across personas to 6 dp.

### Gate results (2026-09-29, live, old account)

| # | Check | Result |
|---|---|---|
| 1 | Canonical values (§3a windows) | OTD **0.875262** (= the E01 value, ties to a direct `V_SHIPMENT` count) · fill **0.926100** · DOI **36.436790** · landed **604.841638**: fill, DOI and landed equal B08c to 6 dp; all inside §3 ✅. `total_revenue` 10,094,237,839.54 = C11 Q21's ground truth to the cent |
| 2 | §4 matrix | 58/58 contract pairings PASS (incl. `order_year_quarter` ×3); DOI × `orders.*`/`shipments.*`/`customers.*` rejected ✅ |
| 3 | Supplier fan-out | units ordered by supplier 429,720,584 = total; below-reorder positions by supplier 14 = total ✅ |
| 4 | Verified queries | 12/12 run (8 §9 + 4 cross-functional) ✅ |
| 5 | Personas | `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE` alone (secondary NONE) and `SP_METRICS_AS_*` (owned by each persona): identical to 6 dp ✅ |
| 6 | Fast | ~8.3K tokens (v1 3.4K; budget 25K). Analyst on 5 questions: v1 7.3/13.7/8.9/6.9/7.8 s (44.6 s) → v2 5.2/5.5/4.6/4.9/4.7 s (24.9 s); all 5 applied the §3a window ✅ |
| 7 | Artifacts | art 05 (58 pairings, 281,869 chars, SHA-256 `0383c071…33739b19`, parses); art 06 (100 cells); art 09 (`identical_to_6dp: true`, divergence = §6 exactly) ✅ |

**Found while running the gate:**
- **New Snowflake behaviour: one-to-many cross-grain pairings now run.** OTD and landed cost ×
  `parts.*`, and fill rate × `shipments.*`, were rejected in v1 and now return rows. They
  multi-count: shipment count by part category sums to 241,117 against 95,892 shipments, and
  units by carrier come out about 11% over. None is a §4 pairing. `AI_SQL_GENERATION` rule 8
  forbids them, and B10's evaluation should include one such question.
- The two paths to `suppliers` (`sourcing` and `primary_sourcing`) were accepted without
  `USING`; the fallback wasn't needed.
- `LABELS = (FILTER)` works on boolean dimensions (4 named filters).
- Verified-query SQL written as `SEMANTIC_VIEW(...)` is accepted, and Analyst reproduces it
  (Q8 came back as the exact `vq_worst_plants_otd` SQL).
- The trailing-12-month quarter view has 5 quarters (the partial first and last), which is
  expected.
