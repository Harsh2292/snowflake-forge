# B08 — Semantic View → artifacts 05, 06 (+ `SP_METRICS_AS_*`)

| | |
|---|---|
| **Owner** | CoCo |
| **Milestone** | M3 |
| **Prerequisite** | B07 + B07b gates passed (9 governed views, masking, persona sample procedures) |
| **Est. effort** | One session |
| **Writes** | `semantic/01_semantic_view.sql`, `sql/04_governance/05_persona_metric_procedures.sql`, `docs/artifacts/05_metric_values.json`, `docs/artifacts/06_dimension_matrix.md` |
| **Status** | ✅ done 2026-09-28, gate passed |

---

## Goal

Build `SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV` over the 9 governed views, exactly as
contract §3/§4 names it, then the three owner's-rights metric procedures of CR-002. Capture
art 05 and art 06, which unlock Claude Code's C6b.

## Carried in (B07 / B07b)

| Item | Implementation |
|---|---|
| CR-005 fill-rate filter | `order_lines.fill_rate` counts only lines whose order is `SHIPPED` or `DELIVERED`, via `order_lines → orders`. Target 0.926485 |
| §3 DOI formula | `AVG(quantity_on_hand) / NULLIFZERO(AVG(daily_usage))`. Target 28.499215 |
| GAP-2 time dimensions | `order_year`, `order_quarter` (`'Q'||QUARTER`), `order_month` (`YYYY-MM`), `order_week`, as dimension expressions on `V_ORDER` |
| Persona access | `GRANT SELECT ON SEMANTIC VIEW` to the 3 persona roles |
| `SP_METRICS_AS_*` | Same pattern as `04_persona_procedures.sql` |

---

## Design

| Decision | Why |
|---|---|
| Created by **`FORGE_ADMIN`** | The app owner; it has `CREATE SEMANTIC VIEW` on `SEMANTIC` and `SELECT` on the governed views |
| Logical table names = contract entity names (`suppliers`, `parts`, `sourcing`, `plants`, `inventory`, `customers`, `orders`, `order_lines`, `shipments`) | §3/§4 identifiers are `<entity>.<name>` |
| Contract dimension names mapped onto view columns (`plants.plant_region AS region`, `plants.plant_country AS country`, `suppliers.supplier_region AS region`, `customers.customer_region AS region`) | §4 names differ from §7 column names; §5.2 output headers are the unqualified dimension names |
| Relationships are all many-to-one, from fact to master (10, as LLD §6) | Gives exactly the §4 valid pairings; DOI has no path to `orders`/`shipments` |
| Metrics use the §3 definitions word for word in `COMMENT` | Cortex Analyst and B13 read the same text the app shows |
| No metric references a masked column | §6 invariant: the numbers are identical across personas |
| Built incrementally: shipments + orders → + order_lines → + plants/parts/inventory → + customers/suppliers/sourcing | CoCo gotcha: never write 9 entities blind |
| Metric procedures return `NUMBER(38,6)` | The gate compares to 6 dp |

If the CR-005 filter cannot reference `orders.order_status` from an `order_lines` metric,
try a derived fact on `order_lines`. If neither works, stop and file a CR; do not ship a
different number.

---

## Steps

1. Write `semantic/01_semantic_view.sql`; build it in 4 stages, validating each with a real `SEMANTIC_VIEW()` query.
2. Grant `SELECT` on the semantic view to the persona roles.
3. Capture art 05: 4 overall values + all 55 valid §4 pairings in full.
4. Capture art 06: 4 metrics × 24 dimensions (the 23 of §4 plus `orders.order_week`) = 96, pass/fail with error text.
5. Write and run `sql/04_governance/05_persona_metric_procedures.sql`.
6. Run the gate.

---

## Gate

1. The 4 metrics equal the B07 values to 6 dp and sit inside their §3 ranges.
2. All 55 valid pairings return rows, with the §5.2 column names.
3. DOI × `orders.*` and × `shipments.*` are rejected by Snowflake.
4. Dimension values match §4 (`Q1`–`Q4`, regions, statuses …).
5. Each persona role, alone (secondary roles off), queries the semantic view and gets the same 4 values.
6. `SP_METRICS_AS_*`: owned by their persona roles; `PERSONA` = owner; values identical to 6 dp and equal to the semantic view.
7. Art 05 and 06 exist; art 05 parses and matches Snowflake's hash.

Not run: Claude Code's `pytest -m live` (the project venv has no Snowpark, as at B07b). The
SQL checks above cover the same assertions.

### Build stages (live, as `FORGE_ADMIN`)

| Stage | Tables | Check | Result |
|---|---|---|---|
| a | shipments, orders | OTD | 0.873973 ✅ |
| b | + order_lines | fill rate with CR-005 (private facts reading `orders.order_status`) | 0.926485 ✅; no CR needed |
| c | + plants, parts, inventory | DOI | 28.499215 ✅ |
| d | + customers, suppliers, sourcing (9 tables, 10 relationships) | all 4 in one query | 0.873973 / 0.926485 / 28.499215 / 518.971250 ✅ |

### Gate results (2026-09-28, live)

| # | Check | Result |
|---|---|---|
| 1 | 4 metrics vs B07 | OTD 0.873973, fill 0.926485, DOI 28.499215, landed 518.971250: all equal to 6 dp and inside §3 ranges ✅ |
| 2 | 55 valid pairings | 55/55 PASS; headers are unqualified names (`PLANT_REGION`, …) ✅ |
| 3 | DOI × `orders.*` / `shipments.*` | 9/9 rejected: "The entities 'ORDERS' and 'INVENTORY' are not related…" ✅ |
| 4 | Dimension values | `Q1`–`Q4`; APAC / EMEA / AMER; OPEN / SHIPPED / DELIVERED / CANCELLED ✅ |
| 5 | Persona roles alone | `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE` each query the view; identical values ✅ |
| 6 | `SP_METRICS_AS_*` | owned by PLANNER / BUYER / LOGISTICS_ROLE; `PERSONA` = owner; identical to 6 dp and equal to the view ✅ |
| 7 | Artifacts | art 05 SHA-256 `02eb2c2e…b814b2a5` matches Snowflake, parses, 55 pairings; art 06 written from query `01c75f59-…13b6` ✅ |

**Found while running the gate:**
- **`suppliers.*` is not in §4, but Snowflake accepts it for fill rate and DOI.** `parts` reaches `suppliers` through `sourcing`, where 150 of 250 parts have more than one supplier, so "by supplier" counts a part once per supplier. Art 06 flags it. It's harmless for the contract (the app only uses §4 pairings); B09's `AI_SQL_GENERATION` should tell the agent not to break metrics down by supplier.
- **Rows inside each art 05 pairing are not sorted** (`ORDER BY 1` inside `WITHIN GROUP` sorts by a constant). Values are exact; consumers should sort by the dimension.
- **Shipments cover 6 of 12 plants**, so OTD and landed cost by plant have 6 rows. That comes from the data, not the view.
- **Fill rate by category** is exactly 1.000 for CHEMICAL, ELECTRONICS and RAW_MATERIAL, and about 0.85 for the other three. That comes from the B04 generated data.

---

## On Completion

1. Tick B08 ✅ in `.agents/NEXT.md`; set B09 as NEXT.
2. Update `.agents/HANDOFF.md` (CoCo section): art 05/06 DONE → C6b unlocked; `compare_across_personas()` live mode no longer needs the mock fallback.
3. Update `.agents/tasks/COCO_TASKS.md`, `docs/SESSION_LOG.md`, `.agents/tasks/README.md`.
