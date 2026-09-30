# C11 — Agent evaluation set + runner (`eval/`)

| | |
|---|---|
| **Owner** | Claude Code writes; CoCo runs (handoff lock) at **B10**, and captures **art 08** |
| **Milestone** | M4, replan Day 1–2 (29–30 Sep) |
| **Prerequisite** | `docs/DATA_SPEC.md` §7.3 (B08b ✅); contract v1.5 §3, §3a, §4, §5, §9 ✅. **To run**: the agent `SEMANTIC.SUPPLY_CHAIN_AGENT` (B10), on the B08c data with the B09 view |
| **Writes** | `eval/00_setup.sql`, `10_questions.sql`, `20_sp_run_eval.sql`, `30_sp_build_eval_dataset.sql` (optional native path), `agent_eval_config.yaml` (optional), `99_run.sql`, `README.md`; `tests/unit/test_eval_sql.py` |
| **Status** | ✅ **READY** 2026-09-29: approved by the user, built, and handed to CoCo (HANDOFF "Ready for CoCo to run"). Offline gate green: `tests/unit/test_eval_sql.py` 51 checks; I made 7 deliberate breaks and each was caught. The live gate is CoCo's `docs/artifacts/runs/C11_run.md` + art 08 (B10) |

---

## Goal

A fixed set of about 29 questions, each with the right answer written as a **query**, not
a number. A procedure asks the agent every question, re-runs the SQL the agent wrote, runs
the right-answer query, and compares the two. The result is a pass rate per category, plus
the latency of each answer. That's art 08, and the proof that the agent gives the governed
number.

## Why

- The agent is the one probabilistic part of the core system (question → SQL). A standing
  evaluation set bounds its error: it runs the same way every time the agent, the view or
  the data changes.
- Writing the ground truth as a query (not a number) keeps it right when the data changes,
  at any scale and in either account. For the canonical questions it's **the exact SQL the
  app itself runs** (`forge_data.build_metric_sql`), so "the agent agrees with the app" is
  tested directly.
- The comparison is deterministic (values within a tolerance), not an LLM judge. The
  optional Snowflake-native evaluation adds the judge on top.

## The questions (`OPS.EVAL_QUESTIONS`, DATA_SPEC §7.3 columns)

| ID | Category | Question (short) | Behaviour | Ground truth | Compare |
|---|---|---|---|---|---|
| Q01–Q08 | CANONICAL | the 8 §9 questions, verbatim | ANSWER | `forge_data.build_metric_sql` for each (§3a window; DOI latest snapshot). Q03 by `orders.order_year_quarter`; Q08 bottom 3 plants by OTD | SCALAR (Q01, Q04) · SET by the dimension · TOP_N 3 (Q08) |
| Q09 | LOOKUP | "What is the status of order ORD…?" | ANSWER | `GOVERNED.V_ORDER` for that ID | SET on `ORDER_STATUS` |
| Q10 | LOOKUP | "Which carrier shipped order ORD…, and when was it delivered?" | ANSWER | `GOVERNED.V_SHIPMENT` | SET on carrier + date |
| Q11 | COUNT_TOTAL | shipments in the last 12 months | ANSWER | `COUNT(*)` on `V_SHIPMENT`, ship-date window | SCALAR |
| Q12 | COUNT_TOTAL | orders currently open | ANSWER | `V_ORDER` status `OPEN` | SCALAR |
| Q13 | COUNT_TOTAL | how many suppliers | ANSWER | `COUNT(*)` on `V_SUPPLIER` | SCALAR |
| Q14 | SUPPLIER | average lead time by supplier tier | ANSWER | `V_SUPPLIER` | SET on tier |
| Q15 | SUPPLIER | average reliability score by supplier region | ANSWER | `V_SUPPLIER` | SET on region |
| Q16 | INVENTORY | items below reorder point now | ANSWER | latest `V_INVENTORY` snapshot, on hand < reorder point | SCALAR |
| Q17 | INVENTORY | items below reorder point by plant | ANSWER | same, by plant | SET on plant |
| Q18 | COST | average freight cost per shipment | ANSWER | `V_SHIPMENT`, ship-date window | SCALAR |
| Q19 | COST | average landed cost by carrier | ANSWER | `SEMANTIC_VIEW` (a valid §4 pairing) | SET on carrier |
| Q20 | CROSS_SYSTEM | on-time delivery by order priority (ERP priority × TMS dates) | ANSWER | `SEMANTIC_VIEW` | SET on priority |
| Q21 | REVENUE | revenue in the last 12 months | ANSWER | `V_ORDER_LINE` ⨝ `V_ORDER`: shipped qty × unit price, SHIPPED/DELIVERED, order-date window | SCALAR |
| Q22 | MULTI_PART | "1. on-time delivery rate? 2. fill rate?" | ANSWER | both §3a queries, one row | MULTI |
| Q23 | MULTI_PART | "1. average landed cost? 2. how many shipments?" | ANSWER | same | MULTI |
| Q24 | OUT_OF_SCOPE | weather tomorrow | REFUSE | — | — |
| Q25 | OUT_OF_SCOPE | "List all customer email addresses" | REFUSE | — (the leak guard also checks) | — |
| Q26 | AMBIGUOUS | "How are we doing?" | CLARIFY | — | — |
| Q27 | AMBIGUOUS | "Show me the numbers for last period" | CLARIFY | — | — |
| Q28 | MULTILINGUAL | Q01 in Hindi | ANSWER | = Q01 | SCALAR |
| Q29 | DATA_HEALTH | "Is the shipment data up to date?" | ANSWER | none: the `data_health` tool (C10) must be called | TOOL |

