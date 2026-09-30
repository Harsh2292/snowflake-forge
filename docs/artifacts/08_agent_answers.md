# Artifact 08 — Agent evaluation: every question, answer, SQL, pass/fail, latency

- **Build step**: B08m (event account; replayed from the repo), after B09a. Runs Claude Code's C11, `eval/`
- **Captured at**: 2026-09-30T18:53:09Z (evaluation run 2026-10-01 01:43–01:49 UTC; Q18, Q22 and Q23 re-run last, after the view change below)
- **Captured by**: CoCo
- **Agent**: `SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT` (`agent/01_agent.sql`), model `claude-sonnet-4-5`; tools `supply_chain_analyst` (Cortex Analyst on `SUPPLY_CHAIN_SV`, 14 verified queries) and `data_health` (`SP_DATA_HEALTH`). B09a removed `data_to_chart` and the SQL block in answers, and added a no-chart instruction
- **Caller**: role `FORGE_ADMIN`, warehouse `FORGE_WH`, through `OPS.SP_RUN_EVAL` (`DATA_AGENT_RUN`, non-streaming, a new thread per question); 4 batches run concurrently
- **Run label**: `b10-v2`: the 30 questions of `eval/10_questions.sql`. Previous run: `b10-baseline` (B10, old account): 27/30, p50 17.7 s, p95 48.8 s
- **Query** (99_run.sql step 3 with the label `b10-v2`, plus `INPUT_QUERY` from `EVAL_QUESTIONS`):

```sql
SELECT QUESTION_ID, CATEGORY, EXPECTED_BEHAVIOUR, OBSERVED_BEHAVIOUR, PASSED, FAIL_REASON,
       LATENCY_MS, ARRAY_TO_STRING(TOOLS_USED, ', ') AS TOOLS, ANSWER_TEXT, AGENT_SQL
FROM SUPPLY_CHAIN_FORGE.OPS.EVAL_RESULTS
WHERE RUN_LABEL = 'b10-v2'
QUALIFY ROW_NUMBER() OVER (PARTITION BY QUESTION_ID ORDER BY RUN_TS DESC) = 1
ORDER BY QUESTION_ID;
```

## Summary (computed from the 30 latest rows, in `SP_RUN_EVAL`'s shape)

```json
{
  "by_category": {
    "AMBIGUOUS": {
      "n": 2,
      "passed": 2
    },
    "CANONICAL": {
      "n": 8,
      "passed": 8
    },
    "COST": {
      "n": 2,
      "passed": 2
    },
    "COUNT_TOTAL": {
      "n": 3,
      "passed": 3
    },
    "CROSS_GRAIN": {
      "n": 1,
      "passed": 1
    },
    "CROSS_SYSTEM": {
      "n": 1,
      "passed": 1
    },
    "DATA_HEALTH": {
      "n": 1,
      "passed": 1
    },
    "INVENTORY": {
      "n": 2,
      "passed": 2
    },
    "LOOKUP": {
      "n": 2,
      "passed": 2
    },
    "MULTILINGUAL": {
      "n": 1,
      "passed": 1
    },
    "MULTI_PART": {
      "n": 2,
      "passed": 0
    },
    "OUT_OF_SCOPE": {
      "n": 2,
      "passed": 2
    },
    "REVENUE": {
      "n": 1,
      "passed": 1
    },
    "SUPPLIER": {
      "n": 2,
      "passed": 2
    }
  },
  "latency_ms": {
    "max": 41224,
    "p50": 12336.0,
    "p95": 36470.4
  },
  "pass_rate": 0.9333,
  "passed": 28,
  "questions": 30,
  "run_label": "b10-v2"
}
```

**Pass rate 28/30 = 93.3%.** Latency: p50 12.3 s, p95 36.5 s, max 41.2 s, mean 18.5 s.

| Category | Passed |
|---|---|
| AMBIGUOUS | 2/2 |
| CANONICAL | 8/8 |
| COST | 2/2 |
| COUNT_TOTAL | 3/3 |
| CROSS_GRAIN | 1/1 |
| CROSS_SYSTEM | 1/1 |
| DATA_HEALTH | 1/1 |
| INVENTORY | 2/2 |
| LOOKUP | 2/2 |
| MULTILINGUAL | 1/1 |
| MULTI_PART | 0/2 |
| OUT_OF_SCOPE | 2/2 |
| REVENUE | 1/1 |
| SUPPLIER | 2/2 |

## All questions

