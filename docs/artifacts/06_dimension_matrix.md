# Artifact 06 — Metric × Dimension Matrix

| | |
|---|---|
| **Build step** | B09 (re-captured on the B08c data; v1 was B08) |
| **Captured** | 2026-09-29, into `SUPPLY_CHAIN_FORGE.OPS.B09_MATRIX` by one anonymous block; read back by query `01c76640-0002-23d2-000f-b48a000724c2` |
| **Object** | `SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV` (v2) |
| **Run as** | `FORGE_ADMIN`, secondary roles off |
| **Tested** | 4 metrics × 25 dimensions = 100 queries: the 24 contract §4 dimensions (incl. `orders.order_year_quarter`), plus `orders.order_week` (GAP-2); `suppliers.*` now route through `primary_sourcing` |

Each cell ran, with the metric's contract §5.1 default window:

```sql
SELECT ARRAY_AGG(OBJECT_CONSTRUCT_KEEP_NULL(*)) WITHIN GROUP (ORDER BY <dim>)
FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  DIMENSIONS <dimension> METRICS <metric> WHERE <default window>);
```

`PASS` = the query ran; Rows = rows returned. `FAIL` = Snowflake refused it; the error is quoted.

## Summary

| | Count |
|---|---|
| Contract §4 pairings that PASS | 58 of 58 |
| Non-contract pairings rejected by Snowflake | 22 |
| Non-contract pairings Snowflake accepts | 20 (see notes) |

**Changes from v1 (B08):**
- `orders.order_year_quarter` added: 3 PASS (OTD, fill rate, landed cost); rejected for DOI.
- `suppliers.*` for fill rate and DOI now go through `primary_sourcing` and no longer fan out: summed by supplier, units ordered and below-reorder positions tie to the totals exactly.
- `suppliers.*` for OTD and landed cost now fail with `Multi-path in many-to-many relationship` instead of "not related".
- **New Snowflake behaviour:** OTD and landed cost × `parts.*`, and fill rate × `shipments.*`, were rejected in v1 and now run. They cross a one-to-many join (an order has several lines and ~1.1 shipments), so they multi-count: shipment count by part category sums to 241,117 against 95,892 shipments. None is a §4 pairing, the app doesn't use them, and `AI_SQL_GENERATION` rule 8 forbids them for the agent.

## `shipments.on_time_delivery_rate`

| Dimension | In §4 | Result | Rows | Note / error |
|---|---|---|---|---|
| `suppliers.supplier_name` | — | FAIL ✅ |  | Unsupported feature 'Multi-path in many-to-many relationship'. |
| `suppliers.supplier_region` | — | FAIL ✅ |  | Unsupported feature 'Multi-path in many-to-many relationship'. |
| `suppliers.supplier_tier` | — | FAIL ✅ |  | Unsupported feature 'Multi-path in many-to-many relationship'. |
| `parts.part_name` | — | PASS ⚠ | 1165 | ⚠ multi-counts (one-to-many through `orders`); banned by `AI_SQL_GENERATION` rule 8 |
| `parts.category` | — | PASS ⚠ | 7 | ⚠ multi-counts (one-to-many through `orders`); banned by `AI_SQL_GENERATION` rule 8 |
| `parts.subcategory` | — | PASS ⚠ | 25 | ⚠ multi-counts (one-to-many through `orders`); banned by `AI_SQL_GENERATION` rule 8 |
| `parts.is_critical` | — | PASS ⚠ | 3 | ⚠ multi-counts (one-to-many through `orders`); banned by `AI_SQL_GENERATION` rule 8 |
| `plants.plant_name` | ✅ | PASS | 12 | None |
| `plants.plant_region` | ✅ | PASS | 3 | None |
| `plants.plant_country` | ✅ | PASS | 9 | None |
| `plants.plant_type` | ✅ | PASS | 3 | None |
| `customers.customer_segment` | ✅ | PASS | 3 | None |
| `customers.customer_region` | ✅ | PASS | 3 | None |
| `orders.order_date` | ✅ | PASS | 370 | None |
| `orders.order_month` | ✅ | PASS | 13 | None |
| `orders.order_quarter` | ✅ | PASS | 4 | None |
| `orders.order_year` | ✅ | PASS | 2 | None |
| `orders.order_year_quarter` | ✅ | PASS | 5 | None |
| `orders.order_status` | ✅ | PASS | 3 | None |
| `orders.order_priority` | ✅ | PASS | 3 | None |
| `orders.order_week` | — | PASS ⚠ | 54 | GAP-2 extra dimension (not in §4) |
| `shipments.ship_date` | ✅ | PASS | 365 | None |
| `shipments.carrier` | ✅ | PASS | 7 | None |
| `shipments.shipment_status` | ✅ | PASS | 3 | None |
| `inventory.snapshot_date` | — | FAIL ✅ |  | SQL compilation error: The entities 'INVENTORY' and 'SHIPMENTS' are not related. Consider selecting calculations from entities that are related and have appropriate levels of granularity. |

