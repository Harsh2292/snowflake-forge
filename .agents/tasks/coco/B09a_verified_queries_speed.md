# B09a — Verified queries for the C11 misses + agent speed (reduced)

| | |
|---|---|
| **Owner** | CoCo |
| **Status** | ✅ done 2026-09-30: final eval in the new account at B08m, **28/30, p50 12.3 s, p95 36.5 s** (baseline 27/30, 17.7 s, 48.8 s); art 08 re-written |
| **Scope** | Reduced with the user's approval (30 Sep): **no metadata-driven generator, no name search** (both → `docs/ROADMAP.md` material). Verified queries for the questions the agent missed, and Claude Code's agent-speed suggestion |
| **Writes** | `semantic/01_semantic_view.sql`, `agent/01_agent.sql`; art 08 (at B08m) |

## What changed

1. **3 verified queries** in `SUPPLY_CHAIN_SV` (12 → 15), for the questions where Analyst wrote
   its own CTE at B10 (art 08):
   - `vq_reliability_by_supplier_region` (Q15): `suppliers.avg_reliability_score` by
     `suppliers.supplier_region`. Checked equal to the ground truth: AMER 0.8648, APAC 0.8711,
     EMEA 0.8811.
   - `vq_revenue_last_12_months` (Q21): `order_lines.total_revenue`, last 12 months by order
     date. Equal to the ground truth: 10,062,971,242.50 USD.
   - `vq_landed_cost_overall` (Q23, Claude Code's C14 note): **removed at B08m**. Analyst
     matched "average freight cost per shipment" (Q18) to it and answered landed cost ($604.81);
     without it Q18 passes ($468.29). The view has **14** verified queries.
2. **Agent speed** (Claude Code's suggestion, HANDOFF 30 Sep):
   - removed "show the SQL in a sql code block" from `response` (the app shows the tool's SQL)
   - removed the `data_to_chart` tool (the app draws its own charts)
   - added: "Never create a chart or visualization, and never use a charting tool or skill…",
     because the orchestrator still reached a built-in chart skill (`server_skill` +
     `data_to_chart` in `TOOLS_USED`) on Q02, Q05, Q14, Q19 without the tool
   - **Haiku not tried**: the pass rate is the priority, and Sonnet now passes 30/30. Try only
     if there's budget and time after B15
3. After re-creating the agent, `GRANT USAGE … TO ROLE FORGE_APP_ROLE` must be re-applied
   (it lives in `sql/05_app_access/01_app_service_user.sql`; `CREATE OR REPLACE AGENT` drops
   grants). In the B08m replay 05_app_access runs after the agent, so it's automatic.

## Measured (old account, 30 Sep, label `b10-v2`, before the no-chart line)

| | b10-baseline (B10) | b10-v2 |
|---|---|---|
| Passed | 27/30 | **30/30** |
| p50 / p95 | 17.7 s / 48.8 s | 18.9 s / 44.6 s (4 batches ran concurrently) |
| Q15 | FAIL, 77.6 s | PASS, 8.0 s |
| Q21 | FAIL, 26.7 s | PASS, 9.4 s |
| Q23 | 38.0 s | 19.2 s |
| Q17 | FAIL (ground truth) | PASS (C16's ground-truth fix) |
| Q02 / Q05 / Q14 / Q19 | 12.9 / 13.2 / 25.6 / 13.2 s | 29.3 / 29.6 / 46.3 / 19.6 s (built-in chart skill) |

## Gate

- [x] The new verified-query SQLs return the ground truth
- [x] Pass rate ≥ 27/30 (old account 30/30; new account 28/30: Q22 a real Analyst miss on a
      two-part question, Q23 a runner limitation with a correct answer; `runs/B08m_run.md`)
- [x] Q02/Q05/Q19 no longer use a chart skill (11.1 / 10.3 / 8.4 s); p50 12.3 s < 17.7 s
- [x] Art 08 re-written from `b10-v2` in the new account