| ID | Category | Expected | Observed | Pass | Latency (s) | Tools |
|---|---|---|---|---|---|---|
| Q01 | CANONICAL | ANSWER | ANSWER | PASS | 13.0 | system_execute_sql |
| Q02 | CANONICAL | ANSWER | ANSWER | PASS | 11.1 | system_execute_sql |
| Q03 | CANONICAL | ANSWER | ANSWER | PASS | 11.6 | system_execute_sql |
| Q04 | CANONICAL | ANSWER | ANSWER | PASS | 8.1 | system_execute_sql |
| Q05 | CANONICAL | ANSWER | ANSWER | PASS | 10.3 | system_execute_sql |
| Q06 | CANONICAL | ANSWER | ANSWER | PASS | 11.2 | system_execute_sql |
| Q07 | CANONICAL | ANSWER | ANSWER | PASS | 11.3 | system_execute_sql |
| Q08 | CANONICAL | ANSWER | ANSWER | PASS | 9.7 | system_execute_sql |
| Q09 | LOOKUP | ANSWER | ANSWER | PASS | 29.8 | supply_chain_analyst, system_execute_sql, system_agentic_semantic_context |
| Q10 | LOOKUP | ANSWER | ANSWER | PASS | 24.6 | supply_chain_analyst, system_execute_sql, system_agentic_semantic_context |
| Q11 | COUNT_TOTAL | ANSWER | ANSWER | PASS | 26.1 | supply_chain_analyst, system_execute_sql, system_agentic_semantic_context |
| Q12 | COUNT_TOTAL | ANSWER | ANSWER | PASS | 23.8 | supply_chain_analyst, system_agentic_semantic_context, system_execute_sql |
| Q13 | COUNT_TOTAL | ANSWER | ANSWER | PASS | 26.1 | supply_chain_analyst, system_execute_sql, system_agentic_semantic_context |
| Q14 | SUPPLIER | ANSWER | ANSWER | PASS | 31.0 | supply_chain_analyst, system_execute_sql, system_agentic_semantic_context |
| Q15 | SUPPLIER | ANSWER | ANSWER | PASS | 8.2 | system_execute_sql |
| Q16 | INVENTORY | ANSWER | ANSWER | PASS | 32.9 | supply_chain_analyst, system_execute_sql, system_agentic_semantic_context |
| Q17 | INVENTORY | ANSWER | ANSWER | PASS | 10.7 | system_execute_sql |
| Q18 | COST | ANSWER | ANSWER | PASS | 27.3 | supply_chain_analyst, system_execute_sql, system_agentic_semantic_context |
| Q19 | COST | ANSWER | ANSWER | PASS | 8.4 | system_execute_sql |
| Q20 | CROSS_SYSTEM | ANSWER | ANSWER | PASS | 29.1 | supply_chain_analyst, system_execute_sql, system_agentic_semantic_context |
| Q21 | REVENUE | ANSWER | ANSWER | PASS | 10.1 | system_execute_sql |
| Q22 | MULTI_PART | ANSWER | ANSWER | **FAIL** | 41.2 | supply_chain_analyst, system_execute_sql, system_agentic_semantic_context |
| Q23 | MULTI_PART | ANSWER | ANSWER | **FAIL** | 39.4 | supply_chain_analyst, system_execute_sql, system_agentic_semantic_context |
| Q24 | OUT_OF_SCOPE | REFUSE | REFUSE | PASS | 9.4 | — |
| Q25 | OUT_OF_SCOPE | REFUSE | REFUSE | PASS | 9.5 | — |
| Q26 | AMBIGUOUS | CLARIFY | CLARIFY | PASS | 11.4 | — |
| Q27 | AMBIGUOUS | CLARIFY | CLARIFY | PASS | 9.8 | — |
| Q28 | MULTILINGUAL | ANSWER | ANSWER | PASS | 26.7 | supply_chain_analyst, system_agentic_semantic_context, system_execute_sql |
| Q29 | DATA_HEALTH | ANSWER | ANSWER | PASS | 14.9 | data_health, generic |
| Q30 | CROSS_GRAIN | REFUSE | CLARIFY | PASS | 17.2 | supply_chain_analyst, system_agentic_semantic_context |

## Failures

- **Q22** (1. What is our on-time delivery rate? 2. What is our fill rate?): **Agent miss (Analyst).** The agent stated fill rate 88.1%; the governed `order_lines.fill_rate` for the last 12 months is 92.6%, so Analyst's own fill-rate CTE for the two-part question is wrong (its on-time delivery, 87.5%, is right). The public app doesn't take this path: C14's router splits the question and answers both parts from the semantic view.
  Runner's reason, verbatim: `1 of 2 ground-truth numbers found in the agent results (agent SQL: query 1: SQL compilation error: Object '__ORDER_LINES' does not exist or not authorized. Your primary role FORGE_ADMIN or one of your secondary roles must have at least one privilege granted on TABLE __ORDER_LINES. | query 2: SQL compilation error: Object '__SHIPMENTS' does not exist or not authorized. Your primary role FORGE_ADMIN or one of your secondary roles must have at least one privilege granted on TABLE __SHIPMENTS. | )`
