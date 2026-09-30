-- ============================================================
-- 01_semantic_view.sql — Semantic Layer: SUPPLY_CHAIN_SV (v2)
-- Task: B08 (v1), B09 (v2: every business column, extra metrics, named
--       filters, AI instructions, verified queries)
-- Owner: CoCo
-- Object: SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
-- Run as: FORGE_ADMIN (the app owner; CREATE SEMANTIC VIEW on SEMANTIC,
--         SELECT on every governed view)
-- ============================================================
-- One formula per canonical metric (contract §3), one name per dimension
-- (contract §4). Logical tables sit on the GOVERNED views only, so masking
-- still applies underneath, and no metric reads a masked column (§6).
-- Never exposed: unit_cost, contract_price, payment_terms, credit_limit and
-- both email columns. customer_name is a label only (masked for BUYER).
--
-- Relationships are all many-to-one, fact -> master. inventory has no path
-- to orders or shipments, so days_of_inventory x orders.*/shipments.* is
-- rejected by Snowflake itself. Found at B09: Snowflake now also runs the
-- one-to-many cross-grain pairings that v1 rejected (shipments x parts.*,
-- order_lines x shipments.*), and they multi-count. They are outside the
-- contract §4 pairings; AI_SQL_GENERATION rule 8 forbids them.
--
-- B09 supplier fan-out fix: primary_sourcing is V_SOURCING filtered to
-- is_primary (exactly one row per part, checked live 2026-09-29), so
-- parts -> primary_sourcing -> suppliers is many-to-one and "by supplier"
-- counts every part once, under its primary supplier.
--
-- CR-005: fill_rate counts only lines on SHIPPED or DELIVERED orders (two
-- PRIVATE facts read orders.order_status through lines_to_order).
-- CR-006 / E01: OTD excludes delivered shipments with no promised date from
-- the denominator as well as the numerator.
-- Revenue (agreed with Claude Code for C11): shipped quantity x unit price
-- on SHIPPED / DELIVERED orders, by order date.
-- §3a time rule: stated in AI_SQL_GENERATION and applied in every verified
-- query; the view itself holds no window, so explicit periods still work.
-- ============================================================

USE ROLE FORGE_ADMIN;
USE WAREHOUSE FORGE_WH;
USE DATABASE SUPPLY_CHAIN_FORGE;
USE SCHEMA SEMANTIC;

