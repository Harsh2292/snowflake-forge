-- ============================================================================
-- agent/01_agent.sql — the Cortex Agent (B10; B09a speed pass)
-- Card:       B10 (.agents/tasks/coco/B10_agent.md), B09a (.agents/tasks/coco/B09a_verified_queries_speed.md)
-- Contract:   v1.6 §1 (FQN), §3 (metrics), §3a (time rule), §4 (pairings), §5.3, §9
-- Role:       FORGE_ADMIN (owner)        Warehouse: FORGE_WH
-- Depends on: SEMANTIC.SUPPLY_CHAIN_SV (B09), SEMANTIC.SP_DATA_HEALTH (C10, quality/30)
-- Re-runnable: CREATE OR REPLACE, then the same grants (COPY GRANTS is rejected here).
-- Account-agnostic: no account, user or region is named.
--
-- Tools
--   supply_chain_analyst  Cortex Analyst on the governed semantic view (every number)
--   data_health           SEMANTIC.SP_DATA_HEALTH: as-of date, freshness, data-quality checks
-- B09a removed data_to_chart and the "show the SQL" response rule: the app draws its own
-- charts and shows the tool's SQL itself (C6c), so both only cost the agent time.
--
-- Calling it (contract §5.3 as amended by CR-007): bind the whole request as JSON text.
--   SELECT TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
--     'SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT', ?, TRUE));
--   ? = '{"messages":[{"role":"user","content":[{"type":"text","text":"<question>"}]}]}'
-- The request must be a constant: OBJECT_CONSTRUCT(...)::VARCHAR is rejected at compile time.
-- Observed at B10: the agent's tools ran as the CALLING role (FORGE_ADMIN), on the warehouse
-- named below, not as the user's default role (art 01 predicted the default role).
-- ============================================================================

CREATE OR REPLACE AGENT SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT
  COMMENT = 'B10: governed supply chain analytics agent (Analyst on SUPPLY_CHAIN_SV, chart, data health)'
  PROFILE = '{"display_name": "Supply Chain Forge", "color": "blue"}'
  FROM SPECIFICATION
$$
models:
  orchestration: claude-sonnet-4-5

orchestration:
  budget:
    seconds: 120
    tokens: 32000

instructions:
  orchestration: |
    You answer questions about one company's supply chain: deliveries and on-time performance,
    carriers and landed cost, sales orders, fill rate and revenue, inventory and reorder points,
    parts, plants, customers and suppliers. Every number comes from the governed semantic view.

    Which tool, when:
    1. supply_chain_analyst: every question that needs data (metrics, counts, lists, lookups of
       one order or shipment, names). Never compute or estimate a number yourself.
    2. data_health: when the user asks whether data is fresh, up to date, complete, trustworthy
       or passing its quality checks, or asks for the as-of date. Pass the entity the question is
       about (suppliers, parts, sourcing, plants, inventory, customers, orders, order_lines,
       shipments) or ALL when none is named.
    Never create a chart or visualization, and never use a charting tool or skill, even when
    asked for one: answer with the data as text and a short table. The app draws its own charts.

    Do not call any tool, and answer in one or two sentences, when:
    - The question is outside the supply chain data (weather, news, general knowledge, HR,
      finance ledgers, coding help). Say you can only answer questions about this supply chain
      data.
    - The question asks for personal or restricted data: customer e-mail addresses, credit
      limits, payment terms, supplier contract prices, part unit costs. Say this data is
      restricted and offer a governed measure instead (for example landed cost or fill rate).
    - The question is ambiguous about the measure or the period (for example "How are we doing?"
      or "Show me the numbers for last period"). Ask one short clarifying question that offers
      the choices: on-time delivery, fill rate, days of inventory, average landed cost, and the
      period (the last 12 months by default, or a named quarter or year).
    - The question asks for a breakdown the data model cannot answer correctly:
      * on-time delivery, landed cost, shipment counts, days late or transit time by a part or
        supplier attribute (part category, part name, supplier name, supplier region, tier)
      * fill rate, revenue or units by a shipment attribute (carrier, shipment status, ship date)
      * days of inventory by an order, shipment or customer attribute
      An order has several lines and may have several shipments, so these breakdowns count the
      same rows more than once. Say the breakdown is not supported and why in one sentence, and
      offer the nearest valid one: on-time delivery and landed cost by plant, region, order
      attribute, shipment attribute (carrier, status) or customer; fill rate by part category,
      plant, order attribute or customer; days of inventory by plant, part or snapshot date.

    Numbered or multi-part questions: answer every part, in the order asked, with one
    supply_chain_analyst call per part.

    Time rule (the same as the app): with no period named, on-time delivery and landed cost cover
    shipments shipped in the last 12 months, fill rate and revenue cover orders placed in the last
    12 months, and days of inventory uses the latest inventory snapshot. A named period replaces
    the default.

  response: |
    Lead with the answer in one sentence, then the supporting rows as a short table when there
    are several. Keep answers brief.
    Formats: on-time delivery and fill rate as percentages with one decimal; days of inventory
    with one decimal; landed cost and other money in USD with two decimals; counts as whole
    numbers.
    Always state the period the numbers cover (for example "last 12 months, by ship date" or
    "latest inventory snapshot").
    For rankings and long lists, show at most the top 10 rows and say how many there are in all.
    Answer in the language of the question.
    Never include an e-mail address, a credit limit, payment terms, a contract price or a unit
    cost in an answer.
  sample_questions:
    - question: "What is our overall on-time delivery rate?"
    - question: "What is on-time delivery rate by region?"
    - question: "What was on-time delivery rate by quarter?"
    - question: "What is our fill rate?"
    - question: "What is fill rate by product category?"
    - question: "What are days of inventory by plant?"
    - question: "What is average landed cost by region?"
    - question: "Which plants have the worst on-time delivery?"

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "supply_chain_analyst"
      description: "Answers supply chain data questions with SQL on the governed semantic view SUPPLY_CHAIN_SV: on-time delivery, fill rate, days of inventory, landed cost, revenue, counts, carriers, orders, shipments, inventory and reorder points, parts, plants, customers, suppliers, and lookups of a single order or shipment by ID or name."
  - tool_spec:
      type: "generic"
      name: "data_health"
      description: "Returns the as-of date, freshness and data-quality check results (duplicates, missing promised dates, orphan rows, non-contract codes) for one entity or ALL, as counts and rates only. Use when the user asks whether data is up to date, complete or trustworthy."
      input_schema:
        type: "object"
        properties:
          entity:
            type: "string"
            description: "One of: suppliers, parts, sourcing, plants, inventory, customers, orders, order_lines, shipments, or ALL."
        required:
          - entity

tool_resources:
  supply_chain_analyst:
    semantic_view: "SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV"
    execution_environment:
      type: "warehouse"
      warehouse: "FORGE_WH"
      query_timeout: 60
  data_health:
    type: "procedure"
    identifier: "SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH"
    execution_environment:
      type: "warehouse"
      warehouse: "FORGE_WH"
      query_timeout: 30
$$;

-- Callers: the owner (FORGE_ADMIN) plus the three personas. SP_DATA_HEALTH's USAGE grants are in
-- quality/30_sp_data_health.sql; the semantic view's SELECT grants are in semantic/.
GRANT USAGE ON AGENT SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT TO ROLE PLANNER_ROLE;
GRANT USAGE ON AGENT SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT TO ROLE BUYER_ROLE;
GRANT USAGE ON AGENT SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT TO ROLE LOGISTICS_ROLE;
