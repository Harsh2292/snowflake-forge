-- ============================================================
-- 01_semantic_view.sql — Semantic Layer: SUPPLY_CHAIN_SV
-- Task: B08 (B09 adds AI_SQL_GENERATION, AI_QUESTION_CATEGORIZATION
--       and AI_VERIFIED_QUERIES to this same statement)
-- Owner: CoCo
-- Object: SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
-- Run as: FORGE_ADMIN (the app owner; CREATE SEMANTIC VIEW on SEMANTIC,
--         SELECT on every governed view)
-- ============================================================
-- One formula per canonical metric (contract §3), one name per dimension
-- (contract §4). Logical tables sit on the GOVERNED views only, so masking
-- still applies underneath, and no metric reads a masked column (§6).
--
-- Relationships are all many-to-one, fact -> master. That is what makes the
-- §4 valid pairings work and the invalid ones fail: inventory has no path
-- to orders or shipments, so days_of_inventory x orders.*/shipments.* is
-- rejected by Snowflake itself.
--
-- CR-005: fill_rate counts only lines on SHIPPED or DELIVERED orders. The
-- filter lives in two PRIVATE facts on order_lines that read
-- orders.order_status through lines_to_order.
--
-- GAP-2: order_year / order_quarter / order_month / order_week are
-- dimension expressions here; V_ORDER deliberately does not carry them.
--
-- Built incrementally at B08: (a) shipments + orders, OTD = 0.873973;
-- (b) + order_lines, fill rate = 0.926485; (c) + plants, parts, inventory,
-- DOI = 28.499215; (d) + customers, suppliers, sourcing, landed cost.
-- ============================================================

USE ROLE FORGE_ADMIN;
USE WAREHOUSE FORGE_WH;
USE DATABASE SUPPLY_CHAIN_FORGE;
USE SCHEMA SEMANTIC;

