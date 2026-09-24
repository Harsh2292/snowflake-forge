# Master Task List

> Mark tasks `[x]` when done. Tag: `[COCO]` `[CLAUDE]` `[EITHER]`

## Phase 1: Setup & Data Model

- [ ] `[COCO]` Create database `SUPPLY_CHAIN_FORGE` with schemas `RAW`, `GOVERNED`, `SEMANTIC`
- [ ] `[COCO]` Create warehouse `FORGE_WH` (XS)
- [ ] `[COCO]` Create persona roles: `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE`
- [ ] `[COCO]` Create tables: `SUPPLIERS`, `PARTS`, `PLANTS`, `SHIPMENTS`, `ORDERS`, `ORDER_ITEMS`, `CUSTOMERS`, `INVENTORY`
- [ ] `[COCO]` Load realistic sample data (50+ suppliers, 200+ parts, 500+ orders, inventory records)
- [ ] `[COCO]` Verify data model — join paths work, metrics are computable

## Phase 2: Governance Layer

- [ ] `[COCO]` Create semantic tags (entity types, metric types, PII)
- [ ] `[COCO]` Apply tags to all tables and columns
- [ ] `[COCO]` Create row access policies per persona role
- [ ] `[COCO]` Create data metric functions (null checks, referential integrity, freshness)
- [ ] `[COCO]` Validate governance — each role sees only its permitted data

## Phase 3: Semantic Views & Agent

- [ ] `[COCO]` Build semantic view YAML with all entities, relationships, metrics
- [ ] `[COCO]` Add verified query representations (VQRs) for OTD, Fill Rate, DOI, Landed Cost
- [ ] `[COCO]` Deploy and validate semantic view
- [ ] `[COCO]` Create Cortex Agent wired to the semantic view
- [ ] `[COCO]` Test agent with sample questions per persona
- [ ] `[COCO]` Update HANDOFF.md with all deployed FQNs

## Phase 4: Demo Application

- [ ] `[CLAUDE]` Build Streamlit app with persona switcher
- [ ] `[CLAUDE]` Implement Cortex Agent query integration
- [ ] `[CLAUDE]` Build consistency proof tab (same query, 3 personas, same answer)
- [ ] `[CLAUDE]` Add result visualization (charts for metrics)
- [ ] `[CLAUDE]` Write cross-persona consistency test suite
- [ ] `[CLAUDE]` Deploy Streamlit app to Snowflake (or local demo)

## Phase 5: Polish & Submission

- [ ] `[COCO]` Run lineage validation (end-to-end from raw tables to agent)
- [ ] `[COCO]` Generate data quality report
- [ ] `[EITHER]` Record demo or prepare live presentation
- [ ] `[EITHER]` Write submission README
- [ ] `[EITHER]` Final review and submission