CREATE OR REPLACE SEMANTIC VIEW SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV

  TABLES (
    suppliers   AS SUPPLY_CHAIN_FORGE.GOVERNED.V_SUPPLIER   PRIMARY KEY (supplier_id)
                WITH SYNONYMS ('vendor')
                COMMENT = 'Suppliers (SRM vendor master): who we buy parts from, with lead time and reliability',
    parts       AS SUPPLY_CHAIN_FORGE.GOVERNED.V_PART       PRIMARY KEY (part_id)
                WITH SYNONYMS ('material', 'SKU', 'item')
                COMMENT = 'Parts and materials we buy, stock and sell (SRM material master)',
    primary_sourcing AS (
                  SELECT source_id, supplier_id, part_id
                  FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SOURCING
                  WHERE is_primary
                ) PRIMARY KEY (part_id)
                COMMENT = 'The one primary supplier of each part. Supplier breakdowns of part-based metrics go through this table',
    sourcing    AS SUPPLY_CHAIN_FORGE.GOVERNED.V_SOURCING   PRIMARY KEY (source_id)
                WITH SYNONYMS ('sourcing contract', 'approved vendor list')
                COMMENT = 'All supplier-part sourcing contracts valid today, primary and secondary',
    plants      AS SUPPLY_CHAIN_FORGE.GOVERNED.V_PLANT      PRIMARY KEY (plant_id)
                WITH SYNONYMS ('facility', 'site', 'DC')
                COMMENT = 'Plants, distribution centres and hubs that stock and ship parts (WMS)',
    inventory   AS SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY  PRIMARY KEY (inventory_key)
                WITH SYNONYMS ('stock')
                COMMENT = 'Daily stock snapshot per plant and part (WMS). Use the latest snapshot for current stock',
    customers   AS SUPPLY_CHAIN_FORGE.GOVERNED.V_CUSTOMER   PRIMARY KEY (customer_id)
                WITH SYNONYMS ('client', 'account')
                COMMENT = 'Customers who place sales orders (ERP customer master)',
    orders      AS SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER      PRIMARY KEY (order_id)
                WITH SYNONYMS ('sales order')
                COMMENT = 'Sales order headers (ERP). The ERP promised date is deliberately not available',
    order_lines AS SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER_LINE PRIMARY KEY (line_id)
                WITH SYNONYMS ('order line', 'line item')
                COMMENT = 'Sales order lines: part, shipping plant, quantities and net price in USD',
    shipments   AS SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT   PRIMARY KEY (shipment_id)
                WITH SYNONYMS ('delivery', 'consignment')
                COMMENT = 'Outbound shipments (TMS). promised_delivery_date is the authoritative SLA date; costs in USD'
  )

  RELATIONSHIPS (
    sourcing_to_supplier  AS sourcing         (supplier_id) REFERENCES suppliers,
    sourcing_to_part      AS sourcing         (part_id)     REFERENCES parts,
    part_to_primary       AS parts            (part_id)     REFERENCES primary_sourcing,
    primary_to_supplier   AS primary_sourcing (supplier_id) REFERENCES suppliers,
    inventory_to_plant    AS inventory        (plant_id)    REFERENCES plants,
    inventory_to_part     AS inventory        (part_id)     REFERENCES parts,
    orders_to_customer    AS orders           (customer_id) REFERENCES customers,
    lines_to_order        AS order_lines      (order_id)    REFERENCES orders,
    lines_to_part         AS order_lines      (part_id)     REFERENCES parts,
    lines_to_plant        AS order_lines      (plant_id)    REFERENCES plants,
    shipments_to_order    AS shipments        (order_id)    REFERENCES orders,
    shipments_to_plant    AS shipments        (plant_id)    REFERENCES plants
  )

  FACTS (
    -- suppliers / parts / plants
    suppliers.lead_time_days AS lead_time_days
      COMMENT = 'Quoted supplier lead time in days',
    suppliers.reliability_score AS reliability_score
      COMMENT = 'Supplier reliability score, 0 to 1 (higher is better)',
    parts.weight_kg AS weight_kg
      COMMENT = 'Unit weight in kilograms',
    plants.capacity_units AS capacity_units
      COMMENT = 'Plant storage or throughput capacity in units',
    -- inventory
    inventory.quantity_on_hand AS quantity_on_hand
      WITH SYNONYMS ('on hand', 'stock on hand')
      COMMENT = 'Gross units on hand in the snapshot (never negative)',
    inventory.quantity_reserved AS quantity_reserved
      COMMENT = 'Units reserved for open demand',
    inventory.reorder_point AS reorder_point
      COMMENT = 'Stock level at which the part should be reordered',
    inventory.daily_usage AS daily_usage
      COMMENT = 'Average units consumed per day',
    inventory.available_qty AS quantity_on_hand - quantity_reserved
      COMMENT = 'On-hand units net of reservations (not used by days_of_inventory)',
    inventory.is_below_reorder_point AS IFF(quantity_on_hand < reorder_point, 1, 0)
      COMMENT = '1 when on hand is below the reorder point, else 0',
    -- order lines
    order_lines.quantity_ordered AS quantity_ordered
      COMMENT = 'Units ordered on the line',
    order_lines.quantity_shipped AS quantity_shipped
      COMMENT = 'Units shipped on the line (over-shipments capped at the ordered quantity)',
    order_lines.unit_price AS unit_price
      WITH SYNONYMS ('selling price')
      COMMENT = 'Net selling price per unit, USD',
    order_lines.line_revenue AS
      IFF(orders.order_status IN ('SHIPPED', 'DELIVERED'), quantity_shipped * unit_price, 0)
      COMMENT = 'Revenue of the line, USD: shipped quantity times unit price, on shipped or delivered orders only',
    -- CR-005: only lines on SHIPPED / DELIVERED orders count towards fill rate.
    PRIVATE order_lines.fulfilled_qty_shipped AS
      IFF(orders.order_status IN ('SHIPPED', 'DELIVERED'), quantity_shipped, 0)
      COMMENT = 'Quantity shipped on shipped or delivered orders only (CR-005)',
    PRIVATE order_lines.fulfilled_qty_ordered AS
      IFF(orders.order_status IN ('SHIPPED', 'DELIVERED'), quantity_ordered, 0)
      COMMENT = 'Quantity ordered on shipped or delivered orders only (CR-005)',
    -- shipments
    shipments.freight_cost AS freight_cost
      COMMENT = 'Freight cost, USD (NULL when the cost is unknown or implausible)',
    shipments.duty_cost AS duty_cost
      COMMENT = 'Customs duty, USD (0 for domestic shipments)',
    shipments.handling_cost AS handling_cost
      COMMENT = 'Handling cost, USD',
    shipments.total_landed_cost AS freight_cost + duty_cost + handling_cost
      WITH SYNONYMS ('landed cost per shipment')
      COMMENT = 'Freight plus duty plus handling for one shipment, USD',
    shipments.is_on_time AS IFF(actual_delivery_date <= promised_delivery_date, 1, 0)
      COMMENT = '1 when delivered on or before the TMS promised date, else 0 (in transit is 0)',
    shipments.days_late AS
      GREATEST(DATEDIFF('day', promised_delivery_date, actual_delivery_date), 0)
      COMMENT = 'Days delivered after the TMS promised date, 0 when on time; NULL when not delivered or no promised date',
    shipments.transit_days AS DATEDIFF('day', ship_date, actual_delivery_date)
      COMMENT = 'Days from departure to delivery; NULL while in transit'
  )

  DIMENSIONS (
    -- suppliers
    suppliers.supplier_id     AS supplier_id     COMMENT = 'Supplier ID, e.g. SUP00107',
    suppliers.supplier_name   AS supplier_name   WITH SYNONYMS ('vendor name') COMMENT = 'Supplier name',
    suppliers.supplier_country AS country        COMMENT = 'Supplier country, ISO 3-letter code',
    suppliers.supplier_region AS region          COMMENT = 'Supplier region: APAC / EMEA / AMER',
    suppliers.supplier_tier   AS supplier_tier   COMMENT = 'Supplier tier: 1 / 2 / 3',
    -- parts
    parts.part_id             AS part_id         WITH SYNONYMS ('material number') COMMENT = 'Part ID, e.g. MAT000001',
    parts.part_name           AS part_name       COMMENT = 'Part description',
    parts.category            AS category        WITH SYNONYMS ('product category')
      COMMENT = 'Part category: ELECTRONICS / MECHANICAL / RAW_MATERIAL / PACKAGING / CHEMICAL / FASTENERS',
    parts.subcategory         AS subcategory     COMMENT = 'Part subcategory',
    parts.is_critical         AS is_critical     COMMENT = 'TRUE for critical components',
    parts.critical_parts LABELS = (FILTER) AS is_critical = TRUE
      COMMENT = 'Filter: critical parts only',
    -- sourcing
    sourcing.source_id        AS source_id       COMMENT = 'Sourcing contract ID',
    sourcing.is_primary       AS is_primary      COMMENT = 'TRUE for the primary supplier of the part',
    -- plants
    plants.plant_id           AS plant_id        COMMENT = 'Plant ID',
    plants.plant_name         AS plant_name      WITH SYNONYMS ('site name') COMMENT = 'Plant / facility name',
    plants.plant_region       AS region          COMMENT = 'Plant region: APAC / EMEA / AMER',
    plants.plant_country      AS country         COMMENT = 'Plant country, ISO 3-letter code',
    plants.plant_type         AS plant_type      COMMENT = 'Facility type: MFG / DC / HUB',
    -- customers
    customers.customer_id     AS customer_id     COMMENT = 'Customer ID. Group and rank customers by this ID',
    customers.customer_name   AS customer_name
      COMMENT = 'Customer name, a display label only (masked for some roles): never group or filter by it',
    customers.customer_country AS country        COMMENT = 'Customer country, ISO 3-letter code',
    customers.customer_segment AS customer_segment WITH SYNONYMS ('segment')
      COMMENT = 'Customer segment: ENTERPRISE / MIDMARKET / SMB',
    customers.customer_region AS region          COMMENT = 'Customer region: APAC / EMEA / AMER',
    -- orders
    orders.order_id           AS order_id        WITH SYNONYMS ('order number') COMMENT = 'Sales order ID, e.g. ORD000000001',
    orders.order_date         AS order_date      COMMENT = 'Order date. The default window for fill rate and revenue',
    orders.order_week         AS DATE_TRUNC('WEEK', order_date) COMMENT = 'Week of the order (Monday start)',
    orders.order_month        AS TO_CHAR(order_date, 'YYYY-MM') COMMENT = 'Order month as YYYY-MM',
    orders.order_quarter      AS 'Q' || QUARTER(order_date)     COMMENT = 'Order quarter of the year: Q1 / Q2 / Q3 / Q4 (no year)',
    orders.order_year         AS YEAR(order_date)               COMMENT = 'Order year',
    orders.order_year_quarter AS YEAR(order_date) || '-Q' || QUARTER(order_date)
      WITH SYNONYMS ('quarter')
      COMMENT = 'Order year and quarter, e.g. 2026-Q3. Use this for quarter-by-quarter trends',
    orders.order_status       AS order_status
      COMMENT = 'Order status: OPEN / SHIPPED / DELIVERED / CANCELLED',
    orders.order_priority     AS order_priority  COMMENT = 'Order priority: HIGH / NORMAL / LOW',
    orders.open_orders LABELS = (FILTER) AS order_status = 'OPEN'
      COMMENT = 'Filter: open orders only',
    -- shipments
    shipments.shipment_id     AS shipment_id     COMMENT = 'Shipment ID',
    shipments.ship_date       AS ship_date       WITH SYNONYMS ('departure date')
      COMMENT = 'Departure date. The default window for OTD and landed cost',
    shipments.ship_month      AS TO_CHAR(ship_date, 'YYYY-MM') COMMENT = 'Ship month as YYYY-MM',
    shipments.ship_year_quarter AS YEAR(ship_date) || '-Q' || QUARTER(ship_date)
      COMMENT = 'Ship year and quarter, e.g. 2026-Q3',
    shipments.ship_year       AS YEAR(ship_date)  COMMENT = 'Ship year',
    shipments.promised_delivery_date AS promised_delivery_date
      WITH SYNONYMS ('SLA date', 'committed date')
      COMMENT = 'TMS promised delivery date, the only authoritative promised date',
    shipments.actual_delivery_date AS actual_delivery_date
      COMMENT = 'Actual delivery date; NULL while in transit',
    shipments.delivery_month  AS TO_CHAR(actual_delivery_date, 'YYYY-MM')
      COMMENT = 'Delivery month as YYYY-MM',
    shipments.carrier         AS carrier         WITH SYNONYMS ('transporter') COMMENT = 'Freight carrier',
    shipments.shipment_status AS shipment_status COMMENT = 'Shipment status: IN_TRANSIT / DELIVERED / DELAYED',
    shipments.late_shipments LABELS = (FILTER) AS actual_delivery_date > promised_delivery_date
      COMMENT = 'Filter: shipments delivered after the promised date',
    shipments.delivered_shipments LABELS = (FILTER) AS actual_delivery_date IS NOT NULL
      COMMENT = 'Filter: delivered shipments only',
    -- inventory
    inventory.snapshot_date   AS snapshot_date   COMMENT = 'Inventory snapshot date. Default: the latest snapshot',
    inventory.snapshot_month  AS TO_CHAR(snapshot_date, 'YYYY-MM') COMMENT = 'Snapshot month as YYYY-MM',
    inventory.below_reorder_point LABELS = (FILTER) AS quantity_on_hand < reorder_point
      COMMENT = 'Filter: stock positions below their reorder point'
  )

  METRICS (
    -- 1. ON-TIME DELIVERY (TMS promised date is the only authoritative one; E01)
    shipments.on_time_delivery_rate AS
      COUNT_IF(actual_delivery_date <= promised_delivery_date)
        / NULLIFZERO(COUNT_IF(actual_delivery_date IS NOT NULL AND promised_delivery_date IS NOT NULL))
      WITH SYNONYMS ('OTD', 'on time delivery', 'delivery performance')
      COMMENT = 'Share of delivered shipments arriving on or before the TMS promised delivery date. Excludes in-transit shipments and shipments with no promised date. Without a stated period, covers shipments shipped in the last 12 months.',

    -- 2. FILL RATE (CR-005)
    order_lines.fill_rate AS
      SUM(fulfilled_qty_shipped) / NULLIFZERO(SUM(fulfilled_qty_ordered))
      WITH SYNONYMS ('fill rate', 'order fulfillment rate', 'service level')
      COMMENT = 'Quantity shipped divided by quantity ordered across order lines on shipped or delivered orders. Open and cancelled orders are excluded. Partial shipments are pro-rated; over-shipments count as fully shipped. Without a stated period, covers orders placed in the last 12 months.',

    -- 3. DAYS OF INVENTORY
    inventory.days_of_inventory AS
      AVG(quantity_on_hand) / NULLIFZERO(AVG(daily_usage))
      WITH SYNONYMS ('DOI', 'days of supply', 'inventory days')
      COMMENT = 'Average on-hand quantity divided by average daily usage. Uses gross on-hand, not net of reservations; negative on-hand counts as zero. Without a stated period, uses the latest inventory snapshot.',

    -- 4. LANDED COST
    shipments.avg_landed_cost AS
      AVG(total_landed_cost)
      WITH SYNONYMS ('landed cost', 'all-in cost')
      COMMENT = 'Average total cost to move a shipment to destination, in USD: freight plus duties plus handling. Missing duty or handling counts as zero; shipments with unknown or implausible cost are excluded. Without a stated period, covers shipments shipped in the last 12 months.',

    -- Common metrics (B09). Default windows as for the canonical metric of the same table.
    shipments.shipment_count AS COUNT(shipment_id)
      COMMENT = 'Number of shipments',
    shipments.late_shipment_count AS COUNT_IF(actual_delivery_date > promised_delivery_date)
      WITH SYNONYMS ('late deliveries')
      COMMENT = 'Number of shipments delivered after the TMS promised date',
    shipments.delayed_shipment_count AS COUNT_IF(shipment_status = 'DELAYED')
      COMMENT = 'Number of shipments currently flagged DELAYED by the carrier',
    shipments.total_landed_cost_usd AS SUM(total_landed_cost)
      WITH SYNONYMS ('total logistics cost', 'freight spend')
      COMMENT = 'Total landed cost (freight plus duty plus handling) of the shipments, USD',
    shipments.avg_days_late AS AVG(IFF(actual_delivery_date > promised_delivery_date, days_late, NULL))
      COMMENT = 'Average delay in days of the late shipments only',
    shipments.avg_transit_days AS AVG(transit_days)
      WITH SYNONYMS ('transit time')
      COMMENT = 'Average days from departure to delivery of delivered shipments',
    orders.order_count AS COUNT(order_id)
      COMMENT = 'Number of sales orders',
    customers.customer_count AS COUNT(customer_id)
      COMMENT = 'Number of customers',
    order_lines.total_revenue AS SUM(line_revenue)
      WITH SYNONYMS ('revenue', 'sales')
      COMMENT = 'Revenue in USD: shipped quantity times unit price on shipped or delivered orders, by order date. Without a stated period, covers orders placed in the last 12 months.',
    order_lines.units_ordered AS SUM(quantity_ordered)
      COMMENT = 'Total units ordered',
    order_lines.units_shipped AS SUM(quantity_shipped)
      COMMENT = 'Total units shipped',
    suppliers.supplier_count AS COUNT(supplier_id)
      COMMENT = 'Number of suppliers',
    suppliers.avg_lead_time_days AS AVG(lead_time_days)
      WITH SYNONYMS ('lead time')
      COMMENT = 'Average quoted supplier lead time in days',
    suppliers.avg_reliability_score AS AVG(reliability_score)
      COMMENT = 'Average supplier reliability score, 0 to 1',
    inventory.parts_below_reorder_point AS COUNT_IF(quantity_on_hand < reorder_point)
      WITH SYNONYMS ('stockout risk')
      COMMENT = 'Number of part and plant stock positions below their reorder point. Without a stated period, uses the latest inventory snapshot.'
  )

  COMMENT = 'Governed supply chain ontology unifying ERP, WMS, TMS and SRM data (cleansed in CONFORMED). Canonical metrics per docs/CONTRACT.md §3.'

  AI_SQL_GENERATION 'Rules for every query on this view.