CREATE OR REPLACE SEMANTIC VIEW SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV

  TABLES (
    suppliers   AS SUPPLY_CHAIN_FORGE.GOVERNED.V_SUPPLIER   PRIMARY KEY (supplier_id)
                WITH SYNONYMS ('vendor', 'source', 'supplier')
                COMMENT = 'Suppliers, conformed from SRM LFA1',
    parts       AS SUPPLY_CHAIN_FORGE.GOVERNED.V_PART       PRIMARY KEY (part_id)
                WITH SYNONYMS ('material', 'SKU', 'component', 'item', 'product')
                COMMENT = 'Parts / materials, conformed from SRM MARA',
    sourcing    AS SUPPLY_CHAIN_FORGE.GOVERNED.V_SOURCING   PRIMARY KEY (source_id)
                WITH SYNONYMS ('sourcing contract', 'supplier part')
                COMMENT = 'Supplier-to-part sourcing contracts, conformed from SRM SOURCING',
    plants      AS SUPPLY_CHAIN_FORGE.GOVERNED.V_PLANT      PRIMARY KEY (plant_id)
                WITH SYNONYMS ('facility', 'site', 'warehouse', 'DC')
                COMMENT = 'Plants, distribution centres and hubs, conformed from WMS T001W',
    inventory   AS SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY  PRIMARY KEY (inventory_key)
                WITH SYNONYMS ('stock', 'inventory snapshot')
                COMMENT = 'Daily inventory snapshots per plant and part, conformed from WMS MARD',
    customers   AS SUPPLY_CHAIN_FORGE.GOVERNED.V_CUSTOMER   PRIMARY KEY (customer_id)
                WITH SYNONYMS ('client', 'account', 'buyer')
                COMMENT = 'Customers, conformed from ERP KNA1',
    orders      AS SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER      PRIMARY KEY (order_id)
                WITH SYNONYMS ('sales order', 'order header')
                COMMENT = 'Sales order headers, conformed from ERP VBAK. ERP promised date excluded.',
    order_lines AS SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER_LINE PRIMARY KEY (line_id)
                WITH SYNONYMS ('order line', 'line item')
                COMMENT = 'Sales order lines, conformed from ERP VBAP',
    shipments   AS SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT   PRIMARY KEY (shipment_id)
                WITH SYNONYMS ('delivery', 'shipment', 'freight')
                COMMENT = 'Shipments, conformed from TMS VTTK. promised_delivery_date is the authoritative SLA date.'
  )

  RELATIONSHIPS (
    sourcing_to_supplier AS sourcing    (supplier_id) REFERENCES suppliers,
    sourcing_to_part     AS sourcing    (part_id)     REFERENCES parts,
    inventory_to_plant   AS inventory   (plant_id)    REFERENCES plants,
    inventory_to_part    AS inventory   (part_id)     REFERENCES parts,
    orders_to_customer   AS orders      (customer_id) REFERENCES customers,
    lines_to_order       AS order_lines (order_id)    REFERENCES orders,
    lines_to_part        AS order_lines (part_id)     REFERENCES parts,
    lines_to_plant       AS order_lines (plant_id)    REFERENCES plants,
    shipments_to_order   AS shipments   (order_id)    REFERENCES orders,
    shipments_to_plant   AS shipments   (plant_id)    REFERENCES plants
  )

  FACTS (
    shipments.is_on_time AS IFF(actual_delivery_date <= promised_delivery_date, 1, 0)
      COMMENT = '1 when delivered on or before the TMS promised date, else 0 (NULL-safe: in-transit is 0)',
    shipments.total_landed_cost AS freight_cost + duty_cost + handling_cost
      WITH SYNONYMS ('landed cost per shipment')
      COMMENT = 'Freight plus duty plus handling for one shipment, USD',
    order_lines.line_revenue AS quantity_ordered * unit_price
      COMMENT = 'Quantity ordered times net selling price, USD',
    inventory.available_qty AS quantity_on_hand - quantity_reserved
      COMMENT = 'On-hand quantity net of reservations (not used by days_of_inventory)',
    -- CR-005: only lines on SHIPPED / DELIVERED orders count towards fill rate.
    PRIVATE order_lines.fulfilled_qty_shipped AS
      IFF(orders.order_status IN ('SHIPPED', 'DELIVERED'), quantity_shipped, 0)
      COMMENT = 'Quantity shipped on shipped or delivered orders only (CR-005)',
    PRIVATE order_lines.fulfilled_qty_ordered AS
      IFF(orders.order_status IN ('SHIPPED', 'DELIVERED'), quantity_ordered, 0)
      COMMENT = 'Quantity ordered on shipped or delivered orders only (CR-005)'
  )

  DIMENSIONS (
    -- suppliers
    suppliers.supplier_name   AS supplier_name
      WITH SYNONYMS ('vendor name') COMMENT = 'Supplier name',
    suppliers.supplier_region AS region
      WITH SYNONYMS ('vendor region') COMMENT = 'Supplier region: APAC / EMEA / AMER',
    suppliers.supplier_tier   AS supplier_tier
      WITH SYNONYMS ('tier', 'vendor tier') COMMENT = 'Supplier tier: 1 / 2 / 3',
    -- parts
    parts.part_name           AS part_name
      WITH SYNONYMS ('material name', 'SKU name') COMMENT = 'Part description',
    parts.category            AS category
      WITH SYNONYMS ('product category', 'material category')
      COMMENT = 'Part category: ELECTRONICS / MECHANICAL / RAW_MATERIAL / PACKAGING / CHEMICAL / FASTENERS',
    parts.subcategory         AS subcategory
      WITH SYNONYMS ('product subcategory') COMMENT = 'Part subcategory',
    parts.is_critical         AS is_critical
      WITH SYNONYMS ('critical part', 'critical component') COMMENT = 'TRUE for critical components',
    -- plants
    plants.plant_name         AS plant_name
      WITH SYNONYMS ('facility name', 'site name', 'warehouse name') COMMENT = 'Plant / facility name',
    plants.plant_region       AS region
      WITH SYNONYMS ('region', 'site region') COMMENT = 'Plant region: APAC / EMEA / AMER',
    plants.plant_country      AS country
      WITH SYNONYMS ('country', 'site country') COMMENT = 'Plant country, ISO 3-char code',
    plants.plant_type         AS plant_type
      WITH SYNONYMS ('facility type', 'site type') COMMENT = 'Facility type: MFG / DC / HUB',
    -- customers
    customers.customer_segment AS customer_segment
      WITH SYNONYMS ('segment') COMMENT = 'Customer segment: ENTERPRISE / MIDMARKET / SMB',
    customers.customer_region  AS region
      WITH SYNONYMS ('customer geography') COMMENT = 'Customer region: APAC / EMEA / AMER',
    -- orders (GAP-2 time dimensions)
    orders.order_date         AS order_date
      WITH SYNONYMS ('order day') COMMENT = 'Order document date',
    orders.order_week         AS DATE_TRUNC('WEEK', order_date)
      COMMENT = 'Week of the order (Monday start)',
    orders.order_month        AS TO_CHAR(order_date, 'YYYY-MM')
      WITH SYNONYMS ('month') COMMENT = 'Order month as YYYY-MM',
    orders.order_quarter      AS 'Q' || QUARTER(order_date)
      WITH SYNONYMS ('quarter') COMMENT = 'Order quarter: Q1 / Q2 / Q3 / Q4',
    orders.order_year         AS YEAR(order_date)
      WITH SYNONYMS ('year') COMMENT = 'Order year',
    orders.order_status       AS order_status
      COMMENT = 'Order status: OPEN / SHIPPED / DELIVERED / CANCELLED',
    orders.order_priority     AS order_priority
      WITH SYNONYMS ('priority') COMMENT = 'Order priority: HIGH / NORMAL / LOW',
    -- shipments
    shipments.ship_date       AS ship_date
      WITH SYNONYMS ('departure date') COMMENT = 'Actual departure date',
    shipments.carrier         AS carrier
      WITH SYNONYMS ('freight carrier', 'transporter') COMMENT = 'Freight carrier',
    shipments.shipment_status AS shipment_status
      COMMENT = 'Shipment status: IN_TRANSIT / DELIVERED / DELAYED',
    -- inventory
    inventory.snapshot_date   AS snapshot_date
      WITH SYNONYMS ('inventory date') COMMENT = 'Inventory snapshot date'
  )

  METRICS (
    -- 1. ON-TIME DELIVERY (TMS promised date is the only authoritative one)
    shipments.on_time_delivery_rate AS
      COUNT_IF(actual_delivery_date <= promised_delivery_date)
        / NULLIFZERO(COUNT_IF(actual_delivery_date IS NOT NULL))
      WITH SYNONYMS ('OTD', 'on time delivery', 'delivery performance', 'on-time %')
      COMMENT = 'Share of delivered shipments arriving on or before the TMS promised delivery date. Excludes in-transit shipments.',

    -- 2. FILL RATE (CR-005)
    order_lines.fill_rate AS
      SUM(fulfilled_qty_shipped) / NULLIFZERO(SUM(fulfilled_qty_ordered))
      WITH SYNONYMS ('fill rate', 'order fulfillment rate', 'service level')
      COMMENT = 'Quantity shipped divided by quantity ordered across order lines on shipped or delivered orders. Open and cancelled orders are excluded. Partial shipments are pro-rated.',

    -- 3. DAYS OF INVENTORY
    inventory.days_of_inventory AS
      AVG(quantity_on_hand) / NULLIFZERO(AVG(daily_usage))
      WITH SYNONYMS ('DOI', 'days of inventory', 'inventory days', 'days of supply')
      COMMENT = 'Average on-hand quantity divided by average daily usage. Uses gross on-hand, not net of reservations.',

    -- 4. LANDED COST
    shipments.avg_landed_cost AS
      AVG(total_landed_cost)
      WITH SYNONYMS ('landed cost', 'total delivered cost', 'all-in cost')
      COMMENT = 'Average total cost to move a shipment to destination: freight plus duties plus handling.'
  )

  COMMENT = 'Governed supply chain ontology unifying ERP, WMS, TMS and SRM sources. Canonical metrics per docs/CONTRACT.md §3.'

  COPY GRANTS;

-- Persona roles query the semantic view directly (and SP_METRICS_AS_* run as
-- them). COPY GRANTS keeps these across re-runs; re-granting is harmless.
GRANT SELECT ON SEMANTIC VIEW SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV TO ROLE PLANNER_ROLE;
GRANT SELECT ON SEMANTIC VIEW SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV TO ROLE BUYER_ROLE;
GRANT SELECT ON SEMANTIC VIEW SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV TO ROLE LOGISTICS_ROLE;
