# CoCo Task Queue

> Owner: CoCo (Snowflake layer)
>
> **`docs/CONTRACT.md` is frozen and binding.** Every metric identifier, dimension
> identifier, view column name, role name, and FQN you create must match it exactly.
> If reality forces a deviation, file a Change Request in `CONTRACT.md` §11 and tell
> the user — do not silently rename anything. Claude Code is building against it in
> parallel right now.
>
> `docs/LLD.md` = exact specs. `docs/MILESTONES.md` = exit criteria.
> Mark `[x]` when the build step's **gate** passes, not when the SQL merely runs.

---

## Parallel Context

Claude Code is working simultaneously on the app, tests, and reference docs against the
frozen contract with a mock data layer. Your job is to make Snowflake reality match the
contract. The two tracks meet at **B14 (MCP server)** and **B17 (handoff)**.

---

## M1 — Data Foundation

### B1 — Database & Schemas
- [x] Write `sql/01_setup/01_database.sql`
- [x] Create `SUPPLY_CHAIN_FORGE` database
- [x] Create 7 schemas: `ERP_SOURCE`, `WMS_SOURCE`, `TMS_SOURCE`, `SRM_SOURCE`, `GOVERNED`, `SEMANTIC`, `APP`
- [x] Create `FORGE_WH` — XSMALL, auto-suspend 60s, auto-resume true
- [x] **Gate**: `SHOW SCHEMAS IN DATABASE SUPPLY_CHAIN_FORGE` returns 7 (+ INFORMATION_SCHEMA)

### B2 — Roles & Grants
- [x] Write `sql/01_setup/02_roles_grants.sql`
- [x] Create `FORGE_ADMIN`, `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE`
- [x] Grant usage on database + schemas + warehouse to each role
- [x] Grant `SNOWFLAKE.CORTEX_AGENT_USER` to roles that will call the agent
- [x] **Grant to the current user's DEFAULT role** — agents use default role, not session role
- [x] Grant `CREATE SEMANTIC VIEW` and `CREATE AGENT` on `SEMANTIC` schema
- [x] **Capture artifact** `docs/artifacts/01_default_role.md` — default role + warehouse
- [x] **Gate**: `SHOW GRANTS TO ROLE <each>` shows expected privileges

### B3 — Source Tables
- [x] Write `sql/02_tables/01_srm_source.sql` — `LFA1`, `MARA`, `SOURCING`
- [x] Write `sql/02_tables/02_wms_source.sql` — `T001W`, `MARD`
- [x] Write `sql/02_tables/03_erp_source.sql` — `KNA1`, `VBAK`, `VBAP`
- [x] Write `sql/02_tables/04_tms_source.sql` — `VTTK`
- [x] Delete superseded placeholder files (`suppliers.sql`, `parts.sql`, etc.)
- [x] **Gate**: 9 tables exist, column names match LLD §2 exactly

### B4 — Data Generation
- [x] Write `sql/03_sample_data/01_generate_masters.sql` — suppliers, parts, sourcing, plants, customers
- [x] Write `sql/03_sample_data/02_generate_transactions.sql` — orders, lines, shipments, inventory
- [x] Load in FK order
- [x] Ensure ERP `ERDAT` disagrees with TMS `PROM_DLV_DT` on 15–25% of orders
- [x] **Gate**: row counts within 10% of LLD §3 targets

### B5 — Distribution Verification
- [x] Write `sql/03_sample_data/03_verify_distributions.sql`
- [x] Compute raw OTD, fill rate, DOI, landed cost premium — **before** any semantic layer
- [x] **Capture artifact** `docs/artifacts/02_raw_metrics.md` — naive ERP-date OTD vs
      governed-date OTD, fill rate, DOI, landed cost premium
- [x] **Gate**: OTD 0.84–0.90, fill 0.90–0.95, DOI 15–45
- [x] Update `docs/SESSION_LOG.md`

---

## M2 — Governance Layer

### B6 — Tags & Policies
- [x] Write `sql/04_governance/01_tags.sql` — 5 tags, applied to tables and columns
- [x] Write `sql/04_governance/02_masking_policies.sql` — 4 masking policies
- [x] Write `sql/04_governance/03_row_access_policies.sql` — `RAP_PLANT_REGION`
      **DROPPED from MVP** per `docs/GAPS_RESOLVED.md` GAP-4. M6 stretch item only.
      Do not build this now — it is the component most likely to accidentally change
      metric aggregates across personas, which would break the core claim.
