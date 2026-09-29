# Artifact 06 — Metric × Dimension Matrix

| | |
|---|---|
| **Build step** | B08 |
| **Captured** | 2026-09-28, query ID `01c75f59-0002-2332-000f-b48a000513b6` |
| **Object** | `SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV` |
| **Run as** | `FORGE_ADMIN`, secondary roles off |
| **Tested** | 4 metrics × 24 dimensions = 96 queries (the 23 contract §4 dimensions plus `orders.order_week`, GAP-2) |

Each cell ran:

```sql
SELECT COUNT(*) FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  DIMENSIONS <dimension> METRICS <metric>
);
```

`PASS` = the query ran; the number is the row count it returned. `FAIL` = Snowflake
refused it at compile time. Every failure's error text is exactly:

> SQL compilation error:
> The entities '*A*' and '*B*' are not related. Consider selecting calculations from
> entities that are related and have appropriate levels of granularity.

with *A* and *B* as shown in the Error column.

## Summary

| | Count |
|---|---|
| Contract §4 valid pairings | 55 |
| … of which PASS | **55** |
| Pairings §4 lists as invalid (DOI × `orders.*`, `shipments.*`) | 9 |
| … of which rejected by Snowflake | **9** |
| `orders.order_week` (not in §4, GAP-2 extra) | PASS for OTD, fill rate, landed cost; FAIL for DOI |
| Not in §4 but Snowflake runs them | 6: `suppliers.*` × fill rate and × DOI ⚠ see note |

**Note on `suppliers.*`.** No metric's §4 list includes `suppliers.*`. Snowflake accepts
fill rate and DOI by supplier because `parts` reaches `suppliers` through `sourcing`.
But 150 of the 250 parts have more than one sourcing row (400 rows in total), so these
results count a part once per supplier. They are **not** contract pairings; the app
and agent should not use them. OTD and landed cost by supplier are rejected.

---

## `shipments.on_time_delivery_rate`

§4 valid: `plants.*`, `orders.*`, `shipments.*`, `customers.*`

| Dimension | In §4 | Result | Rows | Error (*A* / *B*) |
|---|---|---|---|---|
| `suppliers.supplier_name` | — | FAIL | | SUPPLIERS / SHIPMENTS |
| `suppliers.supplier_region` | — | FAIL | | SUPPLIERS / SHIPMENTS |
| `suppliers.supplier_tier` | — | FAIL | | SUPPLIERS / SHIPMENTS |
| `parts.part_name` | — | FAIL | | PARTS / SHIPMENTS |
| `parts.category` | — | FAIL | | PARTS / SHIPMENTS |
| `parts.subcategory` | — | FAIL | | PARTS / SHIPMENTS |
| `parts.is_critical` | — | FAIL | | PARTS / SHIPMENTS |
| `plants.plant_name` | ✅ | PASS | 6 | |
| `plants.plant_region` | ✅ | PASS | 3 | |
| `plants.plant_country` | ✅ | PASS | 5 | |
| `plants.plant_type` | ✅ | PASS | 3 | |
| `customers.customer_segment` | ✅ | PASS | 3 | |
| `customers.customer_region` | ✅ | PASS | 3 | |
| `orders.order_date` | ✅ | PASS | 292 | |
| `orders.order_month` | ✅ | PASS | 12 | |
| `orders.order_quarter` | ✅ | PASS | 4 | |
| `orders.order_year` | ✅ | PASS | 2 | |
| `orders.order_status` | ✅ | PASS | 2 | |
| `orders.order_priority` | ✅ | PASS | 3 | |
| `shipments.ship_date` | ✅ | PASS | 353 | |
| `shipments.carrier` | ✅ | PASS | 6 | |
| `shipments.shipment_status` | ✅ | PASS | 3 | |
| `inventory.snapshot_date` | — | FAIL | | INVENTORY / SHIPMENTS |
| `orders.order_week` | (GAP-2) | PASS | 51 | |

## `order_lines.fill_rate`

§4 valid: `parts.*`, `plants.*`, `orders.*`, `customers.*`

| Dimension | In §4 | Result | Rows | Error (*A* / *B*) |
|---|---|---|---|---|
| `suppliers.supplier_name` | — | PASS ⚠ | 60 | fans out via `sourcing` |
| `suppliers.supplier_region` | — | PASS ⚠ | 3 | fans out via `sourcing` |
| `suppliers.supplier_tier` | — | PASS ⚠ | 3 | fans out via `sourcing` |
| `parts.part_name` | ✅ | PASS | 250 | |
| `parts.category` | ✅ | PASS | 6 | |
| `parts.subcategory` | ✅ | PASS | 12 | |
| `parts.is_critical` | ✅ | PASS | 2 | |
| `plants.plant_name` | ✅ | PASS | 12 | |
| `plants.plant_region` | ✅ | PASS | 3 | |
| `plants.plant_country` | ✅ | PASS | 9 | |
| `plants.plant_type` | ✅ | PASS | 3 | |
| `customers.customer_segment` | ✅ | PASS | 3 | |
| `customers.customer_region` | ✅ | PASS | 3 | |
| `orders.order_date` | ✅ | PASS | 292 | |
| `orders.order_month` | ✅ | PASS | 12 | |
| `orders.order_quarter` | ✅ | PASS | 4 | |
| `orders.order_year` | ✅ | PASS | 2 | |
| `orders.order_status` | ✅ | PASS | 4 | |
| `orders.order_priority` | ✅ | PASS | 3 | |
| `shipments.ship_date` | — | FAIL | | SHIPMENTS / ORDER_LINES |
| `shipments.carrier` | — | FAIL | | SHIPMENTS / ORDER_LINES |
| `shipments.shipment_status` | — | FAIL | | SHIPMENTS / ORDER_LINES |
| `inventory.snapshot_date` | — | FAIL | | INVENTORY / ORDER_LINES |
| `orders.order_week` | (GAP-2) | PASS | 51 | |