## `order_lines.fill_rate`

| Dimension | In §4 | Result | Rows | Note / error |
|---|---|---|---|---|
| `suppliers.supplier_name` | — | PASS ⚠ | 120 | via `primary_sourcing`: one supplier per part, ties to the total (gate 3) |
| `suppliers.supplier_region` | — | PASS ⚠ | 3 | via `primary_sourcing`: one supplier per part, ties to the total (gate 3) |
| `suppliers.supplier_tier` | — | PASS ⚠ | 3 | via `primary_sourcing`: one supplier per part, ties to the total (gate 3) |
| `parts.part_name` | ✅ | PASS | 1164 | None |
| `parts.category` | ✅ | PASS | 6 | None |
| `parts.subcategory` | ✅ | PASS | 24 | None |
| `parts.is_critical` | ✅ | PASS | 2 | None |
| `plants.plant_name` | ✅ | PASS | 12 | None |
| `plants.plant_region` | ✅ | PASS | 3 | None |
| `plants.plant_country` | ✅ | PASS | 9 | None |
| `plants.plant_type` | ✅ | PASS | 3 | None |
| `customers.customer_segment` | ✅ | PASS | 3 | None |
| `customers.customer_region` | ✅ | PASS | 3 | None |
| `orders.order_date` | ✅ | PASS | 365 | None |
| `orders.order_month` | ✅ | PASS | 13 | None |
| `orders.order_quarter` | ✅ | PASS | 4 | None |
| `orders.order_year` | ✅ | PASS | 2 | None |
| `orders.order_year_quarter` | ✅ | PASS | 5 | None |
| `orders.order_status` | ✅ | PASS | 4 | None |
| `orders.order_priority` | ✅ | PASS | 3 | None |
| `orders.order_week` | — | PASS ⚠ | 53 | GAP-2 extra dimension (not in §4) |
| `shipments.ship_date` | — | PASS ⚠ | 365 | ⚠ multi-counts (one-to-many through `orders`); banned by `AI_SQL_GENERATION` rule 8 |
| `shipments.carrier` | — | PASS ⚠ | 8 | ⚠ multi-counts (one-to-many through `orders`); banned by `AI_SQL_GENERATION` rule 8 |
| `shipments.shipment_status` | — | PASS ⚠ | 4 | ⚠ multi-counts (one-to-many through `orders`); banned by `AI_SQL_GENERATION` rule 8 |
| `inventory.snapshot_date` | — | FAIL ✅ |  | SQL compilation error: The entities 'INVENTORY' and 'ORDER_LINES' are not related. Consider selecting calculations from entities that are related and have appropriate levels of granularity. |

## `inventory.days_of_inventory`

