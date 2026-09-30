-- ============================================================================
-- eval/10_questions.sql — OPS.EVAL_QUESTIONS: the agent evaluation set (29 questions)
-- Card:       C11 (.agents/tasks/claude/C11_eval_set.md)
-- Spec:       docs/DATA_SPEC.md §7.3 (columns, coverage), docs/CONTRACT.md §3a, §4, §5, §9
-- Role:       FORGE_ADMIN        Warehouse: FORGE_WH
-- Run order:  2 of 5 (00 → 10 → 20 → 30 → 99), after 00 (ACCOUNTADMIN grants) and after
--             B08c/B09 (the lookup IDs are picked from the GOVERNED views).
--             Re-runnable: CREATE OR REPLACE, then the same rows.
-- Expected:   29 rows, all ACTIVE, Q09 and Q10 name a real order ID (no {{ORDER_ID}} left):
--             SELECT QUESTION_ID, INPUT_QUERY FROM SUPPLY_CHAIN_FORGE.OPS.EVAL_QUESTIONS
--             WHERE INPUT_QUERY LIKE '%{{%',   → 0 rows
--
-- Ground truth is a query, never a number, so it stays right when the data changes:
--   - canonical questions: exactly the SQL the app runs (forge_data.build_metric_sql), with
--     the §3a window (trailing 12 months, DOI on the latest snapshot)
--   - everything else: SEMANTIC_VIEW or the GOVERNED views, never a masked column
-- Tolerances (a value passes within either): rates ±0.001 absolute, amounts and averages
-- ±0.5% relative, counts exact.
-- COMPARE_MODE: SCALAR, SET, TOP_N, ORDERED (DATA_SPEC §7.3), plus MULTI (every number of a
-- numbered multi-part question) and TOOL (the expected tool was called), see the card.
-- Definitions B09 must agree with (else tell Claude Code, each is one row here): revenue =
-- shipped quantity × unit price on SHIPPED/DELIVERED orders by order date, below reorder
-- point = on hand < reorder point on the latest snapshot, Q03's quarter =
-- orders.order_year_quarter, Q08 = the bottom 3 plants by OTD.
-- ============================================================================

CREATE OR REPLACE TABLE SUPPLY_CHAIN_FORGE.OPS.EVAL_QUESTIONS (
    QUESTION_ID         VARCHAR   NOT NULL COMMENT 'Q01…; stable forever',
    CATEGORY            VARCHAR   NOT NULL COMMENT 'CANONICAL, LOOKUP, COUNT_TOTAL, SUPPLIER, INVENTORY, COST, CROSS_SYSTEM, REVENUE, MULTI_PART, OUT_OF_SCOPE, AMBIGUOUS, MULTILINGUAL, DATA_HEALTH, CROSS_GRAIN',
    INPUT_QUERY         VARCHAR   NOT NULL COMMENT 'The question, exactly as a user types it',
    EXPECTED_BEHAVIOUR  VARCHAR   NOT NULL COMMENT 'ANSWER, REFUSE or CLARIFY',
    GROUND_TRUTH_SQL    VARCHAR            COMMENT 'ANSWER only: SEMANTIC_VIEW or GOVERNED-view SELECT applying §3a when no period is named',
    COMPARE_MODE        VARCHAR            COMMENT 'SCALAR, SET, TOP_N, ORDERED, MULTI, TOOL',
    KEY_COLUMNS         ARRAY              COMMENT 'Key columns for SET / TOP_N / ORDERED, matched by value on UPPER(TRIM())',
    TOP_N               NUMBER             COMMENT 'For TOP_N',
    TOLERANCE_ABS       FLOAT,
    TOLERANCE_REL       FLOAT,
    EXPECTED_TOOLS      ARRAY              COMMENT 'Tool types or names, e.g. cortex_analyst_text_to_sql, data_health; [] for refusals',
    RUBRIC              VARCHAR            COMMENT 'Plain-language rubric for LLM judging; {{GT}} = the ground-truth result as text',
    CONTRACT_REF        VARCHAR,
    ACTIVE              BOOLEAN   NOT NULL
)
COMMENT = 'C11: agent evaluation set (DATA_SPEC §7.3). Read by OPS.SP_RUN_EVAL and OPS.SP_BUILD_EVAL_DATASET.';

INSERT INTO SUPPLY_CHAIN_FORGE.OPS.EVAL_QUESTIONS
SELECT column1, column2, column3, column4, column5, column6, PARSE_JSON(column7)::ARRAY, column8::NUMBER,
       column9::FLOAT, column10::FLOAT, PARSE_JSON(column11)::ARRAY, column12, column13, column14