`orders.order_status` returns 4 rows. By CR-005, OPEN and CANCELLED count 0 in both
numerator and denominator, so their fill rate is `NULL` (see art 05).

## `inventory.days_of_inventory`

§4 valid: `plants.*`, `parts.*`, `inventory.snapshot_date`. §4 invalid: `orders.*`, `shipments.*`

| Dimension | In §4 | Result | Rows | Error (*A* / *B*) |
|---|---|---|---|---|
| `suppliers.supplier_name` | — | PASS ⚠ | 6 | fans out via `sourcing` |
| `suppliers.supplier_region` | — | PASS ⚠ | 3 | fans out via `sourcing` |
| `suppliers.supplier_tier` | — | PASS ⚠ | 3 | fans out via `sourcing` |
| `parts.part_name` | ✅ | PASS | 25 | |
| `parts.category` | ✅ | PASS | 3 | |
| `parts.subcategory` | ✅ | PASS | 6 | |
| `parts.is_critical` | ✅ | PASS | 2 | |
| `plants.plant_name` | ✅ | PASS | 12 | |
| `plants.plant_region` | ✅ | PASS | 3 | |
| `plants.plant_country` | ✅ | PASS | 9 | |
| `plants.plant_type` | ✅ | PASS | 3 | |
| `customers.customer_segment` | — | FAIL | | CUSTOMERS / INVENTORY |
| `customers.customer_region` | — | FAIL | | CUSTOMERS / INVENTORY |
| `orders.order_date` | ❌ invalid | FAIL ✅ | | ORDERS / INVENTORY |
| `orders.order_month` | ❌ invalid | FAIL ✅ | | ORDERS / INVENTORY |
| `orders.order_quarter` | ❌ invalid | FAIL ✅ | | ORDERS / INVENTORY |
| `orders.order_year` | ❌ invalid | FAIL ✅ | | ORDERS / INVENTORY |
| `orders.order_status` | ❌ invalid | FAIL ✅ | | ORDERS / INVENTORY |
| `orders.order_priority` | ❌ invalid | FAIL ✅ | | ORDERS / INVENTORY |
| `shipments.ship_date` | ❌ invalid | FAIL ✅ | | SHIPMENTS / INVENTORY |
| `shipments.carrier` | ❌ invalid | FAIL ✅ | | SHIPMENTS / INVENTORY |
| `shipments.shipment_status` | ❌ invalid | FAIL ✅ | | SHIPMENTS / INVENTORY |
| `inventory.snapshot_date` | ✅ | PASS | 30 | |
| `orders.order_week` | (GAP-2) | FAIL | | ORDERS / INVENTORY |

Inventory covers 25 parts (of 250) across 12 plants, over 30 snapshot dates.

## `shipments.avg_landed_cost`

§4 valid: `plants.*`, `orders.*`, `shipments.*`, `customers.*`

| Dimension | In §4 | Result | Rows | Error (*A* / *B*) |
|---|---|---|---|---|
| `suppliers.supplier_name` | — | FAIL | | SUPPLIERS / SHIPMENTS |
| `suppliers.supplier_region` | — | FAIL | | SUPPLIERS / SHIPMENTS |
| `suppliers.supplier_tier` | — | FAIL | | SUPPLIERS / SHIPMENTS |
| `parts.part_name` | — | FAIL | | PARTS / SHIPMENTS |
| `parts.category` | — | FAIL | | PARTS / SHIPMENTS |
| `parts.subcategory` | — | FAIL | | PARTS / SHIPMENTS |
| `parts.is_critical` | — | FAIL | | PARTS / SHIPMENTS |
| `plants.plant_name` | ✅ | PASS | 6 | |
| `plants.plant_region` | ✅ | PASS | 3 | |
| `plants.plant_country` | ✅ | PASS | 5 | |
| `plants.plant_type` | ✅ | PASS | 3 | |
| `customers.customer_segment` | ✅ | PASS | 3 | |
| `customers.customer_region` | ✅ | PASS | 3 | |
| `orders.order_date` | ✅ | PASS | 292 | |
| `orders.order_month` | ✅ | PASS | 12 | |
| `orders.order_quarter` | ✅ | PASS | 4 | |
| `orders.order_year` | ✅ | PASS | 2 | |
| `orders.order_status` | ✅ | PASS | 2 | |
| `orders.order_priority` | ✅ | PASS | 3 | |
| `shipments.ship_date` | ✅ | PASS | 353 | |
| `shipments.carrier` | ✅ | PASS | 6 | |
| `shipments.shipment_status` | ✅ | PASS | 3 | |
| `inventory.snapshot_date` | — | FAIL | | INVENTORY / SHIPMENTS |
| `orders.order_week` | (GAP-2) | PASS | 51 | |

---

## Observations for C6b (data, not semantic-view defects)

- **Shipments cover 6 of 12 plants**, in 5 countries, so OTD and landed cost by plant
  return 6 rows. Order lines and inventory cover all 12.
- **OTD × `orders.order_status`** returns 2 rows: only SHIPPED and DELIVERED orders have
  shipments.
- **Fill rate by `parts.category`**: CHEMICAL, ELECTRONICS and RAW_MATERIAL are exactly
  1.000; FASTENERS, MECHANICAL and PACKAGING are about 0.85. That comes from the B04
  generated data. The overall value, 0.926485, is inside the §3 range.