- **Q23** (Two questions: 1) What is our average landed cost per shipment? 2) How many shipments did we send in the last 12 months?): **Runner limitation, the answer is right.** The agent answered $604.81 average landed cost and 95,707 shipments; both equal the governed values. The runner re-runs only single read-only SELECTs, and Analyst's SQL came back as several statements.
  Runner's reason, verbatim: `no agent query could be re-run: query 1: not re-run (not a single read-only SELECT) | query 2: not re-run (not a single read-only SELECT) | query 3: SQL compilation error: error line 11 at position 2 invalid identifier 'AVG_LANDED_COST' | query 4: SQL compilation error: error line 8 at position 2 invalid identifier 'SHIPMENT_COUNT' | query 5: not re-run (not a single read-only SELECT) | `

## Each question: answer and SQL (verbatim from `EVAL_RESULTS`)

### Q01 · CANONICAL · PASS · 13.0 s

**Question**: What is our overall on-time delivery rate?

**Answer**:

````text
Your overall on-time delivery rate is **87.5%** for the last 12 months by ship date.
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV METRICS shipments.on_time_delivery_rate WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE())

SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV METRICS shipments.on_time_delivery_rate WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE())
-- Generated by Cortex
;
````

### Q02 · CANONICAL · PASS · 11.1 s

**Question**: What is on-time delivery rate by region?

**Answer**:

````text
On-time delivery rate for the last 12 months by ship date is highest in EMEA at 88.4%, followed by AMER at 87.4% and APAC at 86.8%.
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS plants.plant_region METRICS shipments.on_time_delivery_rate WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE()) ORDER BY plant_region

SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS plants.plant_region METRICS shipments.on_time_delivery_rate WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE()) ORDER BY plant_region
-- Generated by Cortex
;
````

### Q03 · CANONICAL · PASS · 11.6 s

**Question**: What was on-time delivery rate by quarter?

**Answer**:

````text
On-time delivery improved from 85.4% in Q3 2025 to 88.0% in Q3 2026, based on shipments shipped in the last 12 months:
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS orders.order_year_quarter METRICS shipments.on_time_delivery_rate WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE()) ORDER BY order_year_quarter

SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS orders.order_year_quarter METRICS shipments.on_time_delivery_rate WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE()) ORDER BY order_year_quarter
-- Generated by Cortex
;
````

### Q04 · CANONICAL · PASS · 8.1 s

**Question**: What is our fill rate?

**Answer**:

````text
Your fill rate is 92.6% for the last 12 months by order date.
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV METRICS order_lines.fill_rate WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE()) AND orders.order_date <= CURRENT_DATE())

SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV METRICS order_lines.fill_rate WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE()) AND orders.order_date <= CURRENT_DATE())
-- Generated by Cortex
;
````

### Q05 · CANONICAL · PASS · 10.3 s

**Question**: What is fill rate by product category?

**Answer**:

````text
Fill rate ranges from 92.1% to 94.9% across product categories for orders placed in the last 12 months.

 

Electronics has the highest fill rate at 94.9%, while Packaging has the lowest at 92.1%.
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS parts.category METRICS order_lines.fill_rate WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE()) AND orders.order_date <= CURRENT_DATE()) ORDER BY category

SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS parts.category METRICS order_lines.fill_rate WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE()) AND orders.order_date <= CURRENT_DATE()) ORDER BY category
-- Generated by Cortex
;
````

### Q06 · CANONICAL · PASS · 11.2 s

**Question**: What are days of inventory by plant?

**Answer**:

````text
Days of inventory range from 34.6 to 37.7 days across the 12 plants in the latest inventory snapshot, with Frankfurt Central Distribution lowest at 34.6 days and Long Beach Maritime Hub highest at 37.7 days.
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS plants.plant_name METRICS inventory.days_of_inventory WHERE inventory.snapshot_date = (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY)) ORDER BY plant_name

SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS plants.plant_name METRICS inventory.days_of_inventory WHERE inventory.snapshot_date = (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY)) ORDER BY plant_name
-- Generated by Cortex
;
````

### Q07 · CANONICAL · PASS · 11.3 s

**Question**: What is average landed cost by region?

**Answer**:

````text
Average landed cost over the last 12 months by ship date is $568.19 for AMER, $664.26 for APAC, and $589.44 for EMEA.
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS plants.plant_region METRICS shipments.avg_landed_cost WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE()) ORDER BY plant_region

SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS plants.plant_region METRICS shipments.avg_landed_cost WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE()) ORDER BY plant_region
-- Generated by Cortex
;
````

### Q08 · CANONICAL · PASS · 9.7 s

**Question**: Which plants have the worst on-time delivery?

**Answer**:

````text
The plants with the worst on-time delivery over the last 12 months by ship date are Singapore Logistics Gateway (86.2%), Chennai Heavy Production (86.8%), and Long Beach Maritime Hub (87.0%).
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS plants.plant_name METRICS shipments.on_time_delivery_rate WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE()) ORDER BY on_time_delivery_rate ASC LIMIT 3

SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS plants.plant_name METRICS shipments.on_time_delivery_rate WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE()) ORDER BY on_time_delivery_rate ASC LIMIT 3
-- Generated by Cortex
;
````

### Q09 · LOOKUP · PASS · 29.8 s

**Question**: What is the status of order ORD000261581?

**Answer**:

````text
Order ORD000261581 has been **DELIVERED**. It was placed on September 30, 2021 for Keystone Power Systems - Division 0529 (EMEA region) with normal priority. The order had 2 line items totaling 95 units, all of which were shipped, with a total value of $17,303.39.
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT 
    o.order_id,
    o.order_date,
    o.order_status,
    o.order_priority,
    c.customer_name,
    c.customer_region,
    COUNT(DISTINCT ol.line_id) AS line_count,
    SUM(ol.quantity_ordered) AS total_units_ordered,
    SUM(ol.quantity_shipped) AS total_units_shipped,
    SUM(ol.quantity_ordered * ol.unit_price) AS total_order_value
FROM __orders o
LEFT JOIN __customers c ON o.customer_id = c.customer_id
LEFT JOIN __order_lines ol ON o.order_id = ol.order_id
WHERE o.order_id = 'ORD000261581'
GROUP BY o.order_id, o.order_date, o.order_status, o.order_priority, c.customer_name, c.customer_region


WITH __orders AS (
  SELECT
    order_date,
    order_id,
    order_priority,
    order_status,
    customer_id
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER
), __customers AS (
  SELECT
    customer_id,
    customer_name,
    region AS customer_region
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_CUSTOMER
), __order_lines AS (
  SELECT
    line_id,
    order_id,
    quantity_ordered,
    quantity_shipped,
    unit_price
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER_LINE
)
SELECT
  o.order_id,
  o.order_date,
  o.order_status,
  o.order_priority,
  c.customer_name,
  c.customer_region,
  COUNT(DISTINCT ol.line_id) AS line_count,
  SUM(ol.quantity_ordered) AS total_units_ordered,
  SUM(ol.quantity_shipped) AS total_units_shipped,
  SUM(ol.quantity_ordered * ol.unit_price) AS total_order_value
FROM __orders AS o
LEFT JOIN __customers AS c
  ON o.customer_id = c.customer_id
LEFT JOIN __order_lines AS ol
  ON o.order_id = ol.order_id
WHERE
  o.order_id = 'ORD000261581'
GROUP BY
  o.order_id,
  o.order_date,
  o.order_status,
  o.order_priority,
  c.customer_name,
  c.customer_region /* Generated by Cortex */;
````

### Q10 · LOOKUP · PASS · 24.6 s

**Question**: Which carrier shipped order ORD000261581, and on what date was it delivered?

**Answer**:

````text
Order ORD000261581 was shipped by **Maersk Logistics** and delivered on **October 16, 2021**.
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT 
    s.order_id,
    s.shipment_id,
    s.carrier,
    s.ship_date,
    s.actual_delivery_date
FROM __shipments s
WHERE s.order_id = 'ORD000261581'
ORDER BY s.ship_date


WITH __shipments AS (
  SELECT
    actual_delivery_date,
    carrier,
    shipment_id,
    ship_date,
    order_id
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT
)
SELECT
  s.order_id,
  s.shipment_id,
  s.carrier,
  s.ship_date,
  s.actual_delivery_date
FROM __shipments AS s
WHERE
  s.order_id = 'ORD000261581'
ORDER BY
  s.ship_date /* Generated by Cortex */;
````

### Q11 · COUNT_TOTAL · PASS · 26.1 s

**Question**: How many shipments did we send in the last 12 months?

**Answer**:

````text
We sent 95,707 shipments in the last 12 months, by ship date.
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT COUNT(shipment_id) AS shipment_count
FROM __shipments
WHERE ship_date > DATEADD(MONTH, -12, CURRENT_DATE())
  AND ship_date <= CURRENT_DATE()

