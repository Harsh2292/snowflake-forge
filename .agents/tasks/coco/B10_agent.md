# B10 — Cortex Agent + evaluation set (Day 2)

> **Owner**: CoCo · **Milestone**: M4 · **Contract**: v1.5 (§3a, §4, §5.3, §9)
> **Spec**: `.agents/tasks/COCO_TASKS.md` § B10 · **Plan mode**: waived by the user (30 Sep)
> **Depends on**: B09 (semantic view v2), C10 objects (`SEMANTIC.SP_DATA_HEALTH`, created at B12
> step 0), C11 (`eval/`, handoff lock)

## Goal

One Cortex Agent, `SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT`, that answers supply chain
questions only through the governed semantic view, refuses what is out of scope or
cross-grain, asks when a question is ambiguous, and can report data health. Then measure it
with Claude Code's C11 evaluation set.

## Build

1. `agent/01_agent.sql` (re-runnable, account-agnostic, run as `FORGE_ADMIN`):
   - `CREATE OR REPLACE AGENT … COPY GRANTS FROM SPECIFICATION`
   - tools:
     - `supply_chain_analyst`: `cortex_analyst_text_to_sql` on `SEMANTIC.SUPPLY_CHAIN_SV`,
       `FORGE_WH`, query timeout 60 s. Name search goes through the view's dimensions.
     - `data_to_chart`
     - `data_health`: `generic`, the procedure `SEMANTIC.SP_DATA_HEALTH(VARCHAR)` (C10),
       input `entity` (one of the 9 entities or `ALL`), `FORGE_WH`, 30 s
   - orchestration instructions:
     - which tool when
     - refuse out-of-scope questions and masked personal data without calling a tool
     - ask one clarifying question when the measure or the period is unclear
     - refuse cross-grain breakdowns (the view's `AI_SQL_GENERATION` rule 8; the B09 finding)
       and offer the nearest valid §4 pairing
     - numbered parts are answered in order, one analyst call each
   - response instructions:
     - state the time window (§3a)
     - show the SQL
     - format per §3
     - answer in the user's language
   - the 8 §9 sample questions; budget 120 s / 32K tokens
   - model: `claude-sonnet-4-5` for the baseline. Compare models only if the baseline fails
     the gate (budget).
2. Grants: `USAGE` on the agent to `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE`
   (`FORGE_ADMIN` owns it). `USAGE` on `SP_DATA_HEALTH` for the personas comes from C10 file 30.
3. Record which role the agent's SQL runs under when called through `DATA_AGENT_RUN` (art 01:
   the caller's default role).

## Run C11 (handoff lock)

`eval/00` (ACCOUNTADMIN) → `10`, `20`, `30` (FORGE_ADMIN) → `99` steps 1–4 (FORGE_ADMIN).
- **User request (30 Sep):** add one cross-grain question, "OTD by part category", with an
  expected refusal. `eval/` is Claude Code's, so it is added at run time as row **Q30**
  (`CROSS_GRAIN`, `REFUSE`) in `OPS.EVAL_QUESTIONS`, and handed back to Claude Code in the run
  report to fold into `10_questions.sql`.
- Step 5 (native evaluation) is optional; skipped for budget unless the grants already exist.

## Capture

- **Art 07** `docs/artifacts/07_agent_response.json`: one complete, unmodified
  `DATA_AGENT_RUN` response (Q02, OTD by region).
- **Art 08** `docs/artifacts/08_agent_answers.md`: every question with its answer, SQL,
  pass/fail and latency, plus the run summary.
- Run report `docs/artifacts/runs/C11_run.md`.

## Gate

| # | Check | Result |
|---|---|---|
| 1 | The 8 canonical answers (Q01–Q08) match art 05 (the runner's ground truth is the app's SQL) | |
| 2 | Out-of-scope questions (Q24, Q25) and the cross-grain question (Q30) are refused; ambiguous ones (Q26, Q27) get a clarifying question | |
| 3 | Pass rate by category and latencies recorded in art 08 | |
| 4 | No masked value leaks into an answer (no e-mail in any answer; no unit cost, contract price, payment terms or credit limit values) | |
| 5 | `data_health` is called for the data-health question (Q29) | |
| 6 | `agent/01_agent.sql` re-runs cleanly and names no account | |

## Result: ✅ done 2026-09-30, gate 6/6

| # | Check | Result |
|---|---|---|
| 1 | The 8 canonical answers (Q01–Q08) match art 05 (the runner's ground truth is the app's SQL) | ✅ 8/8 |
| 2 | Refusals and clarifying questions | ✅ Q24, Q25, Q30 refused (Q30: *"not supported because a shipment can contain multiple order lines…"*, offers plant, region, carrier, customer or status); Q26, Q27 ask which metric and period |
| 3 | Pass rate by category and latencies recorded in art 08 | ✅ **27/30 = 90%**; p50 17.7 s, p95 48.8 s, max 77.6 s |
| 4 | No masked value leaks | ✅ none of the 30 answers contains an e-mail, a credit limit, payment terms, a contract price or a unit cost |
| 5 | `data_health` called for Q29 | ✅ |
| 6 | `agent/01_agent.sql` re-runs cleanly, names no account | ✅ re-run: created + 3 grants; no account, user or region in the file |

Artifacts: art 07 `07_agent_response.json` (fresh Q02 call, raw text byte for byte, 4,055
bytes), art 08 `08_agent_answers.md`. Run report: `docs/artifacts/runs/C11_run.md`.

**Findings**
1. **CR-007 (proposed): the §5.3 call fails live.** `DATA_AGENT_RUN` needs a constant
   request, so `OBJECT_CONSTRUCT(… ? …)::VARCHAR` is rejected at compile time. Binding the
   whole JSON text as one `?` works. The user approved filing the CR and continuing.
   `SP_RUN_EVAL` got a 3-line run fix. The app's `forge_data.build_agent_sql` needs the same
   change (Claude Code).
2. **The agent's tools run as the calling role** (82 generated queries as `FORGE_ADMIN` on
   `FORGE_WH`), not the user's default role as art 01 assumed. Good for `FORGE_APP_ROLE`.
3. **`COPY GRANTS` is rejected** in `CREATE OR REPLACE AGENT` (syntax error), so the file
   re-issues its grants instead.
4. A custom-tool `identifier` without an argument signature works
   (`SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH`).
5. **Two real agent misses:**
   - Q15: Analyst dropped `region` from its CTE
   - Q21: revenue built by hand instead of `total_revenue`, missing the status filter

   Both can be fixed with verified queries in the view (B09a, or a small B09 follow-up).
   Q17 is an evaluation-set strictness issue (Claude Code).
6. Model: `claude-sonnet-4-5` kept. The baseline passes the gate, so no model comparison was
   run (budget).