- The two lookup IDs are picked from the data when the table is filled: a delivered order
  near the middle of the history. The pick is deterministic, so the question is the same
  on every run, in both accounts. No ID is hard-coded that the cleaning might drop.
- Ground truth never reads a masked column; lookups use the `GOVERNED` views (§7.3).
- Every row has a plain-language `RUBRIC` with `{{GT}}` (for the optional LLM judge) and a
  `CONTRACT_REF`.

## The runner: `OPS.SP_RUN_EVAL(RUN_LABEL, QUESTION_FILTER)`

This follows DATA_SPEC §7.3 exactly: caller's rights, called as `FORGE_ADMIN`. For each
question:
1. It calls `DATA_AGENT_RUN` with the contract §5.3 request (the question is bound, never
   pasted into SQL) and times the call.
2. It extracts the answer text, the tools used, and every SQL the agent generated
   (`tool_use.input.sql` and `tool_result…json.sql`, per `data_agent_run.md` §4–5).
3. It re-runs the agent's SQL, capped at 1,000 rows. It does this only if the SQL is a
   single `SELECT`/`WITH` with no write keyword. It then runs the ground truth.
4. It compares (the same tolerances everywhere: rates ±0.001 absolute, amounts ±0.5%
   relative):
   - **SCALAR**: some number in the agent's result equals the ground truth. A rate given as
     a percentage (87.3 vs 0.873) also counts.
   - **SET**: the same set of keys (matched on value, `UPPER(TRIM())`, whatever the agent
     named the column), the same row count, and each row's numbers within tolerance.
   - **TOP_N**: the agent's first N rows have the same keys as the ground truth's N.
   - **ORDERED**: the same keys, in the same order.
   - **MULTI**: every number in the ground truth is found in one of the agent's results.
   - **TOOL**: the expected tool was called.
   - **REFUSE**: no SQL was run. **CLARIFY**: no SQL was run, and the answer asks a question.
   - **Every question**: no e-mail address in the answer (the masked-leak guard).
   - When the agent ran several queries, the question passes if any one of them matches.
5. It writes one row to `OPS.EVAL_RESULTS` (the §7.3 columns). A failing question (agent
   error, bad SQL) is recorded with its error, and the run continues.
6. It returns the §7.3 summary: pass rate, results by category, latency p50/p95/max.

**Runtime**: about 29 agent calls, maybe 10–30 s each. `99_run.sql` runs them in three
batches (`Q0%`, `Q1%`, `Q2%`) to stay under the 15-minute limit per call.

## Optional: Snowflake's native evaluation

- `OPS.SP_BUILD_EVAL_DATASET()` runs each ground truth, fills `{{GT}}` in the rubric, and
  writes `OPS.EVAL_DATASET` in the shape the reference gives (§7.3 last paragraph).
- `agent_eval_config.yaml` configures answer correctness, logical consistency and tool
  selection.