WITH __shipments AS (
  SELECT
    shipment_id,
    ship_date
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT
)
SELECT
  COUNT(shipment_id) AS shipment_count
FROM __shipments
WHERE
  ship_date > DATEADD(MONTH, -12, CURRENT_DATE)
  AND ship_date <= CURRENT_DATE /* Generated by Cortex */;
````

### Q12 · COUNT_TOTAL · PASS · 23.8 s

**Question**: How many orders are open right now?

**Answer**:

````text
There are 723 open orders right now.
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT COUNT(order_id) AS open_order_count
FROM __orders
WHERE order_status = 'OPEN'

WITH __orders AS (
  SELECT
    order_id,
    order_status
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER
)
SELECT
  COUNT(order_id) AS open_order_count
FROM __orders
WHERE
  order_status = 'OPEN' /* Generated by Cortex */;
````

### Q13 · COUNT_TOTAL · PASS · 26.1 s

**Question**: How many suppliers do we have?

**Answer**:

````text
We have 150 suppliers.
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT supplier_count FROM __suppliers

WITH __suppliers AS (
  SELECT
    supplier_id
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SUPPLIER
)
SELECT
  supplier_count
FROM __suppliers /* Generated by Cortex */;

SELECT COUNT(DISTINCT supplier_id) AS supplier_count FROM __suppliers

WITH __suppliers AS (
  SELECT
    supplier_id
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SUPPLIER
)
SELECT
  COUNT(DISTINCT supplier_id) AS supplier_count
FROM __suppliers /* Generated by Cortex */;
````

### Q14 · SUPPLIER · PASS · 31.0 s

**Question**: What is the average supplier lead time for each supplier tier?

**Answer**:

````text
The average supplier lead time for Tier 1 suppliers is 11.2 days, for Tier 2 is 22.8 days, and for Tier 3 is 30.0 days.
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT 
    supplier_tier,
    AVG(lead_time_days) AS avg_lead_time_days
FROM __suppliers
GROUP BY supplier_tier
ORDER BY supplier_tier

WITH __suppliers AS (
  SELECT
    supplier_tier,
    lead_time_days
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SUPPLIER
)
SELECT
  supplier_tier,
  AVG(lead_time_days) AS avg_lead_time_days
FROM __suppliers
GROUP BY
  supplier_tier
ORDER BY
  supplier_tier /* Generated by Cortex */;
````

### Q15 · SUPPLIER · PASS · 8.2 s

**Question**: What is the average supplier reliability score by supplier region?

**Answer**:

````text
EMEA has the highest average supplier reliability score at 0.88, followed by APAC at 0.87 and AMER at 0.86.
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS suppliers.supplier_region METRICS suppliers.avg_reliability_score) ORDER BY supplier_region

SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS suppliers.supplier_region METRICS suppliers.avg_reliability_score) ORDER BY supplier_region
-- Generated by Cortex
;
````

### Q16 · INVENTORY · PASS · 32.9 s

**Question**: How many part and plant combinations are below their reorder point in the latest inventory snapshot?

**Answer**:

````text
14 part and plant combinations are below their reorder point in the latest inventory snapshot.
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT 
    parts_below_reorder_point
FROM __inventory
WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY)


WITH __inventory AS (
  SELECT
    snapshot_date,
    quantity_on_hand,
    reorder_point
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY
)
SELECT
  parts_below_reorder_point
FROM __inventory
WHERE
  snapshot_date = (
    SELECT
      MAX(snapshot_date)
    FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY
  ) /* Generated by Cortex */;


SELECT 
    COUNT_IF(quantity_on_hand < reorder_point) as parts_below_reorder_point
FROM __inventory
WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM __inventory)


WITH __inventory AS (
  SELECT
    snapshot_date,
    quantity_on_hand,
    reorder_point
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY
)
SELECT
  COUNT_IF(quantity_on_hand < reorder_point) AS parts_below_reorder_point
FROM __inventory
WHERE
  snapshot_date = (
    SELECT
      MAX(snapshot_date)
    FROM __inventory
  ) /* Generated by Cortex */;
````

### Q17 · INVENTORY · PASS · 10.7 s

**Question**: For each plant, how many parts are below their reorder point right now?

**Answer**:

````text
In the latest inventory snapshot, Shanghai Mega Manufacturing and Long Beach Maritime Hub each have 3 parts below their reorder point, the highest across all plants.
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS plants.plant_name METRICS inventory.parts_below_reorder_point WHERE inventory.snapshot_date = (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY)) ORDER BY parts_below_reorder_point DESC

SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS plants.plant_name METRICS inventory.parts_below_reorder_point WHERE inventory.snapshot_date = (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY)) ORDER BY parts_below_reorder_point DESC
-- Generated by Cortex
;
````

### Q18 · COST · PASS · 27.3 s

**Question**: What is our average freight cost per shipment?

**Answer**:

````text
Your average freight cost per shipment is $468.29 over the last 12 months by ship date (95,420 shipments with freight cost data out of 95,707 total shipments).
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT 
    AVG(freight_cost) AS avg_freight_cost_per_shipment,
    COUNT(shipment_id) AS total_shipments,
    COUNT(freight_cost) AS shipments_with_freight_cost
FROM __shipments
WHERE ship_date > DATEADD(MONTH, -12, CURRENT_DATE())
  AND ship_date <= CURRENT_DATE()


WITH __shipments AS (
  SELECT
    shipment_id,
    ship_date,
    freight_cost
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT
)
SELECT
  AVG(freight_cost) AS avg_freight_cost_per_shipment,
  COUNT(shipment_id) AS total_shipments,
  COUNT(freight_cost) AS shipments_with_freight_cost
FROM __shipments
WHERE
  ship_date > DATEADD(MONTH, -12, CURRENT_DATE)
  AND ship_date <= CURRENT_DATE /* Generated by Cortex */;
````

### Q19 · COST · PASS · 8.4 s

**Question**: What is average landed cost by carrier?

**Answer**:

````text
Maersk Logistics had the highest average landed cost at $859.30, while FedEx Freight had the lowest at $418.28 over the last 12 months by ship date.
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS shipments.carrier METRICS shipments.avg_landed_cost WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE()) ORDER BY avg_landed_cost DESC

SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS shipments.carrier METRICS shipments.avg_landed_cost WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE()) ORDER BY avg_landed_cost DESC
-- Generated by Cortex
;
````

### Q20 · CROSS_SYSTEM · PASS · 29.1 s

**Question**: Does order priority make a difference to on-time delivery? Show the on-time delivery rate by order priority.

**Answer**:

````text
Yes, order priority makes a difference to on-time delivery: HIGH priority orders achieve 89.5% on-time delivery, compared to 87.3% for NORMAL priority and 86.5% for LOW priority (last 12 months, by ship date).
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT 
    __orders.order_priority,
    COUNT(DISTINCT __shipments.shipment_id) AS total_shipments,
    COUNT(DISTINCT CASE WHEN __shipments.actual_delivery_date <= __shipments.promised_delivery_date 
                   THEN __shipments.shipment_id END) AS on_time_shipments,
    COUNT(DISTINCT CASE WHEN __shipments.actual_delivery_date <= __shipments.promised_delivery_date 
                   THEN __shipments.shipment_id END) / 
    NULLIF(COUNT(DISTINCT CASE WHEN __shipments.actual_delivery_date IS NOT NULL 
                            AND __shipments.promised_delivery_date IS NOT NULL 
                            THEN __shipments.shipment_id END), 0) AS on_time_delivery_rate
FROM __shipments
LEFT JOIN __orders ON __shipments.order_id = __orders.order_id
WHERE __shipments.ship_date > DATEADD(MONTH, -12, CURRENT_DATE)
  AND __shipments.ship_date <= CURRENT_DATE
  AND __shipments.actual_delivery_date IS NOT NULL
  AND __shipments.promised_delivery_date IS NOT NULL
GROUP BY __orders.order_priority
ORDER BY on_time_delivery_rate DESC NULLS LAST


WITH __shipments AS (
  SELECT
    actual_delivery_date,
    promised_delivery_date,
    shipment_id,
    ship_date,
    order_id
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT
), __orders AS (
  SELECT
    order_id,
    order_priority
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER
)
SELECT
  __orders.order_priority,
  COUNT(DISTINCT __shipments.shipment_id) AS total_shipments,
  COUNT(
    DISTINCT CASE
      WHEN __shipments.actual_delivery_date <= __shipments.promised_delivery_date
      THEN __shipments.shipment_id
    END
  ) AS on_time_shipments,
  COUNT(
    DISTINCT CASE
      WHEN __shipments.actual_delivery_date <= __shipments.promised_delivery_date
      THEN __shipments.shipment_id
    END
  ) / NULLIF(
    NULLIF(
      COUNT(
        DISTINCT CASE
          WHEN NOT __shipments.actual_delivery_date IS NULL
          AND NOT __shipments.promised_delivery_date IS NULL
          THEN __shipments.shipment_id
        END
      ),
      0
    ),
    0
  ) AS on_time_delivery_rate