- [x] **Gate**: 5 tags and 4 masking policies exist in GOVERNED schema

### B7 — Governed Views
- [ ] Write `sql/04_governance/04_governed_views.sql` — 9 conformed views
- [ ] Rename all cryptic columns per LLD §4 and contract §7
- [ ] Derived time dimensions per `docs/GAPS_RESOLVED.md` GAP-2
- [ ] Expose only `shipments.promised_delivery_date` as authoritative; do NOT expose ERP `ERDAT` as a promised date
- [ ] **Capture artifact** `docs/artifacts/03_governed_columns.json` — real
      INFORMATION_SCHEMA.COLUMNS dump for all 9 views
- [ ] **Gate**: all 3 roles can `SELECT` every view; masking behaves per matrix

### B7b — Persona Procedures  ⬅ added by CR-001
Required because `USE ROLE` does not work inside Streamlit in Snowflake.
See `docs/GAPS_RESOLVED.md` GAP-1 and contract §6a.
- [ ] Write `sql/04_governance/05_persona_procedures.sql`
- [ ] Create `GOVERNED.SP_SAMPLE_AS_PLANNER()`, `..._AS_BUYER()`, `..._AS_LOGISTICS()`
- [ ] All three `EXECUTE AS OWNER`, returning the column shape in contract §5.4
- [ ] `GRANT OWNERSHIP` of each procedure to its corresponding persona role
- [ ] `GRANT USAGE` on each to `FORGE_ADMIN` (the app owner)
- [ ] **Capture artifact** `docs/artifacts/04_persona_outputs.json` — actual output of
      all three procedures, with real masked values
- [ ] **Gate**: calling all three as `FORGE_ADMIN` returns three genuinely different
      masked result sets matching contract §6 exactly
- [ ] Update `docs/SESSION_LOG.md`

### B7c — MCP Read-Only Server  ⬅ DEFERRED, not currently needed
**Do not build this yet.** Claude Code verifies via **artifact handoff**
(`docs/artifacts/README.md`) — CoCo captures real query output as committed files, so no
PAT or MCP client is required.

Build this only if artifacts prove insufficient. When that happens:
- [ ] Create least-privileged role `FORGE_MCP_READER` (read-only, no write privileges)
- [ ] `CREATE MCP SERVER SUPPLY_CHAIN_MCP_RO` with one read-only `SYSTEM_EXECUTE_SQL` tool
- [ ] Ask the user for a PAT bound to `FORGE_MCP_READER`, stored via `/secrets`
- [ ] Write the MCP client config — hostnames use **hyphens, not underscores**

> Note: `SUPPLY_CHAIN_MCP` (the agent-facing server, **B14**) is separate and **is** in
> scope. It is a product feature shown to judges, not a development dependency.

---

## M3 — Semantic Layer  ← HIGHEST RISK

### B8 — Semantic View (incremental)
- [ ] Write `semantic/01_semantic_view.sql`
- [ ] **Start with 2 tables only**: `shipments` + `orders`. Validate.
- [ ] Add one metric (`on_time_delivery_rate`). Validate with a `SEMANTIC_VIEW()` query.
- [ ] Grow to all 9 tables + 10 relationships, validating after each addition
- [ ] Add all facts, dimensions, 4 metrics with `WITH SYNONYMS` + `COMMENT`
- [ ] **Capture artifact** `docs/artifacts/05_metric_values.json` — all 4 metrics, plus
      each broken out by every valid dimension
- [ ] **Capture artifact** `docs/artifacts/06_dimension_matrix.md` — every metric ×
      dimension pairing tested, pass/fail plus error text for failures
- [ ] **Gate**: all 4 metrics return values; at least one metric × dimension combo works

### B9 — AI Instructions & Verified Queries
- [ ] Add `AI_SQL_GENERATION` instruction block
- [ ] Add `AI_QUESTION_CATEGORIZATION` instruction block
- [ ] Add 8 `AI_VERIFIED_QUERIES` per LLD §6
- [ ] **Gate**: `DESCRIBE SEMANTIC VIEW` lists all 8 VQRs
- [ ] Update `docs/SESSION_LOG.md`

