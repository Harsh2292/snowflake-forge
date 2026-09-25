# Reference — Querying a semantic view with `SEMANTIC_VIEW()`

| | |
|---|---|
| **Sources** | <https://docs.snowflake.com/en/sql-reference/constructs/semantic_view> |
| | <https://docs.snowflake.com/en/user-guide/views-semantic/querying> |
| **Fetched** | 2026-09-24 (raw `.md` versions) |
| **Used by** | `forge_data.get_metric()` / `get_all_metrics()` (C02), Tab 2 + Tab 4 (C03), C04 tests |

---

## 1. Syntax

`SEMANTIC_VIEW(...)` goes in the `FROM` clause of a `SELECT`.

```sql
SEMANTIC_VIEW(
  [<namespace>.]<semantic_view_name>
  [ { METRICS <metric_expr> [ [AS] <alias> ] [, ...]
    | FACTS   <fact_expr> [, ...] } ]
  [ DIMENSIONS <dimension_expr> [ [AS] <alias> ] [, ...] ]
  [ WHERE <predicate> ]
)
```

### Clause rules (from usage notes)

| Rule | Consequence for us |
|------|--------------------|
| At least one of `METRICS`, `DIMENSIONS`, `FACTS` is required. | — |
| **`FACTS` and `METRICS` cannot appear in the same `SEMANTIC_VIEW` clause.** | We only ever use `METRICS` (+ `DIMENSIONS`). Never `FACTS`. |
| **Clause order = output column order.** `DIMENSIONS` first → dimension columns first. | Always write `DIMENSIONS` before `METRICS` so DataFrames come out `[dim, metric]` (matches contract §5.2). |
| Within a clause, items appear in the order listed. | — |
| `WHERE` may reference dimensions and facts only (not metrics). It is applied **before** metrics are computed. | Filter by region/date in `WHERE`; never filter on a metric there. |
| Private facts/metrics can't be queried or used in `WHERE`. | — |
| Wildcard must be table-qualified: `plants.*` OK, bare `*` not allowed. | — |
| Result can be used in `JOIN`, `PIVOT`, `UNPIVOT`, `GROUP BY`, CTEs, and have `ORDER BY` / `LIMIT` outside. | `ORDER BY` goes **outside** the parentheses. |

---

## 2. Naming and output columns

- Names can be qualified (`shipments.on_time_delivery_rate`) or unqualified. **Unqualified
  only works if the name is unique across the whole view** (a metric and a dimension sharing
  a name forces qualification). → We always qualify, exactly as contract §3/§4 lists them.
- **Output column headers use the unqualified name, uppercased.**
  `plants.plant_region` → `PLANT_REGION`; `shipments.on_time_delivery_rate` →
  `ON_TIME_DELIVERY_RATE`. (Docs example: `customer.customer_order_count` → column
  `CUSTOMER_ORDER_COUNT`.)
- If two selected items share an unqualified name, the columns collide — use `AS <alias>`.
  Our contract's names are all distinct, so this doesn't arise.

Confirms contract §5.2's note. ✅

---

## 3. Granularity — which metric × dimension pairs are legal

Verbatim rule:

> If you specify a dimension and a metric, the logical table for the dimension must be
> related to the logical table for the metric. In addition, the logical table for the
> dimension must have an **equal or lower level of granularity** than the logical table
> for the metric.

In plain terms: you can break a metric down by attributes of **its own table or any
"parent" table it rolls up to** (many shipments → one plant, so shipments × plant is fine).
You can't break it down by a "child" table, or by an unrelated one.

The documented failure:

```text
010234 (42601): SQL compilation error:
Invalid dimension specified: The dimension entity 'ORDERS' must be related to and
  have an equal or lower level of granularity compared to the base metric or dimension entity 'CUSTOMER'.
```

→ Error code **`010234`**, SQLSTATE **`42601`**. The C04 test
`days_of_inventory × orders.*` should assert this code.

### Contract §4 pairings checked against the rule

| Metric (base table) | Contract says valid | Why it holds |
|--------------------|--------------------|--------------|
| `on_time_delivery_rate` (shipments) | plants, orders, shipments, customers | shipment → order → customer; shipment → plant. All parents. ✅ |
| `fill_rate` (order_lines) | parts, plants, orders, customers | line → part, plant, order → customer. ✅ |
| `days_of_inventory` (inventory) | plants, parts, `inventory.snapshot_date` | inventory → plant, part. ✅ Orders/shipments are not parents of inventory → **010234**, as the contract predicts. ✅ |
| `avg_landed_cost` (shipments) | plants, orders, shipments, customers | Same path as OTD. ✅ |

Consistent with the docs, provided CoCo defines the relationships in that direction (B08).

### Discovering legal dimensions at runtime

```sql
SHOW SEMANTIC DIMENSIONS IN SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  FOR METRIC on_time_delivery_rate;
```

Returns `table_name, name, data_type, required, synonyms, comment` — one row per legal
dimension. A good source for artifact `06_dimension_matrix.md`.

---

## 4. Privileges

- A role that doesn't own the view needs **`SELECT` on the semantic view**.
- It does **not** need `SELECT` on the underlying tables (same as standard views).

---

## 5. Our query templates (contract §5.1 / §5.2)

```sql
-- Metric only → 1 row, 1 column ON_TIME_DELIVERY_RATE
SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  METRICS shipments.on_time_delivery_rate
);

-- Metric by dimension → columns PLANT_REGION, ON_TIME_DELIVERY_RATE
SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  DIMENSIONS plants.plant_region
  METRICS shipments.on_time_delivery_rate
) ORDER BY plant_region;

-- All four metrics in one row. Allowed: several metrics in one METRICS clause.
-- (Each metric aggregates at its own base-table grain; no dimensions = grand totals.)
SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  METRICS shipments.on_time_delivery_rate,
          order_lines.fill_rate,
          inventory.days_of_inventory,
          shipments.avg_landed_cost
);
```

**INFERRED**: the combined four-metric query should work because no dimension is
involved, so no granularity rule applies. If B08 shows it fails, fall back to four
single-metric queries. Track this in artifact `06`.

### Building these safely in Python

Identifiers can't be bind parameters. Build the SQL only from the contract allow-list,
never from user text:

```python
assert metric_key in METRICS                  # contract §3
assert dimension is None or dimension in VALID_DIMENSIONS[metric_key]   # contract §4
```

---

## 6. Alternative: standard SQL against the view (not used, for reference)

```sql
SELECT plant_region, AGG(on_time_delivery_rate)
  FROM SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  GROUP BY plant_region;
```

Metrics must go through `AGG()`. This gets rewritten internally into `SEMANTIC_VIEW(...)`
(`GROUP BY` → `DIMENSIONS`). We stick to the explicit `SEMANTIC_VIEW()` form because
contract §5 specifies it and it matches what judges will see in Snowsight.
