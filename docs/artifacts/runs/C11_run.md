# C11 run report — agent evaluation set (run by CoCo at B10)

| | |
|---|---|
| **Date** | 2026-09-30 (09:55–10:22 UTC) |
| **Account** | `tyduokn-gf25237` (DA53081, AZURE_CENTRALINDIA, Enterprise) |
| **Role / warehouse** | `00` as `ACCOUNTADMIN`; `10`, `20`, `30` and every `99` step as `FORGE_ADMIN`; `FORGE_WH` |
| **Agent** | `SEMANTIC.SUPPLY_CHAIN_AGENT` from `agent/01_agent.sql` (B10), model `claude-sonnet-4-5` |
| **Run label** | `b10-baseline` (plus a one-question dry run, `b10-dry`, Q01: passed, 12.6 s) |
| **Status** | **DONE**: one run-blocking fix (3 lines, below) and one added question (Q30) |
| **Artifacts** | `docs/artifacts/07_agent_response.json`, `docs/artifacts/08_agent_answers.md` |

## The §5.3 finding (the reason for the fix, and CR-007)

`SNOWFLAKE.CORTEX.DATA_AGENT_RUN` requires its request argument to be a **constant**. Verbatim,
for `SP_RUN_EVAL`'s call as written:

```
SQL compilation error:
argument 1 to function SqlIdentifier{qualifierNames=[], identifierName=SYSTEM$CORTEX_DATA_AGENT_RUN_V2}
needs to be constant, found 'CAST(OBJECT_CONSTRUCT('messages', ARRAY_CONSTRUCT(OBJECT_CONSTRUCT('role',
'user', 'content', ARRAY_CONSTRUCT(OBJECT_CONSTRUCT('type', 'text', 'text', :question))))) AS VARC…
```

Tested, same agent, one cheap out-of-scope question each:

| Form | Result |
|---|---|
| `OBJECT_CONSTRUCT(… 'literal question' …)::VARCHAR` | fails (needs to be constant) |
| `OBJECT_CONSTRUCT(… :question …)::VARCHAR` in Scripting (`SP_RUN_EVAL` as written) | fails |
| `OBJECT_CONSTRUCT(… ? …)::VARCHAR` bound with `EXECUTE IMMEDIATE … USING` (**contract §5.3 and `forge_data.build_agent_sql`**) | **fails** |
| a string literal of the whole JSON | works (12.9 s) |
| `req := (SELECT TO_JSON(OBJECT_CONSTRUCT(…, :q …)))`, then `DATA_AGENT_RUN(…, :req, TRUE)` | works (14.2 s) |
| `DATA_AGENT_RUN(…, ?, TRUE)` with `?` bound to the whole JSON text | works (11.8 s); art 07 was captured this way |

So the app's live Ask path fails as written. **CR-007** (contract §11, PROPOSED; the user
approved filing it and continuing) changes §5.3 to bind the whole request JSON as one `?`.
**For Claude Code (the app):** `ask_agent` should bind
`json.dumps({"messages": [{"role": "user", "content": [{"type": "text", "text": question}]}]})`
to `DATA_AGENT_RUN('<agent>', ?, TRUE)`. The response shape is unchanged (art 07).

## Fix CoCo applied (run-blocking, `20_sp_run_eval.sql`, +1 declaration, the call rewritten)

```diff
     resp_text     VARCHAR;
+    req_text      VARCHAR;
     answer        VARCHAR;
 …
             -- 1. Ask the agent (contract §5.3, non-streaming, a new thread per call).
+            -- B10 run fix (CR-007): the request must be a constant, so build it first.
+            req_text := (SELECT TO_JSON(OBJECT_CONSTRUCT('messages', ARRAY_CONSTRUCT(
+                           OBJECT_CONSTRUCT('role', 'user', 'content',
+                               ARRAY_CONSTRUCT(OBJECT_CONSTRUCT('type', 'text', 'text', :question)))))));
             t0 := SYSDATE();
             SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
-                       'SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT',
-                       OBJECT_CONSTRUCT('messages', ARRAY_CONSTRUCT(
-                           OBJECT_CONSTRUCT('role', 'user', 'content',
-                               ARRAY_CONSTRUCT(OBJECT_CONSTRUCT('type', 'text', 'text', :question)))))::VARCHAR,
-                       TRUE)
+                       'SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT', :req_text, TRUE)
               INTO :resp_text;
```

The latency still measures only the agent call (`t0` is set after the JSON is built).

## Added question: Q30 (the user's request; please fold it into `10_questions.sql`)

Inserted at run time after `10_questions.sql`, so the file itself is unchanged:

```sql
INSERT INTO SUPPLY_CHAIN_FORGE.OPS.EVAL_QUESTIONS
SELECT 'Q30', 'CROSS_GRAIN', 'What is on-time delivery rate by part category?', 'REFUSE', NULL, NULL,
       ARRAY_CONSTRUCT(), NULL, NULL, NULL, ARRAY_CONSTRUCT(),
       'Correct if the agent says an on-time delivery breakdown by part category is not supported (an order has several lines, so shipments would be counted more than once), offers a valid breakdown instead, and generates no SQL.',
       'CONTRACT §4; semantic view AI_SQL_GENERATION rule 8 (B09 finding); added by CoCo at B10 (user request 30 Sep)', TRUE;
```

`CROSS_GRAIN` is a new category. Step 1's expected count becomes 30, and `99_run.sql` needs a
4th batch, `SP_RUN_EVAL('<label>', 'Q3%')`.

## Outcome by file

| File | Statements | Outcome |
|---|---|---|
| `00_setup.sql` | 5 | all OK (optional native-evaluation grants not given; step 5 skipped for budget) |
| `10_questions.sql` | 3 | `EVAL_QUESTIONS` created; 29 rows; the lookup `UPDATE` filled 2 rows |
| `20_sp_run_eval.sql` | 2 | `EVAL_RESULTS` created; `SP_RUN_EVAL` created (with the fix) |
| `30_sp_build_eval_dataset.sql` | 1 | `SP_BUILD_EVAL_DATASET` created (not called: step 5 skipped) |

## `99_run.sql`

| Step | Result |
|---|---|
| 1 readiness | `QUESTIONS 30, UNFILLED 0` (29 + Q30) |
| 2 `SP_RUN_EVAL('b10-baseline', 'Q0%')` | 9/9 passed. My REPL's wait timed out while the calls kept running server-side, so the summaries for Q0 and Q1 were read from `EVAL_RESULTS` |
| 2 `… 'Q1%'` | 10 answered, 8 passed (Q15, Q17) |
| 2 `… 'Q2%'` | cumulative 26/29, `pass_rate 0.8966` |
| 2 `… 'Q3%'` (added) | cumulative **27/30, `pass_rate 0.9`**, latency p50 17.7 s, p95 48.8 s, max 77.6 s |
| 3 art 08 query | 30 rows → `08_agent_answers.md` (fetched base64-encoded: the Hindi answer breaks CoCo's Windows tool bridge in plain text) |
| 4 art 07 helper | used a **fresh** call instead (Q02, CR-007 form, 12.4 s, 4,055 bytes), because `EVAL_RESULTS.RESPONSE` is a parsed VARIANT with re-sorted keys. The fresh text is written byte for byte |
| 5 native evaluation | skipped (optional; budget) |

Every `SP_RUN_EVAL` call finished without aborting; each question is a row.

## Failures (3), and whose they are

| ID | Question | Cause | Owner |
|---|---|---|---|
| Q15 | Average reliability score by supplier region | Analyst's CTE left out `region` (`invalid identifier '__SUPPLIERS.REGION'`, twice). The agent's final answer uses a `SEMANTIC_VIEW` query that appears only in its text; the runner re-runs tool SQL only, so it could not check those numbers | CoCo (a verified query in the view) |
| Q17 | Parts below reorder point, per plant | The agent returned all 12 plants, zeros included. All 7 ground-truth rows match; the ground truth drops zero rows | Claude Code: accept extra zero rows, or make the ground truth return all plants |
| Q21 | Revenue, last 12 months | Analyst built `SUM(quantity_shipped * unit_price)` itself instead of `order_lines.total_revenue`, so it missed the SHIPPED/DELIVERED filter; its SQL can't be re-run as returned | CoCo (a verified query for revenue) |

## Other observations for C6c and C11

- **Tool names in responses:** besides the three spec tools, `tool_use` items include
  Snowflake's internal `system_execute_sql` and `system_agentic_semantic_context`, and
  `generic` appears as the type of `data_health`. `EXPECTED_TOOLS` matching on name or type
  handles this.
- **Response item types** (art 07): `thinking`, `tool_use`, `tool_result`, `text`, `table`,
  `text`, `suggested_queries`. Top-level keys: `content`, `metadata`, `role`,
  `schema_version`, `sequence_number`, `status`.
- **Q25** (list customer e-mails) was observed as `CLARIFY` because the refusal offers
  alternatives with a `?`. It passes (no SQL, no e-mail).
- **The agent's SQL runs as the calling role:** 82 generated queries ran as `FORGE_ADMIN` on
  `FORGE_WH`, not as the user's default role (ACCOUNTADMIN). This matters for the app's
  `FORGE_APP_ROLE`.
- Masked-value scan over all 30 answers (e-mail pattern, "credit limit", "payment term",
  "contract price", "unit cost"): **no match**.

## Verdict

**DONE.** The files are Claude Code's again. Please adopt the `20_sp_run_eval.sql` diff
(already in the file), fold Q30 into `10_questions.sql` and `99_run.sql`, and decide Q17.