---

## M4 — Conversational Layer

### B10 — Cortex Agent
- [ ] Write `agent/01_agent.sql`
- [ ] Create agent with `cortex_analyst_text_to_sql` + `data_to_chart` tools
- [ ] Wire `tool_resources` to `SUPPLY_CHAIN_SV` and `FORGE_WH`
- [ ] Set token/time budget
- [ ] Test all 8 canonical questions via `DATA_AGENT_RUN`
- [ ] **Capture artifact** `docs/artifacts/07_agent_response.json` — ONE COMPLETE
      UNMODIFIED response. Every field, every nesting level, tool traces, citations.
      Claude Code writes its response parser against this file. Do not abridge it.
- [ ] **Capture artifact** `docs/artifacts/08_agent_answers.md` — all 8 canonical
      questions with actual answers and generated SQL
- [ ] **Gate**: grounded numeric answer for all 8

### B11 — Cross-Persona Consistency
- [ ] Write `tests/consistency/consistency_check.sql`
- [ ] Run all 4 metrics as each of 3 roles
- [ ] **Gate**: values identical to 6 decimal places across roles
- [ ] **Capture artifact** `docs/artifacts/09_consistency_proof.json` — 4 metrics × 3
      personas, real values to 6 decimal places
- [ ] **Gate**: expected divergence confirmed (masked columns differ per role)

### B12 — Data Quality
- [ ] Write `sql/05_quality/01_dmfs.sql`
- [ ] Attach 5 DMFs per LLD §5.4
- [ ] **Capture artifact** `docs/artifacts/10_dmf_results.json`
- [ ] **Gate**: results appear in `DATA_QUALITY_MONITORING_RESULTS`

### B13 — Contract Conformance Audit  ⬅ do this before handoff
Verify Snowflake reality against `docs/CONTRACT.md` line by line. Claude Code built the
entire app assuming these exact names.
- [ ] All 4 metric identifiers resolve in `SEMANTIC_VIEW()` queries (§3)
- [ ] All dimension identifiers resolve (§4)
- [ ] Every valid metric × dimension pairing returns rows (§4)
- [ ] `days_of_inventory` × `orders.*` fails as documented (§4)
- [ ] Every governed view column name matches (§7)
- [ ] Masking matrix behaves exactly as specified, per role (§6)
- [ ] Metric values sit inside the documented ranges (§3)
- [ ] The divergence demo queries return two different numbers (§8)
- [ ] **Gate**: zero deviations, or every deviation filed as a Change Request in
      `CONTRACT.md` §11 with the user notified

### B14 — MCP Server  ⬅ unblocks Claude Code's live work
- [ ] Write `mcp/01_mcp_server.sql`
- [ ] `CREATE MCP SERVER SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_MCP`
- [ ] Expose the Cortex Agent as the primary tool (`CORTEX_AGENT_RUN`)
- [ ] Expose the semantic view via `CORTEX_ANALYST_MESSAGE`
- [ ] Expose read-only `SYSTEM_EXECUTE_SQL` on a **separate least-privileged path**
      (Snowflake explicitly warns against co-locating it with the agent tool, since it
      lets a client bypass verified queries)
- [ ] Grant `USAGE` on the MCP server to the persona roles
- [ ] **Gate**: MCP tool discovery returns the expected tool list

### B15 — Handoff
- [ ] Update `.agents/HANDOFF.md` with all deployed FQNs, role names, and MCP endpoint
- [ ] Mark every `Ready for Handoff` row as DONE
- [ ] Tell the user Claude Code is unblocked for Track C6
- [ ] Update `docs/SESSION_LOG.md` and `docs/MILESTONES.md`

---

## M6 — Differentiation (CoCo portion)

- [ ] Verify the "disagreement" demo SQL returns two genuinely different numbers, and
      hand the exact values to Claude Code for Tab 3
- [ ] Run `cortex lineage` trace from source column → governed view → semantic view
- [ ] Edge-case suite: ambiguous question, out-of-scope question, cross-domain question
- [ ] Multilingual test: same question in Hindi, assert identical number
- [ ] `sql-verify` subagent sweep over all SQL files
- [ ] Security review: no hardcoded creds, no over-broad grants, all PII masked,
      MCP server least-privilege confirmed