FROM __shipments
LEFT JOIN __orders
  ON __shipments.order_id = __orders.order_id
WHERE
  __shipments.ship_date > DATEADD(MONTH, -12, CURRENT_DATE)
  AND __shipments.ship_date <= CURRENT_DATE
  AND NOT __shipments.actual_delivery_date IS NULL
  AND NOT __shipments.promised_delivery_date IS NULL
GROUP BY
  __orders.order_priority
ORDER BY
  on_time_delivery_rate DESC NULLS LAST /* Generated by Cortex */;
````

### Q21 · REVENUE · PASS · 10.1 s

**Question**: What was our revenue over the last 12 months?

**Answer**:

````text
Revenue was $10.06B over the last 12 months (by order date).
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV METRICS order_lines.total_revenue WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE()) AND orders.order_date <= CURRENT_DATE())

SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV METRICS order_lines.total_revenue WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE()) AND orders.order_date <= CURRENT_DATE())
-- Generated by Cortex
;
````

### Q22 · MULTI_PART · FAIL · 41.2 s

**Question**: 1. What is our on-time delivery rate? 2. What is our fill rate?

**Answer**:

````text
Your on-time delivery rate is 87.5% and your fill rate is 88.1%, both for the last 12 months (by ship date and order date respectively).
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT 
    SUM(quantity_shipped) / NULLIF(SUM(quantity_ordered), 0) AS fill_rate
FROM __order_lines
LEFT JOIN __orders ON __order_lines.order_id = __orders.order_id
WHERE __orders.order_date > DATEADD(MONTH, -12, CURRENT_DATE) 
  AND __orders.order_date <= CURRENT_DATE

SELECT 
    COUNT_IF(actual_delivery_date <= promised_delivery_date) / 
    NULLIF(COUNT_IF(actual_delivery_date IS NOT NULL AND promised_delivery_date IS NOT NULL), 0) AS on_time_delivery_rate
FROM __shipments
WHERE ship_date > DATEADD(MONTH, -12, CURRENT_DATE) 
  AND ship_date <= CURRENT_DATE

WITH __shipments AS (
  SELECT
    actual_delivery_date,
    promised_delivery_date,
    ship_date
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT
)
SELECT
  COUNT_IF(actual_delivery_date <= promised_delivery_date) / NULLIF(
    NULLIF(
      COUNT_IF(NOT actual_delivery_date IS NULL AND NOT promised_delivery_date IS NULL),
      0
    ),
    0
  ) AS on_time_delivery_rate
FROM __shipments
WHERE
  ship_date > DATEADD(MONTH, -12, CURRENT_DATE)
  AND ship_date <= CURRENT_DATE /* Generated by Cortex */;

WITH __order_lines AS (
  SELECT
    order_id,
    quantity_ordered,
    quantity_shipped
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER_LINE
), __orders AS (
  SELECT
    order_date,
    order_id
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER
)
SELECT
  SUM(quantity_shipped) / NULLIF(NULLIF(SUM(quantity_ordered), 0), 0) AS fill_rate
FROM __order_lines
LEFT JOIN __orders
  ON __order_lines.order_id = __orders.order_id
WHERE
  __orders.order_date > DATEADD(MONTH, -12, CURRENT_DATE)
  AND __orders.order_date <= CURRENT_DATE /* Generated by Cortex */;
````

### Q23 · MULTI_PART · FAIL · 39.4 s

**Question**: Two questions: 1) What is our average landed cost per shipment? 2) How many shipments did we send in the last 12 months?

**Answer**:

````text
1) Our average landed cost per shipment is $604.81, and 2) we sent 95,707 shipments over the last 12 months (by ship date).
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT 
  shipment_count
FROM __shipments
WHERE ship_date > DATEADD(MONTH, -12, CURRENT_DATE())
  AND ship_date <= CURRENT_DATE()



SELECT 
  avg_landed_cost
FROM __shipments
WHERE ship_date > DATEADD(MONTH, -12, CURRENT_DATE())
  AND ship_date <= CURRENT_DATE()


WITH __shipments AS (
  SELECT
    ship_date,
    duty_cost,
    freight_cost,
    handling_cost,
    freight_cost + duty_cost + handling_cost AS total_landed_cost
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT
)
SELECT
  avg_landed_cost
FROM __shipments
WHERE
  ship_date > DATEADD(MONTH, -12, CURRENT_DATE)
  AND ship_date <= CURRENT_DATE /* Generated by Cortex */;

WITH __shipments AS (
  SELECT
    shipment_id,
    ship_date
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT
)
SELECT
  shipment_count
FROM __shipments
WHERE
  ship_date > DATEADD(MONTH, -12, CURRENT_DATE)
  AND ship_date <= CURRENT_DATE /* Generated by Cortex */;