1. Use the named metrics. On-time delivery, fill rate, days of inventory, landed cost and revenue must always come from on_time_delivery_rate, fill_rate, days_of_inventory, avg_landed_cost and total_revenue. Never recompute them from facts.
2. The only promised date is shipments.promised_delivery_date (TMS). There is no ERP promised date; never use order_date as a promised date.
3. Time rule. The anchor is CURRENT_DATE(). When the question names no period: for shipment metrics filter shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE(); for order_lines and orders metrics filter the same window on orders.order_date; for inventory metrics filter inventory.snapshot_date = (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY). A named period replaces the default. Metrics with different windows go in separate queries. Always state the period used.
4. For quarter trends use orders.order_year_quarter or shipments.ship_year_quarter, not order_quarter, and order the result by it.
5. Rankings (best, worst, top, bottom) return the top 10 unless a number is asked for; order by the metric and LIMIT. Lists of records are capped at 100 rows.
6. Amounts are USD. Rates are fractions between 0 and 1; show them as percentages with one decimal.
7. Group, rank and filter customers by customer_id; customer_name is a label only. Break part-based metrics down by supplier only through primary_sourcing (one supplier per part); never through sourcing.
8. Never break shipments metrics (on-time delivery, landed cost, shipment counts, days late, transit) down by parts or suppliers dimensions, and never break order_lines metrics (fill rate, revenue, units) down by shipments dimensions: an order has several lines and may have several shipments, so the result counts the same rows more than once. Inventory has no path to orders, shipments or customers. If asked for such a breakdown, say it is not supported and offer the nearest valid one (for example by plant).
9. For numbered multi-part questions, answer each part in order with its own query.'

  AI_QUESTION_CATEGORIZATION 'This view answers questions about supply chain operations: deliveries and on-time performance, carriers and landed cost, sales orders, fill rate and revenue, inventory and reorder points, parts, plants, customers and suppliers. Questions about anything else (HR, finance ledgers, weather, general knowledge) are out of scope: say so and do not guess. Questions that ask for masked data (unit cost, contract price, payment terms, credit limit, emails) cannot be answered here. When a question is ambiguous, for example "performance" or "cost" with no metric, ask which metric is meant.'

  AI_VERIFIED_QUERIES (
    vq_otd_overall AS (
      QUESTION 'What is our overall on-time delivery rate?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV METRICS shipments.on_time_delivery_rate WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE())'
    ),
    vq_otd_by_region AS (
      QUESTION 'What is on-time delivery rate by region?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS plants.plant_region METRICS shipments.on_time_delivery_rate WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE()) ORDER BY plant_region'
    ),
    vq_otd_by_quarter AS (
      QUESTION 'What was on-time delivery rate by quarter?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS orders.order_year_quarter METRICS shipments.on_time_delivery_rate WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE()) ORDER BY order_year_quarter'
    ),
    vq_fill_rate AS (
      QUESTION 'What is our fill rate?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV METRICS order_lines.fill_rate WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE()) AND orders.order_date <= CURRENT_DATE())'
    ),
    vq_fill_rate_by_category AS (
      QUESTION 'What is fill rate by product category?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS parts.category METRICS order_lines.fill_rate WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE()) AND orders.order_date <= CURRENT_DATE()) ORDER BY category'
    ),
    vq_doi_by_plant AS (
      QUESTION 'What are days of inventory by plant?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS plants.plant_name METRICS inventory.days_of_inventory WHERE inventory.snapshot_date = (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY)) ORDER BY plant_name'
    ),
    vq_landed_cost_by_region AS (
      QUESTION 'What is average landed cost by region?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS plants.plant_region METRICS shipments.avg_landed_cost WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE()) ORDER BY plant_region'
    ),
    vq_worst_plants_otd AS (
      QUESTION 'Which plants have the worst on-time delivery?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS plants.plant_name METRICS shipments.on_time_delivery_rate WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE()) ORDER BY on_time_delivery_rate ASC LIMIT 3'
    ),
    vq_revenue_by_quarter AS (
      QUESTION 'What was revenue by quarter over the last 12 months?'
      SQL 'SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS orders.order_year_quarter METRICS order_lines.total_revenue WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE()) AND orders.order_date <= CURRENT_DATE()) ORDER BY order_year_quarter'
    ),
    vq_below_reorder_by_plant AS (
      QUESTION 'For each plant, how many parts are below their reorder point right now?'
      SQL 'SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS plants.plant_name METRICS inventory.parts_below_reorder_point WHERE inventory.snapshot_date = (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY)) ORDER BY parts_below_reorder_point DESC'
    ),
    vq_landed_cost_by_carrier AS (
      QUESTION 'What is average landed cost by carrier?'
      SQL 'SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS shipments.carrier METRICS shipments.avg_landed_cost WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE()) AND shipments.ship_date <= CURRENT_DATE()) ORDER BY avg_landed_cost DESC'
    ),
    vq_worst_suppliers_fill_rate AS (
      QUESTION 'Which suppliers have the lowest fill rate on the parts they supply?'
      SQL 'SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS suppliers.supplier_id, suppliers.supplier_name METRICS order_lines.fill_rate WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE()) AND orders.order_date <= CURRENT_DATE()) ORDER BY fill_rate ASC LIMIT 10'
    ),
    -- B09a: pin the two questions where Analyst wrote its own CTE at B10 (C11 Q15, Q21).
    -- (A third, 'average landed cost per shipment', was tried and removed at B08m: Analyst
    -- matched "average freight cost per shipment" (Q18) to it and answered landed cost.)
    vq_reliability_by_supplier_region AS (
      QUESTION 'What is the average supplier reliability score by supplier region?'
      SQL 'SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV DIMENSIONS suppliers.supplier_region METRICS suppliers.avg_reliability_score) ORDER BY supplier_region'
    ),
    vq_revenue_last_12_months AS (
      QUESTION 'What was our revenue over the last 12 months?'
      SQL 'SELECT * FROM SEMANTIC_VIEW(SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV METRICS order_lines.total_revenue WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE()) AND orders.order_date <= CURRENT_DATE())'
    )
  )

  COPY GRANTS;

-- Persona roles query the semantic view directly (and SP_METRICS_AS_* run as
-- them). COPY GRANTS keeps these across re-runs; re-granting is harmless.
GRANT SELECT ON SEMANTIC VIEW SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV TO ROLE PLANNER_ROLE;
GRANT SELECT ON SEMANTIC VIEW SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV TO ROLE BUYER_ROLE;
GRANT SELECT ON SEMANTIC VIEW SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV TO ROLE LOGISTICS_ROLE;
