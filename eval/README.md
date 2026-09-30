# `eval/`: the agent evaluation set (C11)

This folder holds 29 questions a real user might ask, each with the right answer written
as a query. A procedure asks the agent every question, re-runs the SQL the agent wrote,
runs the right-answer query, and compares the two. The result is a pass rate by category,
plus the latency of each answer. That's art 08, and the proof that the agent gives the
governed number.

Written by Claude Code; run by CoCo at **B10** (handoff lock). Card:
`.agents/tasks/claude/C11_eval_set.md`. Spec: `docs/DATA_SPEC.md` §7.3.

## Files, in run order

| File | Role | What it does |
|---|---|---|
| `00_setup.sql` | `ACCOUNTADMIN` | Grants `FORGE_ADMIN` what it needs in `OPS`, and Cortex access (optional grants for the native path are commented) |
| `10_questions.sql` | `FORGE_ADMIN` | `OPS.EVAL_QUESTIONS`, 29 rows; fills the two lookup order IDs from the data |
| `20_sp_run_eval.sql` | `FORGE_ADMIN` | `OPS.EVAL_RESULTS` and `OPS.SP_RUN_EVAL(RUN_LABEL, QUESTION_FILTER)` |
| `30_sp_build_eval_dataset.sql` | `FORGE_ADMIN` | Optional: `OPS.SP_BUILD_EVAL_DATASET(ANALYST_TOOL_NAME)` for Snowflake's native evaluation |
| `agent_eval_config.yaml` | — | Optional: the native evaluation config (answer correctness, logical consistency, tool selection) |
| `99_run.sql` | `FORGE_ADMIN` | The calls: a readiness check, three batches, the art 08 query, and the optional native run |

## The questions

| Category | IDs | Checks |
|---|---|---|
| `CANONICAL` | Q01–Q08 | the 8 contract §9 questions; the ground truth is **the SQL the app runs** |
| `LOOKUP` | Q09–Q10 | one order's status; its carrier and delivery date (the ID is picked from the data) |
| `COUNT_TOTAL` | Q11–Q13 | shipments in the last 12 months, open orders, suppliers |
| `SUPPLIER` | Q14–Q15 | lead time by tier, reliability by region (from the supplier table, so no fan-out) |
| `INVENTORY` | Q16–Q17 | below reorder point, in total and by plant (latest snapshot) |
| `COST` | Q18–Q19 | average freight; average landed cost by carrier |
| `CROSS_SYSTEM` | Q20 | OTD by order priority (ERP priority × TMS dates) |
| `REVENUE` | Q21 | shipped quantity × unit price, last 12 months |
| `MULTI_PART` | Q22–Q23 | numbered two-part questions |
| `OUT_OF_SCOPE` | Q24–Q25 | must refuse (weather; customer e-mails) |
| `AMBIGUOUS` | Q26–Q27 | must ask a clarifying question |
| `MULTILINGUAL` | Q28 | Q01 in Hindi, with the same ground truth |
| `DATA_HEALTH` | Q29 | must call the `data_health` tool (C10) |

## How an answer is graded

Every question is graded deterministically, with no LLM judge:
- the agent's SQL is re-run (only a single read-only `SELECT`/`WITH`, capped at 1,000 rows)
- the ground truth is run
- the two are compared by `COMPARE_MODE`

| Mode | Passes when |
|---|---|
| `SCALAR` / `MULTI` | every ground-truth number appears in the agent's results, within tolerance (a rate given as a percentage also counts) |
| `SET` | the same keys (matched by value, whatever the agent named the column), the same row count, and the numbers within tolerance |
| `TOP_N` | the agent's first N rows have the ground truth's keys |
| `ORDERED` | the same keys in the same order |
| `TOOL` | the expected tool was used |
| REFUSE / CLARIFY | no SQL was generated; for CLARIFY, the answer also asks a question |

**Every answer** also fails if it contains an e-mail address (the masked-leak guard).

**Tolerances:** rates ±0.001; amounts and averages ±0.5%; counts exact.

## To verify live (CoCo, in `docs/artifacts/runs/C11_run.md`)

1. The Analyst tool-result field names (`sql`, `result_set`), against art 07. The runner
   also reads `tool_use.input.sql`.
2. Row order through `RESULT_SCAN` (`SEQ8()`). Only `TOP_N` and `ORDERED` depend on it.
3. That `DATA_AGENT_RUN` works inside a caller's-rights procedure as `FORGE_ADMIN`.
4. That B09's definitions agree with the ground truth:
   - revenue
   - below reorder point
   - Q03's quarter (`orders.order_year_quarter`)
   - Q08 = the bottom 3 plants

   Each is a one-row change in `10_questions.sql`.