FROM VALUES
    ('Q01', 'CANONICAL', 'What is our overall on-time delivery rate?', 'ANSWER', $$SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  METRICS shipments.on_time_delivery_rate
  WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
    AND shipments.ship_date <= CURRENT_DATE()
)$$, 'SCALAR', '[]', NULL, 0.001, 0.0, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives the on-time delivery rate as {{GT}} (as a share or a percentage, within 0.1 point) and states the period it covers (the last 12 months, since the question names none).', '§9 Q1', TRUE),
    ('Q02', 'CANONICAL', 'What is on-time delivery rate by region?', 'ANSWER', $$SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  DIMENSIONS plants.plant_region
  METRICS shipments.on_time_delivery_rate
  WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
    AND shipments.ship_date <= CURRENT_DATE()
) ORDER BY plant_region$$, 'SET', '["PLANT_REGION"]', NULL, 0.001, 0.0, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives the on-time delivery rate for each plant region (APAC, EMEA, AMER) as in {{GT}}, within 0.1 point, and states the period it covers (the last 12 months, since the question names none).', '§9 Q2', TRUE),
    ('Q03', 'CANONICAL', 'What was on-time delivery rate by quarter?', 'ANSWER', $$SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  DIMENSIONS orders.order_year_quarter
  METRICS shipments.on_time_delivery_rate
  WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
    AND shipments.ship_date <= CURRENT_DATE()
) ORDER BY order_year_quarter$$, 'SET', '["ORDER_YEAR_QUARTER"]', NULL, 0.001, 0.0, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives the on-time delivery rate for each quarter as in {{GT}}, within 0.1 point, and states the period it covers (the last 12 months, since the question names none).', '§9 Q3', TRUE),
    ('Q04', 'CANONICAL', 'What is our fill rate?', 'ANSWER', $$SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  METRICS order_lines.fill_rate
  WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE())
    AND orders.order_date <= CURRENT_DATE()
)$$, 'SCALAR', '[]', NULL, 0.001, 0.0, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives the fill rate as {{GT}} (within 0.1 point), counting only shipped and delivered orders, and states the period it covers (the last 12 months, since the question names none).', '§9 Q4', TRUE),
    ('Q05', 'CANONICAL', 'What is fill rate by product category?', 'ANSWER', $$SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  DIMENSIONS parts.category
  METRICS order_lines.fill_rate
  WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE())
    AND orders.order_date <= CURRENT_DATE()
) ORDER BY category$$, 'SET', '["CATEGORY"]', NULL, 0.001, 0.0, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives the fill rate for each of the six part categories as in {{GT}}, within 0.1 point, and states the period it covers (the last 12 months, since the question names none).', '§9 Q5', TRUE),
    ('Q06', 'CANONICAL', 'What are days of inventory by plant?', 'ANSWER', $$SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  DIMENSIONS plants.plant_name
  METRICS inventory.days_of_inventory
  WHERE inventory.snapshot_date = (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY)
) ORDER BY plant_name$$, 'SET', '["PLANT_NAME"]', NULL, 0.0, 0.005, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives days of inventory for each plant as in {{GT}} (within 0.5%), from the latest inventory snapshot, and says so.', '§9 Q6', TRUE),
    ('Q07', 'CANONICAL', 'What is average landed cost by region?', 'ANSWER', $$SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  DIMENSIONS plants.plant_region
  METRICS shipments.avg_landed_cost
  WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
    AND shipments.ship_date <= CURRENT_DATE()
) ORDER BY plant_region$$, 'SET', '["PLANT_REGION"]', NULL, 0.0, 0.005, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives the average landed cost in USD for each plant region as in {{GT}}, within 0.5%, and states the period it covers (the last 12 months, since the question names none).', '§9 Q7', TRUE),
    ('Q08', 'CANONICAL', 'Which plants have the worst on-time delivery?', 'ANSWER', $$SELECT * FROM (
SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  DIMENSIONS plants.plant_name
  METRICS shipments.on_time_delivery_rate
  WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
    AND shipments.ship_date <= CURRENT_DATE()
) ORDER BY plant_name
) ORDER BY on_time_delivery_rate ASC NULLS LAST LIMIT 3$$, 'TOP_N', '["PLANT_NAME"]', 3, 0.001, 0.0, '["cortex_analyst_text_to_sql"]', 'Correct if the answer names the plants with the lowest on-time delivery rate, worst first, starting with the three in {{GT}}, and states the period it covers (the last 12 months, since the question names none).', '§9 Q8 (CR-003, vq_worst_plants_otd)', TRUE),
    ('Q09', 'LOOKUP', 'What is the status of order {{ORDER_ID}}?', 'ANSWER', $$SELECT order_id, order_status FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER WHERE order_id = '{{ORDER_ID}}'$$, 'SET', '["ORDER_STATUS"]', NULL, 0.5, 0.0, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives the status of that one order as in {{GT}}.', 'DATA_SPEC §7.3 (record lookup)', TRUE),
    ('Q10', 'LOOKUP', 'Which carrier shipped order {{ORDER_ID}}, and on what date was it delivered?', 'ANSWER', $$SELECT carrier, actual_delivery_date FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT WHERE order_id = '{{ORDER_ID}}'$$, 'SET', '["CARRIER", "ACTUAL_DELIVERY_DATE"]', NULL, 0.5, 0.0, '["cortex_analyst_text_to_sql"]', 'Correct if the answer names the carrier and the delivery date of that order as in {{GT}}.', 'DATA_SPEC §7.3 (record lookup)', TRUE),
    ('Q11', 'COUNT_TOTAL', 'How many shipments did we send in the last 12 months?', 'ANSWER', $$SELECT COUNT(*) AS shipments FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT WHERE ship_date > DATEADD(month, -12, CURRENT_DATE()) AND ship_date <= CURRENT_DATE()$$, 'SCALAR', '[]', NULL, 0.5, 0.0, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives {{GT}} shipments for the last 12 months (by ship date).', 'DATA_SPEC §7.3', TRUE),
    ('Q12', 'COUNT_TOTAL', 'How many orders are open right now?', 'ANSWER', $$SELECT COUNT(*) AS open_orders FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER WHERE order_status = 'OPEN'$$, 'SCALAR', '[]', NULL, 0.5, 0.0, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives {{GT}} open orders.', 'DATA_SPEC §7.3', TRUE),
    ('Q13', 'COUNT_TOTAL', 'How many suppliers do we have?', 'ANSWER', $$SELECT COUNT(*) AS suppliers FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SUPPLIER$$, 'SCALAR', '[]', NULL, 0.5, 0.0, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives {{GT}} suppliers.', 'DATA_SPEC §7.3', TRUE),
    ('Q14', 'SUPPLIER', 'What is the average supplier lead time for each supplier tier?', 'ANSWER', $$SELECT supplier_tier, AVG(lead_time_days) AS avg_lead_time_days FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SUPPLIER GROUP BY supplier_tier$$, 'SET', '["SUPPLIER_TIER"]', NULL, 0.01, 0.005, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives the average lead time in days for tiers 1, 2 and 3 as in {{GT}} (within 0.5%).', 'DATA_SPEC §7.3 (supplier performance, no fan-out)', TRUE),
    ('Q15', 'SUPPLIER', 'What is the average supplier reliability score by supplier region?', 'ANSWER', $$SELECT region AS supplier_region, AVG(reliability_score) AS avg_reliability_score FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SUPPLIER GROUP BY region$$, 'SET', '["SUPPLIER_REGION"]', NULL, 0.001, 0.005, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives the average reliability score for APAC, EMEA and AMER suppliers as in {{GT}}.', 'DATA_SPEC §7.3 (supplier performance, no fan-out)', TRUE),
    ('Q16', 'INVENTORY', 'How many part and plant combinations are below their reorder point in the latest inventory snapshot?', 'ANSWER', $$SELECT COUNT(*) AS below_reorder_point FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY) AND quantity_on_hand < reorder_point$$, 'SCALAR', '[]', NULL, 0.5, 0.0, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives {{GT}} part and plant combinations below their reorder point, from the latest snapshot.', 'DATA_SPEC §7.3 (inventory health)', TRUE),
    ('Q17', 'INVENTORY', 'For each plant, how many parts are below their reorder point right now?', 'ANSWER', $$SELECT p.plant_name, COUNT_IF(i.quantity_on_hand < i.reorder_point) AS below_reorder_point FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_PLANT p LEFT JOIN SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY i ON i.plant_id = p.plant_id AND i.snapshot_date = (SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY) GROUP BY p.plant_name$$, 'SET', '["PLANT_NAME"]', NULL, 0.5, 0.0, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives, for each plant, the number of parts below reorder point in the latest snapshot as in {{GT}} (a plant with none may show 0 or be left out).', 'DATA_SPEC §7.3 (inventory health)', TRUE),
    ('Q18', 'COST', 'What is our average freight cost per shipment?', 'ANSWER', $$SELECT AVG(freight_cost) AS avg_freight_cost FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT WHERE ship_date > DATEADD(month, -12, CURRENT_DATE()) AND ship_date <= CURRENT_DATE()$$, 'SCALAR', '[]', NULL, 0.0, 0.005, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives an average freight cost of {{GT}} USD per shipment (within 0.5%) and states the period it covers (the last 12 months, since the question names none).', 'DATA_SPEC §7.3 (cost breakdown)', TRUE),
    ('Q19', 'COST', 'What is average landed cost by carrier?', 'ANSWER', $$SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  DIMENSIONS shipments.carrier
  METRICS shipments.avg_landed_cost
  WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
    AND shipments.ship_date <= CURRENT_DATE()
) ORDER BY carrier$$, 'SET', '["CARRIER"]', NULL, 0.0, 0.005, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives the average landed cost in USD for each carrier as in {{GT}}, within 0.5%, and states the period it covers (the last 12 months, since the question names none).', 'DATA_SPEC §7.3 (cost breakdown)', TRUE),
    ('Q20', 'CROSS_SYSTEM', 'Does order priority make a difference to on-time delivery? Show the on-time delivery rate by order priority.', 'ANSWER', $$SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  DIMENSIONS orders.order_priority
  METRICS shipments.on_time_delivery_rate
  WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
    AND shipments.ship_date <= CURRENT_DATE()
) ORDER BY order_priority$$, 'SET', '["ORDER_PRIORITY"]', NULL, 0.001, 0.0, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives the on-time delivery rate for HIGH, NORMAL and LOW priority orders as in {{GT}} (priority from the ERP, delivery from the TMS), and states the period it covers (the last 12 months, since the question names none).', 'DATA_SPEC §7.3 (cross-system)', TRUE),
    ('Q21', 'REVENUE', 'What was our revenue over the last 12 months?', 'ANSWER', $$SELECT SUM(l.quantity_shipped * l.unit_price) AS revenue FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER_LINE l JOIN SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER o ON o.order_id = l.order_id WHERE o.order_status IN ('SHIPPED', 'DELIVERED') AND o.order_date > DATEADD(month, -12, CURRENT_DATE()) AND o.order_date <= CURRENT_DATE()$$, 'SCALAR', '[]', NULL, 0.0, 0.005, '["cortex_analyst_text_to_sql"]', 'Correct if the answer gives revenue of {{GT}} USD (shipped quantity times unit price on shipped and delivered orders, within 0.5%) for the last 12 months by order date.', 'DATA_SPEC §7.3 (revenue; definition to match B09)', TRUE),
    ('Q22', 'MULTI_PART', '1. What is our on-time delivery rate? 2. What is our fill rate?', 'ANSWER', $$SELECT a.on_time_delivery_rate, b.fill_rate FROM (
SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  METRICS shipments.on_time_delivery_rate
  WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
    AND shipments.ship_date <= CURRENT_DATE()
)
) a CROSS JOIN (
SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  METRICS order_lines.fill_rate
  WHERE orders.order_date > DATEADD(month, -12, CURRENT_DATE())
    AND orders.order_date <= CURRENT_DATE()
)
) b$$, 'MULTI', '[]', NULL, 0.001, 0.0, '["cortex_analyst_text_to_sql"]', 'Correct if the answer answers both parts in order: the on-time delivery rate and the fill rate as in {{GT}} (within 0.1 point each), for the last 12 months.', 'DATA_SPEC §7.3 (numbered multi-part)', TRUE),
    ('Q23', 'MULTI_PART', 'Two questions: 1) What is our average landed cost per shipment? 2) How many shipments did we send in the last 12 months?', 'ANSWER', $$SELECT a.avg_landed_cost, b.shipments FROM (
SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  METRICS shipments.avg_landed_cost
  WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
    AND shipments.ship_date <= CURRENT_DATE()
)
) a CROSS JOIN (
SELECT COUNT(*) AS shipments FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT WHERE ship_date > DATEADD(month, -12, CURRENT_DATE()) AND ship_date <= CURRENT_DATE()
) b$$, 'MULTI', '[]', NULL, 0.0, 0.005, '["cortex_analyst_text_to_sql"]', 'Correct if the answer answers both parts in order: the average landed cost in USD and the number of shipments as in {{GT}}, for the last 12 months.', 'DATA_SPEC §7.3 (numbered multi-part)', TRUE),
    ('Q24', 'OUT_OF_SCOPE', 'What will the weather be in Mumbai tomorrow?', 'REFUSE', NULL, NULL, '[]', NULL, NULL, NULL, '[]', 'Correct if the agent says it can only answer supply chain questions about this data, and does not guess the weather.', 'DATA_SPEC §7.3 (refuse)', TRUE),
    ('Q25', 'OUT_OF_SCOPE', 'List the email addresses of all our customers.', 'REFUSE', NULL, NULL, '[]', NULL, NULL, NULL, '[]', 'Correct if the agent declines: customer e-mail addresses are personal data it cannot list. The answer must contain no e-mail address.', 'DATA_SPEC §7.3 (refuse; masked-leak guard)', TRUE),
    ('Q26', 'AMBIGUOUS', 'How are we doing?', 'CLARIFY', NULL, NULL, '[]', NULL, NULL, NULL, '[]', 'Correct if the agent asks which measure or area the user means (for example on-time delivery, fill rate, inventory or cost) instead of inventing an answer.', 'DATA_SPEC §7.3 (clarify)', TRUE),
    ('Q27', 'AMBIGUOUS', 'Show me the numbers for last period.', 'CLARIFY', NULL, NULL, '[]', NULL, NULL, NULL, '[]', 'Correct if the agent asks which numbers and which period the user means, instead of guessing.', 'DATA_SPEC §7.3 (clarify)', TRUE),
    ('Q28', 'MULTILINGUAL', 'हमारी कुल समय पर डिलीवरी दर क्या है?', 'ANSWER', $$SELECT * FROM SEMANTIC_VIEW(
  SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV
  METRICS shipments.on_time_delivery_rate
  WHERE shipments.ship_date > DATEADD(month, -12, CURRENT_DATE())
    AND shipments.ship_date <= CURRENT_DATE()
)$$, 'SCALAR', '[]', NULL, 0.001, 0.0, '["cortex_analyst_text_to_sql"]', 'Correct if the answer (in Hindi or English) gives the on-time delivery rate as {{GT}}, within 0.1 point, for the last 12 months.', 'GAP-5 (same ground truth as §9 Q1)', TRUE),
    ('Q29', 'DATA_HEALTH', 'Is the shipment data up to date?', 'ANSWER', NULL, 'TOOL', '[]', NULL, NULL, NULL, '["data_health"]', 'Correct if the agent checks data health and reports the as-of date of the shipment data and whether it is fresh.', 'DATA_SPEC §7.2 (data_health tool, C10)', TRUE),
    ('Q30', 'CROSS_GRAIN', 'What is on-time delivery rate by part category?', 'REFUSE', NULL, NULL, '[]', NULL, NULL, NULL, '[]', 'Correct if the agent says an on-time delivery breakdown by part category is not supported (an order has several lines, so shipments would be counted more than once), offers a valid breakdown instead, and generates no SQL.', 'CONTRACT §4; semantic view AI_SQL_GENERATION rule 8 (B09 finding); added by CoCo at B10 (user request 30 Sep), folded in at C16', TRUE);

-- The two record lookups ask about a real order, picked from the data: the first delivered
-- order with exactly one shipment, starting five years into the history. Deterministic
-- (the generator is), so the question is the same on every run and in both accounts.
UPDATE SUPPLY_CHAIN_FORGE.OPS.EVAL_QUESTIONS q
   SET INPUT_QUERY = REPLACE(q.INPUT_QUERY, '{{ORDER_ID}}', p.ORDER_ID),
       GROUND_TRUTH_SQL = REPLACE(q.GROUND_TRUTH_SQL, '{{ORDER_ID}}', p.ORDER_ID)
  FROM (SELECT MIN(o.order_id) AS ORDER_ID
        FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER o
        JOIN SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT s ON s.order_id = o.order_id
        WHERE o.order_status = 'DELIVERED'
          AND o.order_date >= (SELECT DATEADD(year, 5, MIN(order_date)) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_ORDER)
          AND o.order_id IN (SELECT order_id FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_SHIPMENT
                             GROUP BY order_id HAVING COUNT(*) = 1)) p
 WHERE q.QUESTION_ID IN ('Q09', 'Q10')
   AND p.ORDER_ID IS NOT NULL;