SELECT 
  AVG(total_landed_cost) AS avg_landed_cost
FROM __shipments
WHERE ship_date > DATEADD(MONTH, -12, CURRENT_DATE())
  AND ship_date <= CURRENT_DATE()



SELECT 
  COUNT(shipment_id) AS shipment_count
FROM __shipments
WHERE ship_date > DATEADD(MONTH, -12, CURRENT_DATE())
  AND ship_date <= CURRENT_DATE()


WITH __shipments AS (
  SELECT
    shipment_id,
    ship_date
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT
)
SELECT
  COUNT(shipment_id) AS shipment_count
FROM __shipments
WHERE
  ship_date > DATEADD(MONTH, -12, CURRENT_DATE)
  AND ship_date <= CURRENT_DATE /* Generated by Cortex */;

WITH __shipments AS (
  SELECT
    ship_date,
    duty_cost,
    freight_cost,
    handling_cost,
    freight_cost + duty_cost + handling_cost AS total_landed_cost
  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT
)
SELECT
  AVG(total_landed_cost) AS avg_landed_cost
FROM __shipments
WHERE
  ship_date > DATEADD(MONTH, -12, CURRENT_DATE)
  AND ship_date <= CURRENT_DATE /* Generated by Cortex */;
````

### Q24 · OUT_OF_SCOPE · PASS · 9.4 s

**Question**: What will the weather be in Mumbai tomorrow?

**Answer**:

````text
I can only answer questions about supply chain data—such as on-time delivery, fill rate, inventory levels, landed cost, orders, shipments, and information about parts, plants, customers, and suppliers. For weather information, you'll need to use a different resource.
````

### Q25 · OUT_OF_SCOPE · PASS · 9.5 s

**Question**: List the email addresses of all our customers.

**Answer**:

````text
Customer e-mail addresses are restricted data and not available through this system. I can help you with supply chain metrics like on-time delivery, fill rate, revenue by customer, or provide a list of customer names and locations if that would be useful.
````

### Q26 · AMBIGUOUS · PASS · 11.4 s

**Question**: How are we doing?

**Answer**:

````text
I can help you with supply chain performance! Which metric would you like to see?

- **On-time delivery** (% of shipments delivered on time)
- **Fill rate** (% of ordered quantity fulfilled)
- **Days of inventory** (current stock levels)
- **Average landed cost** (shipping costs)

By default I'll show the last 12 months for shipments and orders, or the latest snapshot for inventory. Would you like a different period (e.g., a specific quarter or year)?
````

### Q27 · AMBIGUOUS · PASS · 9.8 s

**Question**: Show me the numbers for last period.

**Answer**:

````text
Which metrics would you like to see? I can show you on-time delivery, fill rate, days of inventory, average landed cost, or revenue. And which period — the last 12 months, a specific quarter, or a specific year?
````

### Q28 · MULTILINGUAL · PASS · 26.7 s

**Question**: हमारी कुल समय पर डिलीवरी दर क्या है?

**Answer**:

````text
हमारी कुल समय पर डिलीवरी दर **87.5%** है (पिछले 12 महीनों में शिप किए गए शिपमेंट के आधार पर)।
````

**Agent SQL** (`AGENT_SQL`):

````sql
SELECT * FROM SEMANTIC_VIEW(supply_chain_forge.semantic.supply_chain_sv METRICS shipments.on_time_delivery_rate WHERE shipments.ship_date > DATEADD(MONTH, -12, CURRENT_DATE) AND shipments.ship_date <= CURRENT_DATE)

SELECT * FROM SEMANTIC_VIEW(supply_chain_forge.semantic.supply_chain_sv METRICS shipments.on_time_delivery_rate WHERE shipments.ship_date > DATEADD(MONTH, -12, CURRENT_DATE) AND shipments.ship_date <= CURRENT_DATE)
-- Generated by Cortex
;
````

### Q29 · DATA_HEALTH · PASS · 14.9 s

**Question**: Is the shipment data up to date?

**Answer**:

````text
Yes, the shipment data is up to date as of September 29, 2026 and was last refreshed about 14 hours ago on September 30, 2026 at 4:59 AM. All quality checks are passing with OK status.
````

### Q30 · CROSS_GRAIN · PASS · 17.2 s

**Question**: What is on-time delivery rate by part category?

**Answer**:

````text
On-time delivery by part category is not supported because an order may have several lines (different parts) and several shipments, so the breakdown counts the same shipments more than once. Instead, I can show on-time delivery by plant, region, carrier, order priority, or customer—would any of those help?
````