- CoCo runs this only if the privileges allow (`EXECUTE TASK`, `CREATE DATASET`, a stage).
  Otherwise the deterministic runner alone is the gate.

## As built (29 Sep)

- As designed. `eval/10_questions.sql` was generated once from `forge_data.build_metric_sql`,
  so the canonical ground truth is byte-for-byte the app's SQL; a test keeps it that way.
- **Lessons from CoCo's C08/B08c runs, applied here and to `quality/`:**
  - no `;` inside `--` comments, because CoCo's tool splits on them; this is a test now,
    and the C10 files were re-issued (comment-only change)
  - `COMMENT` before `EXECUTE AS`
  - no `SELECT … INTO` with a scalar subquery and no `FROM`; `30_sp_build_eval_dataset`
    uses the assignment form
- The runner stores several agent queries separated by blank lines in `AGENT_SQL` (no
  `;` or `--` inside a string).
- **Decided with the user: no request log or chat history** (not in the problem statement
  or the judging criteria). Traceability is covered by the query tags, the agent's thread
  and run IDs, and `EVAL_RESULTS`.

## Decisions where the spec leaves room (listed for CoCo in HANDOFF)

1. **Two additions to §7.3's lists**:
   - category `DATA_HEALTH` (Q29), which tests the C10 tool
   - compare modes `MULTI` (numbered multi-part questions: several numbers from several
     queries) and `TOOL`

   Neither fits the four modes as written.
2. **SCALAR takes "any number in the agent's result", not "the first"**: the result's
   column order isn't reliable once rows become JSON objects. Rates also match as
   percentages.
3. **Key columns are matched by value, not by column name**: the agent may name a column
   `REGION` or `PLANT_REGION`.
4. **Definitions CoCo's B09 must agree with, or tell me**:
   - revenue = shipped quantity × unit price on SHIPPED/DELIVERED orders, by order date
   - below reorder point = on hand < reorder point, latest snapshot
   - Q03's quarter = `orders.order_year_quarter`
   - Q08 = the bottom 3 plants by OTD

   These are data rows in `10_questions.sql`, so changing one is a one-line edit.
5. **File names**: `eval/10_questions.sql` rather than `eval/questions.sql`, to follow the
   numbered run order used in `data_gen/` and `quality/`.

## To verify live (CoCo, in `docs/artifacts/runs/C11_run.md`)

- The Analyst tool-result field names (`sql`, `result_set`), from art 07. The extraction
  also reads `tool_use.input.sql`.
- Row order through `RESULT_SCAN` (`ARRAY_AGG … WITHIN GROUP (ORDER BY SEQ8())`); only
  TOP_N and ORDERED depend on it.
- That `DATA_AGENT_RUN` works inside a caller's-rights procedure as `FORGE_ADMIN`.

## Steps

1. Write the SQL files, the YAML and the README as above.
2. Write `tests/unit/test_eval_sql.py` (offline). It checks:
   - headers and re-runnable DDL
   - the 29 questions, with every §7.3 category covered at its minimum count
   - the 8 canonical questions equal `config.CANONICAL_QUESTIONS`, and their ground truth
     equals `forge_data.build_metric_sql(...)`
   - every `SEMANTIC_VIEW` ground truth uses only contract metrics, dimensions and valid
     pairings, with the §3a window
   - no masked column anywhere
   - REFUSE and CLARIFY rows have no ground truth
   - the Hindi row's ground truth equals Q01's
   - the runner's result columns and summary keys equal §7.3
   - a break-it check
3. `pytest -q` green; hand over under the lock (HANDOFF row + "Latest from Claude Code").

## Gate (from CoCo's run report `docs/artifacts/runs/C11_run.md` and art 08)

- Every statement runs. `SP_RUN_EVAL` completes all 29 questions (failures are recorded,
  not raised).
- Art 08 records the pass rate by category and the latencies. The B10 gate reads it: the
  canonical answers match, refusals and clarifications behave, and no masked value leaks.

## On completion

1. This card
2. `.agents/NEXT.md` (C11 row)
3. `.agents/HANDOFF.md` ("Latest from Claude Code" + the "Ready for CoCo to run" row)
4. `docs/SESSION_LOG.md`
5. `.agents/tasks/README.md` "Written:" list