| Dimension | In §4 | Result | Rows | Note / error |
|---|---|---|---|---|
| `suppliers.supplier_name` | — | PASS ⚠ | 120 | via `primary_sourcing`: one supplier per part, ties to the total (gate 3) |
| `suppliers.supplier_region` | — | PASS ⚠ | 3 | via `primary_sourcing`: one supplier per part, ties to the total (gate 3) |
| `suppliers.supplier_tier` | — | PASS ⚠ | 3 | via `primary_sourcing`: one supplier per part, ties to the total (gate 3) |
| `parts.part_name` | ✅ | PASS | 1164 | None |
| `parts.category` | ✅ | PASS | 6 | None |
| `parts.subcategory` | ✅ | PASS | 24 | None |
| `parts.is_critical` | ✅ | PASS | 2 | None |
| `plants.plant_name` | ✅ | PASS | 12 | None |
| `plants.plant_region` | ✅ | PASS | 3 | None |
| `plants.plant_country` | ✅ | PASS | 9 | None |
| `plants.plant_type` | ✅ | PASS | 3 | None |
| `customers.customer_segment` | — | FAIL ✅ |  | SQL compilation error: The entities 'CUSTOMERS' and 'INVENTORY' are not related. Consider selecting calculations from entities that are related and have appropriate levels of granularity. |
| `customers.customer_region` | — | FAIL ✅ |  | SQL compilation error: The entities 'CUSTOMERS' and 'INVENTORY' are not related. Consider selecting calculations from entities that are related and have appropriate levels of granularity. |
| `orders.order_date` | — | FAIL ✅ |  | SQL compilation error: The entities 'ORDERS' and 'INVENTORY' are not related. Consider selecting calculations from entities that are related and have appropriate levels of granularity. |
| `orders.order_month` | — | FAIL ✅ |  | SQL compilation error: The entities 'ORDERS' and 'INVENTORY' are not related. Consider selecting calculations from entities that are related and have appropriate levels of granularity. |
| `orders.order_quarter` | — | FAIL ✅ |  | SQL compilation error: The entities 'ORDERS' and 'INVENTORY' are not related. Consider selecting calculations from entities that are related and have appropriate levels of granularity. |
| `orders.order_year` | — | FAIL ✅ |  | SQL compilation error: The entities 'ORDERS' and 'INVENTORY' are not related. Consider selecting calculations from entities that are related and have appropriate levels of granularity. |
| `orders.order_year_quarter` | — | FAIL ✅ |  | SQL compilation error: The entities 'ORDERS' and 'INVENTORY' are not related. Consider selecting calculations from entities that are related and have appropriate levels of granularity. |
| `orders.order_status` | — | FAIL ✅ |  | SQL compilation error: The entities 'ORDERS' and 'INVENTORY' are not related. Consider selecting calculations from entities that are related and have appropriate levels of granularity. |
| `orders.order_priority` | — | FAIL ✅ |  | SQL compilation error: The entities 'ORDERS' and 'INVENTORY' are not related. Consider selecting calculations from entities that are related and have appropriate levels of granularity. |
| `orders.order_week` | — | FAIL ✅ |  | SQL compilation error: The entities 'ORDERS' and 'INVENTORY' are not related. Consider selecting calculations from entities that are related and have appropriate levels of granularity. |
| `shipments.ship_date` | — | FAIL ✅ |  | SQL compilation error: The entities 'SHIPMENTS' and 'INVENTORY' are not related. Consider selecting calculations from entities that are related and have appropriate levels of granularity. |
| `shipments.carrier` | — | FAIL ✅ |  | SQL compilation error: The entities 'SHIPMENTS' and 'INVENTORY' are not related. Consider selecting calculations from entities that are related and have appropriate levels of granularity. |
| `shipments.shipment_status` | — | FAIL ✅ |  | SQL compilation error: The entities 'SHIPMENTS' and 'INVENTORY' are not related. Consider selecting calculations from entities that are related and have appropriate levels of granularity. |
| `inventory.snapshot_date` | ✅ | PASS | 1 | None |

## `shipments.avg_landed_cost`

| Dimension | In §4 | Result | Rows | Note / error |
|---|---|---|---|---|
| `suppliers.supplier_name` | — | FAIL ✅ |  | Unsupported feature 'Multi-path in many-to-many relationship'. |
| `suppliers.supplier_region` | — | FAIL ✅ |  | Unsupported feature 'Multi-path in many-to-many relationship'. |
| `suppliers.supplier_tier` | — | FAIL ✅ |  | Unsupported feature 'Multi-path in many-to-many relationship'. |
| `parts.part_name` | — | PASS ⚠ | 1165 | ⚠ multi-counts (one-to-many through `orders`); banned by `AI_SQL_GENERATION` rule 8 |
| `parts.category` | — | PASS ⚠ | 7 | ⚠ multi-counts (one-to-many through `orders`); banned by `AI_SQL_GENERATION` rule 8 |
| `parts.subcategory` | — | PASS ⚠ | 25 | ⚠ multi-counts (one-to-many through `orders`); banned by `AI_SQL_GENERATION` rule 8 |
| `parts.is_critical` | — | PASS ⚠ | 3 | ⚠ multi-counts (one-to-many through `orders`); banned by `AI_SQL_GENERATION` rule 8 |
| `plants.plant_name` | ✅ | PASS | 12 | None |
| `plants.plant_region` | ✅ | PASS | 3 | None |
| `plants.plant_country` | ✅ | PASS | 9 | None |
| `plants.plant_type` | ✅ | PASS | 3 | None |
| `customers.customer_segment` | ✅ | PASS | 3 | None |
| `customers.customer_region` | ✅ | PASS | 3 | None |
| `orders.order_date` | ✅ | PASS | 370 | None |
| `orders.order_month` | ✅ | PASS | 13 | None |
| `orders.order_quarter` | ✅ | PASS | 4 | None |
| `orders.order_year` | ✅ | PASS | 2 | None |
| `orders.order_year_quarter` | ✅ | PASS | 5 | None |
| `orders.order_status` | ✅ | PASS | 3 | None |
| `orders.order_priority` | ✅ | PASS | 3 | None |
| `orders.order_week` | — | PASS ⚠ | 54 | GAP-2 extra dimension (not in §4) |
| `shipments.ship_date` | ✅ | PASS | 365 | None |
| `shipments.carrier` | ✅ | PASS | 7 | None |
| `shipments.shipment_status` | ✅ | PASS | 3 | None |
| `inventory.snapshot_date` | — | FAIL ✅ |  | SQL compilation error: The entities 'INVENTORY' and 'SHIPMENTS' are not related. Consider selecting calculations from entities that are related and have appropriate levels of granularity. |
