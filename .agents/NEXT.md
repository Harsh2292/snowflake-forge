# NEXT — What To Do Right Now

> **Single source of truth for "what's next".** Read this, open the named card, execute it.
> Whichever agent finishes a card updates this file.

**Last updated**: 2026-09-30 evening (CoCo: C16 run done, B09a done, **B08m done: everything now runs in the new account `QURFOQP-XU04029`**; next: secrets + B15a, then C17, B14, B15, see "CoCo → NEXT SESSION STARTS HERE") · **Contract**: **v1.6** (CR-007 accepted and applied 2026-09-30) · **Branch**: `development`

> **DEADLINE (from the user): submission 4 Oct 2026. Everything done by end of 2 Oct.**
> Day 1 = 29 Sep · Day 2 = 30 Sep · Day 3 = 1 Oct · **2 Oct = buffer, fixes, rehearsal,
> the user records the video**. Both agents work to the same dates.

> **Replanned 2026-09-29 (user-approved).** Finish in **3 days, production-ready and
> deployed**. The core system (question → agent → semantic view → SQL → governed data →
> answer) must stay correct, fast and cheap from today's small data to billions of rows,
> and while the data keeps changing. The CoCo queue is in `.agents/tasks/COCO_TASKS.md`,
> which starts with the 9 core system rules. The post-hackathon work is in `docs/ROADMAP.md`.

---

## ⏸ Session closed 2026-09-30: moving to a new Snowflake account

**The user (30 Sep, end of day):** the whole Snowflake setup moves to a **new account with the
full $400 credits**. The codebase and every object stay the same; only the account changes.
All Claude Code work is paused until the move is done.

**Claude Code's state at close:** every card that can be built before the move is done
(C14 + C14b included). `pytest -q` 725 passed, 0 failed; `pytest -m ui` 25/26 (the known
drawer flake). No app code change is needed for the move.

**The move (CoCo's B08m; the user's steps are in `deploy/RUNBOOK.md` §1–§3 and §7):**
1. CoCo replays the repo in the new account: `sql/`, `semantic/`, `agent/`, `quality/`, `eval/`,
   `sql/05_app_access/` 01 + 02, and `data_gen/` with the same seed `20260929` and the same
   fixed END_DATE `'2026-09-30'`.
2. The user makes a new key pair (§1). CoCo sets it on `FORGE_APP_SVC` (§2), and the
   Community Cloud secrets get the new account identifier (§3 / §7). Nothing about the
   account goes in the repo.
3. CoCo re-captures the artifacts (05, 07, 08, 09, 10) from the new account. Then
   Claude Code runs `tests/tools/build_captured.py` and `pytest -q`. If `semantic/` changed,
   Claude Code also runs `tests/tools/build_vocabulary.py`.

**Claude Code, after the move, in this order:**
1. **Re-sync:** re-capture → `build_captured.py` → `pytest -q`. Pick up any RETURNED rows in
   HANDOFF's lock table (C12, C13, the C16 re-run).
2. **C17 part B:** the nightly day-append, deferred by the user until after the move.
3. **C05:** demo script, talking points, README, core-scalability doc, with the new account's
   final numbers. Include C14/C14b as a production pattern: fixed paths for known intents,
   the LLM for everything else.
4. **Live checks** (B15a / rehearsal): Ask answers live; a suggested question answers
   instantly (~1–2 s); "Ask is paused" when the budget stops the agent.

---

## ▶ Resume here (Claude Code, end of session 2026-09-30)

**Done today:** C15, C6b, C6c, C16 (in the lock), C13 (in the lock), C17 part A (the
generator range-join fix, in the lock). `pytest -q` 516 passed, 0 failed; `pytest -m ui` 22/22.

**✅ C14b done (30 Sep, the user asked for a "more dynamic" router):** card
`C14b_dynamic_router.md`. The instant path's words now come from the semantic view itself
(`app/utils/vocabulary.json`, built from `semantic/01` by `tests/tools/build_vocabulary.py`),
so every contract pairing is reachable. It also answers one-value questions ("fill rate in
APAC", "OTD at <plant>": that row of the breakdown, no new SQL) and forgives small typos.
No CoCo work.
- `pytest -q` 725 passed, 0 failed; `pytest -m ui` 25/26
- **Known flake:** `test_problem_column_drawer_filters_and_closes` sometimes times out on a
  click (element outside the viewport) in a full `-m ui` run. It passed 3 of 3 alone and
  failed twice today in different themes. Watch it; if it keeps failing, scroll the button
  into view first
- **If `semantic/01` changes:** run `tests/tools/build_vocabulary.py`
  (`test_vocabulary_json_is_exactly_the_builder_output` fails until then)

**✅ C14 done (30 Sep, offline gate):** `pytest -q` 619 passed, 0 failed; `pytest -m ui` 24/24.
- **Instant answers:** the 8 suggested questions (and variants like "OTD by carrier",
  "which regions have the best fill rate") answer from the semantic view with the verified
  queries' own SQL, no agent call, no limit counted. The card says "Instant answer ·
  governed semantic view" and the time taken
- **Multi-part questions** split on clear boundaries; agent parts run in parallel
- **"Ask is paused"** (CoCo's ask): a note instead of the fallback banner; agent calls pause
  for 10 min; instant answers keep working
- Off switch: `[forge] shortcut = false` in secrets. Snowpark pin now ≥ 1.24 (thread-safe
  sessions)
- **Live check left:** at B15a / rehearsal, a suggested question answers in ~1–2 s

**Next task: C05** (demo + docs, after the account switch and the final numbers), then C17
part B (the day-append, deferred by the user until after the switch).

**Waiting on CoCo:**
- run C16 (quality/eval) → re-capture art 10 → run `tests/tools/build_captured.py`
- ✅ C17 part A proved (Session 34: identical checksums, 132.8 s at SF 1)
- B14 live audit (`pytest -m live`)
- B15a once the user's key and Community Cloud app exist

**Waiting on the user:** the public-link steps (the table below).

## 👤 The user's actions: the public link (from C15, 30 Sep)

C15 is built and passes offline. The public link goes live once these are done. Every step
is in **`deploy/RUNBOOK.md`**; the § numbers point there.

| # | Action | Where | Status |
|---|---|---|---|
| 1 | Generate the key pair **outside the repo**, and give the public key (`rsa_key.pub` body) to CoCo | RUNBOOK §1 | ⬜ |
| 2 | CoCo runs `sql/05_app_access/` (user `FORGE_APP_SVC`, role `FORGE_APP_ROLE`) with that key | RUNBOOK §2, CoCo B15a | 🔄 role, user and cost caps done 30 Sep; only the key is left |
| 3 | Create the Community Cloud app: entrypoint `app/streamlit_app.py`, **Python 3.11**, a readable subdomain, paste the secrets (the shape is in `.streamlit/secrets.toml.example`) | RUNBOOK §3 | ⬜ |
| 4 | Check it in a private window: tag says **Live**, no "Live connection paused" banner, Ask answers | RUNBOOK §4 (B15a gate) | ⬜ |
| 5 | After merging to `main`: add the repo variable `PUBLIC_APP_URL`, then run **keep awake** once from Actions | RUNBOOK §5 | ⬜ |
| 6 | Commit and push. Note: the move `app/environment.yml` → `deploy/sis/environment.yml` is **already staged** (`git mv`) | git | ⬜ |
| 7 | Judging days (3–4 Oct): run the checklist | RUNBOOK §9 | ⬜ |

**Suggested to CoCo (30 Sep, agent speed; HANDOFF "Suggestion for CoCo"):** drop the SQL block from the agent's response rule, remove `data_to_chart`, optionally test Claude Haiku 4.5, add verified queries; measure with the C11 eval (`b10-fast` vs `b10-baseline`).

**Asked of CoCo for `sql/05_app_access/`** (detail: HANDOFF, "✅ C15 done"):
- **Missing:** grant `SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER` (the Data health screen),
  and check the screen gets rows as FORGE_APP_ROLE
- confirm `USAGE` on the database and on the `SEMANTIC`, `GOVERNED`, `TMS_SOURCE` and
  `ERP_SOURCE` schemas
- confirm whether querying the semantic view needs `SELECT` on its base objects

**Test state (updated after C16, 30 Sep): `pytest -q` 495 passed, 0 failed; `pytest -m ui` 22/22.** Earlier, after C15: `pytest -q` gives 437 passed and 5 failed. None
are in C15's files:
- 2 were **C6b**'s job: ✅ fixed 30 Sep (451 passed after C6b)
- 3 come from CoCo's run fixes at B10 / B12 (`C10_run.md`, `C11_run.md`):
  - `quality/00_setup.sql`: FRESHNESS now uses `ON ()` (no NTZ signature), and the fix's
    comment has a `;`
  - `eval/20_sp_run_eval.sql`: the agent call was rewritten for CR-007

  My tests still expect the old text. They're fixed in the C10 / C11 follow-up card.

`pytest -m ui` 20/20. One run in three timed out on the Ask card's dialog (5 s); it's
treated as timing flakiness and watched.

**⚠ CR-007 (proposed by CoCo, 30 Sep): the app's live Ask call fails as written.**
`DATA_AGENT_RUN` needs the whole request as one constant, so the public link's Ask would
fall back until the app binds the request JSON instead. ✅ **Accepted by the user (30 Sep)**
and recorded in contract §11. CoCo updates the §5.3 body (v1.6); Claude Code changes the app
in C6c, before B15a.

**⚠ The user, 30 Sep (late):** "if it's too much don't do it right now, we have to change
accounts as soon as development completes". So the remaining order puts the account switch
first:
1. ✅ **Generator range-join fix** (C17 part A) READY 30 Sep, in the lock: 5 joins fixed, the
   same rows. CoCo proves it (identical checksums) before the switch
2. ✅ **C14** (shortcut + router + "Ask is paused") done 30 Sep
3. **C05** (demo + docs, after the final numbers)
4. **C17 day-append deferred** until after the switch. It catches up missed days by itself.
   Until it runs, daily data reads WARN ~36 h after the load and FAIL after 72 h.

**Claude Code's queue (the order approved by the user, 30 Sep; CoCo's freshness asks added the same day):**
1. ✅ **C6b** done (30 Sep): every saved number = the last captured Snowflake result
2. ✅ **C6c** done (30 Sep): Ask works live (CR-007), the parser matches the real agent, and the
   agent's suggestions show. B15a's Ask check can run
3. ✅ **C16** READY (30 Sep, in the handoff lock): freshness fix 1 (REFERENCE), Q30 + 4th batch,
   Q17, E04 0.95×, CoCo's run fixes adopted. `pytest -q` 0 failures. **CoCo: re-run + re-capture art 10**
4. **C17: CoCo's "freshness fix 2"**: **CoCo chose A, build it** (30 Sep; option B was tested
   on a clone and rejected: ~1.5 h a night, wrong joins during refresh, history re-drawn;
   `runs/B12a_reload_test.md`). Card `C17_nightly_day_append.md`, waiting for the user's
   approval. CoCo's extra asks:
   - **no range join:** use `LATERAL FLATTEN(ARRAY_GENERATE_RANGE(1, cnt + 1))`
   - **the same fix in `data_gen/10_sp_generate_data.sql`** (lines 122, 347, 416, 508). The
     move to the new account regenerates everything with it, and CoCo's clone test hit a
     ~9 min/year Cartesian plan
   - never use `CURRENT_DATE()` inside: the account is on LA time, and the task passes the
     UTC date
   - clone tests must re-create the clone's dynamic tables

   **All of this goes in the handoff lock by the end of 1 Oct.**
5. ✅ **C13** READY (30 Sep): `pytest -m live` = 148 checks with a per-contract-section summary; guide `tests/README.md`; CoCo runs it at B14 (and B15a as FORGE_APP_ROLE)
6. **C05**: demo script, talking points, README, core-scalability doc (1–2 Oct)
7. ✅ **C14** done 30 Sep: KPI shortcut (~12 s → instant for known questions) + parallel multi-part router + "Ask is paused". Live check at B15a

**Deadline from CoCo (user-approved): fixes 1 and 2 in the handoff lock by the end of
1 Oct**, so the nightly job has run before the recording.

**C15 access questions: answered by CoCo (30 Sep).** `sql/05_app_access/` ran:
- FORGE_APP_ROLE has everything, incl. the DQ viewer and schema USAGE; Data health is visible
  as that role
- the semantic view needs no grant on its base tables, but the DOI subquery needs SELECT on
  `V_INVENTORY`, which is granted
- cost caps: warehouse 5 credits/day; Cortex 25 credits/month for the app user, which turns
  Ask off at 100%
- contract v1.6 (CR-007) applied

**New small ask from CoCo:** when the Cortex budget switches Ask off, the agent call fails
with "does not exist or not authorized". Show a friendly **"Ask is paused"** message instead
of the fallback banner. ✅ Built in C14 (30 Sep).

---

## CoCo → NEXT SESSION STARTS HERE (updated 30 Sep evening)

**Where things stand (30 Sep evening):**
- **C16 run DONE** (B12a part 1): self-checks 93/93, `SP_DATA_HEALTH('ALL')` OK with 5 × REFERENCE,
  art 10 re-captured, `captured.json` rebuilt (`runs/C16_run.md`).
- **B09a (reduced) done:** 2 new verified queries (Q15, Q21; a third was removed at B08m) + the
  agent without `data_to_chart` / SQL block + a no-chart instruction.
  Card `.agents/tasks/coco/B09a_verified_queries_speed.md`.
- **B08m DONE (30 Sep evening):** the whole build now lives in the new account
  `QURFOQP-XU04029`, replayed from the repo with no hand fix. The data is byte-identical to the
  old account, every compared number matches, self-checks 93/93, data health OK, eval `b10-v2`
  **28/30, p50 12.3 s** (baseline 27/30, 17.7 s). Art 08 and art 10 re-captured there.
  Report `docs/artifacts/runs/B08m_run.md`; card `.agents/tasks/coco/B08m_account_switch.md`
  ("After the gate" = what's left).
- The old account (`tyduokn-gf25237`) is **no longer used** (the user's decision). Its semantic
  view still has the removed 15th verified query; leave it.
- **Extra verification done the same night** (`B08m_run.md`, "Extra verification"): 122 objects
  and all grants identical (new account the correct side of 2 old-account drifts); **the public
  app's 71 queries + one agent call all work as `FORGE_APP_ROLE`**, same numbers as FORGE_ADMIN.
- **`pytest -m live`: 148 passed, 0 failed** in the new account (1 Oct ~05:20 UTC, the first live
  run ever; `B08m_run.md` §4). It needs the bash tool's **`dangerously_disable_sandbox`** (the
  sandbox blocks the browser-OAuth redirect) and the user approving the sign-in within ~2 min.
- **B15a Snowflake side DONE (1 Oct):** `FORGE_APP_SVC` has the user's public key
  (fingerprint `SHA256:iiLw9woP…Fyv0=`, matches the private key); **the live suite as
  `FORGE_APP_SVC` / `FORGE_APP_ROLE` (key pair, no browser): 148 passed, 0 failed.** Left for
  B15a: the user creates the Community Cloud app with the secrets below, then the RUNBOOK §4
  checks on the public link.

**Order for the next session** (all in the new account `QURFOQP-XU04029`; its connection should
be the active one, and pass `connection='QURFOQP-XU04029'` on every SQL call anyway):
1. Tell the user the Community Cloud secrets values (B08m card, "After the gate").
2. **B15a:** key ✅ and live suite as the app role ✅ (1 Oct). Left: once the user's Community
   Cloud app exists, the RUNBOOK §4 checks on the public link (Ask included).
3. **B12a part 2:** Claude Code's C17 day-append when it's in the lock (**critical path**: the
   daily tables read WARN from 1 Oct ~17:00 UTC), then the nightly task with the UTC date.
4. **B14:** `pytest -m live` as FORGE_ADMIN + security review → art 11.
5. **B13** (optional, scale proof) on a clone in the new account, if the budget allows.
6. **B15:** cost check + final checks on the public link.

Close out each card: NEXT.md, HANDOFF (CoCo section only), SESSION_LOG, COCO_TASKS,
`.agents/tasks/README.md`, and `docs/artifacts/runs/<card>_run.md` for each Claude Code file run.

**Open for the user:** the Community Cloud app, with its secrets pointing at the new account
(the key is set: 1 Oct).

---

## CoCo → earlier plan (end of 30 Sep, superseded by the section above)

**Done:** 14 of 21 CoCo cards (B01–B09, B07b, B08b, B08c, B10, B12). B15a's Snowflake side is
done too.

**Order for the next session** (the user: switch accounts as soon as development completes):
1. **Run C16 (freshness fix 1), part of B12a.** In the handoff lock, READY. As `FORGE_ADMIN` on
   `FORGE_WH`:
   - re-run `quality/30_sp_data_health.sql` and `40_sp_dq_self_checks.sql`
   - `CALL SUPPLY_CHAIN_FORGE.OPS.SP_DQ_SELF_CHECKS('SUPPLY_CHAIN_FORGE')`: expect 93 rows, all
     TRUE
   - `CALL SEMANTIC.SP_DATA_HEALTH('ALL')`: the 5 reference entities read `REFERENCE`, and ALL
     reads OK/WARN
   - **re-capture art 10**, then run `tests/tools/build_captured.py`
   - write `runs/C16_run.md` and set the lock row to DONE
   - optional: the eval re-run (`eval/10` + `99`, label `b10-v2`, 30 questions, 4 batches)
2. **B09a, reduced (proposed to the user; awaiting yes/no):** skip the generator; add verified
   queries for Q15 (reliability by supplier region) and Q21 (revenue via `total_revenue`). Also
   consider Claude Code's agent-speed suggestion:
   - drop the SQL block from the response rule
   - remove `data_to_chart`
   - try Haiku

   Measure with `SP_RUN_EVAL('b10-fast', …)` against `b10-baseline`.
3. **B15a (public link).** Waiting on the user's public key (RUNBOOK §1) + Community Cloud app
   (§3). Then:
   - `ALTER USER FORGE_APP_SVC SET RSA_PUBLIC_KEY = '…'`
   - the RUNBOOK §4 checks, Ask included (C6c is done)
   - the C13 live tests as FORGE_APP_ROLE
4. **B13 (scale proof, C12 READY)** in the old account, if it fits before the switch; otherwise
   after.
5. **B08m (account switch).** The user must claim the new account (by 3 Oct UTC) and add a
   VS Code connection. Replay the repo, including:
   - `sql/05_app_access/` 01 + 02
   - the generator (the range-join fix is ✅ proven and deployed 30 Sep: identical checksums,
     SF 1 in 133 s; `runs/C17a_run.md`)
6. **After the switch:**
   - B12a part 2 (run C17 day-append + the nightly task; Claude Code deferred C17 until after
     the switch)
   - B14 (C13 `pytest -m live`, READY)
   - B15 (final deploy)

**Open for the user:**
- the public key
- claim the new account
- yes/no on dropping B09a's generator

---

## CoCo → `B10` ✅ + `B12` ✅ done (30 Sep, gates 6/6 and 6/6)

**B10 + B12 landed (2026-09-30).** Cards `.agents/tasks/coco/B10_agent.md` and `B12_dmfs.md`;
run reports `docs/artifacts/runs/C10_run.md` and `C11_run.md`.
- **Agent** `SEMANTIC.SUPPLY_CHAIN_AGENT` (`agent/01_agent.sql`): Analyst on the view, chart,
  and `data_health` (`SP_DATA_HEALTH`).
  - C11 baseline **27/30 = 90%**: canonical 8/8; refusals, clarifying questions, the
    cross-grain Q30 and data health all pass
  - latency p50 17.7 s, p95 48.8 s
  - no masked value leaked
- **DMFs:** 77 attached, all producing results, on `TRIGGER_ON_CHANGES`. Self-checks 90/91.
- **Art 07, 08 and 10 captured. C6c is unblocked.**
- **⚠ CR-007 (proposed, filed with the user's approval):** the contract §5.3 agent call fails
  live (the request must be a constant). Fix: bind the whole request JSON as one `?`. The
  app's `forge_data.build_agent_sql` needs this change (Claude Code). The user accepts or
  rejects the CR.

**Next:**
- B09a: the generator must reproduce the v2 view, plus verified queries for supplier
  reliability by region (Q15) and revenue (Q21)
- **B12a** (user-approved 30 Sep): run Claude Code's two freshness fixes and schedule the
  nightly day-append, **before the 2 Oct recording**. Without them, data health reads FAIL
  on camera.
- B15a: **Snowflake side done 30 Sep** (card `B15a_public_link_trial.md`). **User:** send the
  *public* key body (`rsa_key.pub`, RUNBOOK step 1), then create the Community Cloud app
  (step 3). The Ask check waits for Claude Code's C6c.
- B08m trial move: when the user's new account connection exists

**Claude Code's queue from CoCo (HANDOFF, CoCo section):**
1. CR-007 `ask_agent` ✅ done (C6c)
2. freshness fix 1 ✅ in the lock (C16; CoCo runs it, re-captures art 10)
3. freshness fix 2: **C17 day-append, confirmed 30 Sep** (option A; the nightly full reload
   was tested on a clone and rejected, `runs/B12a_reload_test.md`). Includes the range-join fix
   in `data_gen/10` for the cutover.

Fix 2 goes in the lock by the end of 1 Oct.

> **Account switch (user-approved 2026-09-29; plan in `COCO.md`, "Account switch plan").**
> The organisers issued a new event account ($400, 30 days; **claim by 3 Oct UTC**).
> - Build in the old account until the **end of 1 Oct**, including B13.
> - **B08m trial move 30 Sep**; **cutover at the end of 1 Oct**.
> - **2 Oct (B14, B15 deploy, final artifacts) runs in the new account.**
> - **User action today:** claim the account ("AI Data Cloud" flow, same email, Enterprise
>   edition) and add a VS Code connection.
> - **Both agents:** everything must be a re-runnable repo script, and nothing may name the
>   account.

---

## Claude Code → C08 ✅ DONE · C10 ✅ READY · C11 ✅ READY (handoff lock) · C09 ✅ · C12 ✅ READY · **C15 ✅ DONE** (30 Sep, Community Cloud readiness; CoCo's B15a can start) · next: **`C6b`** (B09 done: art 05/06/09 landed), then C11 add-on + `C13`

Queue and full detail: `.agents/tasks/CLAUDE_TASKS.md` (replanned 2026-09-29). Claude
Code **writes Snowflake SQL, CoCo runs it** (the handoff lock). Write each card before
building it.
1. **C09** app production pass: **part A done** (29 Sep); part B (as-of date,
   `SP_DATA_HEALTH` display, MCP removal) when the spec and CR-006 land
2. **C08** realistic data generator in `data_gen/`: as soon as `docs/DATA_SPEC.md` lands;
   **READY by the end of Day 1**
3. **C10** data-quality SQL + `SP_DATA_HEALTH` in `quality/` (Day 1–2)
4. **C11** evaluation set + runner in `eval/` (Day 1–2)
5. **C6b** after the re-captured art 05/06 (Day 2); **C12** scale harness (Day 2)
6. **C6c** after art 07–09 (Day 2); **C13** live-test refresh (Day 2–3)
7. **C05** demo, README, core-scalability doc (Day 3); **C14** stretch router
8. Day 3: rehearsal; the user records the video.

Already done: C01–C04, C07, C6a, C09; C08 and C10 READY in the handoff lock (`pytest -q` 333 passed, `pytest -m ui` 20 passed).

---

## The 3-day sequence

```
Day 1  CoCo   B08b spec + CR-006 + references ──┐
       CoCo   B09 semantic view v2 → B09a generator + name search
       Claude C09 app pass │ C08 generator ◄────┘ (critical) │ C10 quality SQL │ C11 eval set
Day 2  CoCo   B08c run C08 + CONFORMED + regenerate view  ◄── C08
       CoCo   B09 captures art 05/06/09 ──────────────► Claude C6b
       CoCo   B12 run C10 → art 10 ; B10 agent, run C11 → art 07/08 ──► Claude C6c
       Claude C12 scale harness ; C13 live-test refresh
Day 3  CoCo   B13 run C12 on a clone → art 12
       CoCo   B14 run C13 (pytest -m live) + security → art 11
       CoCo   B15 cost controls + deploy             Claude C05 docs, fixes, C14 stretch
```

Critical path: **B08b → C08 → B08c → regenerate → B09 captures → B10 → B15**.

### Who does what

| CoCo | Claude Code |
|------|-------------|
| Specs, contract, core design (semantic view, generator, `CONFORMED`, agent) | Every file that can be written offline, **including Snowflake SQL** |
| Runs all of Claude Code's SQL and writes the run reports | App, tests, deploy script, docs, demo |
| All artifact captures | Data generator, data-quality SQL, data-health tool, eval set, scale harness |
| Deploy, cost controls, security review | Agent response parser, proof grid, stretch router |

No-collision rules (one owner per file; the handoff lock; interfaces fixed first):
`.agents/tasks/COCO_TASKS.md` § "Working with Claude Code".

---

## Progress

### CoCo

| Card | Title | Status |
|------|-------|--------|
| B01 | Database, schemas, warehouse | ✅ |
| B02 | Roles and grants | ✅ |
| B03 | Source tables (9) | ✅ |
| B04 | Data generation (v1, small and clean) | ✅ |
| B05 | Distribution verification | ✅ |
| B06 | Tags and masking policies | ✅ |
| B07 | Governed views (9) → art 03 | ✅ |
| B07b | Persona sample procedures (3) → art 04 | ✅ |
| B08 | Semantic view → art 05, 06 (+ `SP_METRICS_AS_*`) | ✅ |
| B08b | Data spec v2 + context pack + CR-006 (Day 1) | ✅ CR-006 accepted (v1.5); Claude Code confirmed the spec |
| B08c | Run C08 + `CONFORMED` cleansing layer → art 03, 04 again | ✅ 29 Sep, gate 7/7 (view regeneration moved to B09) |
| B09 | Semantic view v2: every business column, extra metrics, AI instructions, verified queries → art 05, 06, 09 | ✅ 29 Sep, gate 7/7 |
| B09a | Verified queries for the C11 misses + agent speed (reduced: no generator, no name search) | ✅ 30 Sep: 2 verified queries (14 in all) + agent without `data_to_chart`; `b10-v2` in the new account **28/30, p50 12.3 s** (card `B09a_verified_queries_speed.md`) |
| B10 | Cortex Agent (Analyst + chart + data-health tool); run C11 → art 07, 08 (Day 2) | ✅ 30 Sep, gate 6/6: 27/30 on C11; CR-007 proposed |
| B12 | Run C10 (DMFs + `SP_DATA_HEALTH`) → art 10 (Day 2) | ✅ 30 Sep, gate 6/6: 77 DMFs live, self-checks 90/91 |
| B12a | Freshness fixes: reference data + nightly day-append (Day 3) | 🔄 **Part 1 ✅ 30 Sep** (C16: 93/93, ALL OK, art 10 re-captured). Part 2 (C17 + nightly task) in the new account, when C17 is in the lock (critical: WARN from 1 Oct ~17:00 UTC) |
| B08m | Move to the event account (cutover now, user decision 30 Sep) | ✅ 30 Sep evening: replayed with no hand fix, data byte-identical, numbers match, 93/93, eval 28/30. **All work continues in `QURFOQP-XU04029`** (`runs/B08m_run.md`) |
| B13 | Run C12 scale harness on a clone → art 12 (Day 3, old account) | ⬜ C12 READY; clone tests must re-create the clone's DTs (they read the original database) |
| B14 | Run C13 live tests + security review → art 11 (2 Oct, new account) | ⬜ C13 READY (`pytest -m live`, 148 checks) |
| B15a | Public live link trial on Streamlit Community Cloud (Day 2, old account; ADR-009) | 🔄 30 Sep: Snowflake side done (`sql/05_app_access/` 01 + 02: `FORGE_APP_ROLE`, `FORGE_APP_SVC`, 5-credit/day monitor, 25-credit Cortex budget with auto-stop of Ask). Waits for the user's public key + Community Cloud app. C6c is done, so the Ask check can run too |
| B15 | Cost controls + deploy (2 Oct, new account): the Community Cloud link is the submitted one | ⬜ |
| — | Stretch: governed splitter for the router, lineage trace | ⬜ only if time is left |

Removed on 2026-09-29: B07c and the old B14 (MCP dropped), B11 (merged into B09), B16
(merged into B10/B13), B17 (merged into B14).

### Claude Code

| Card | Title | Status |
|------|-------|--------|
| C01 | API reference library | ✅ |
| C02 | Data access layer (mock-backed) | ✅ |
| C03 | Streamlit app (guided story + Explore), Revision 2 | ✅ |
| C04 | Test suite | ✅ |
| C07 | CI tests on GitHub + one-command deploy script | ✅ |
| C6a | Reconcile governed layer | ✅ re-checked after B08c (29 Sep): art 03 still matches; practice rows re-synced to the new art 04 |
| C09 | App production pass (Day 1–2) | ✅ 29 Sep: part A + part B (contract v1.5: time rule, as-of date, data health, MCP removed); 285 + 20 UI tests |
| C08 | Realistic data generator in `data_gen/` (Day 1, critical path) | ✅ DONE 29 Sep: run by CoCo at B08c (3 small fixes, `C08_run.md`) |
| C10 | Data-quality SQL + `SP_DATA_HEALTH` in `quality/` (Day 1–2) | ✅ DONE 30 Sep: run by CoCo at B12 (1 fix, `C10_run.md`); 2 suggestions (E04 tolerance, master-data freshness) |
| C11 | Evaluation set + runner in `eval/` (Day 1–2) | ✅ DONE 30 Sep: run by CoCo at B10 (1 fix, Q30 added, `C11_run.md`); to fold in: Q30, the 4th batch, Q17's ground truth |
| C6b | Reconcile semantic layer (Day 2) | ✅ DONE 30 Sep: saved data = the last capture (art 05/09/10 + §8 naive) via `app/utils/captured.json`; art 05/06/09 + §4/§10 reconcile (11 tests); Data health view fixed for 77 real checks |
| C12 | Scale-test harness in `tests/scale/` (Day 2) | ✅ READY 29 Sep: in the handoff lock for CoCo's B13 (`tests/scale/99_run.sql`); offline gate green |
| C6c | Ask works live: CR-007 + parser vs the real agent (Day 2) | ✅ DONE 30 Sep (offline gate): CR-007 call; parser built on art 07/08 (clean answer, one table, tool names, agent suggestions); art 07 + art 10 replayed through the live path. Live gate = B15a |
| C13 | Live-test refresh for the audit (Day 2–3) | ✅ READY 30 Sep: 148 live checks + per-section summary; in the lock for B14 |
| C05 | Demo script, talking points, README, core-scalability doc (Day 3) | 📝 card written; scheduled for Day 3. **Adds (user decision, 29 Sep): the public prototype link on Streamlit Community Cloud**: a secrets connection, Ask limits, `deploy/RUNBOOK.md`; CoCo provides a key-pair service user, role and capped warehouse |
| C15 | Community Cloud readiness: the public link, live on Snowflake (Day 2, ADR-009) | ✅ DONE 30 Sep (offline gate): secrets session factory (key pair from PEM), live by default, fallback banner, Ask rate limiter + caps + answer cache, no-secrets CI check, keep-awake job, `deploy/RUNBOOK.md`. Live gate = CoCo's B15a |
| C14 | Parallel multi-part router + KPI shortcut + "Ask is paused" | ✅ DONE 30 Sep (offline gate): `utils/router.py`; 8 suggested questions on the verified queries' SQL with no agent call; 0 false shortcuts on art 08's 30; parallel agent parts; paused note. Live gate = B15a (~1–2 s) |

Legend: ⬜ todo · 📝 planned (card written) · 🔄 in progress · ✅ done · 🔒 waiting on artifact · ⏸ deferred

---

## Credentials — Resolved, Nothing Needed From You

**Decision: artifact handoff.** Claude Code needs no Snowflake credentials.

```
CoCo runs live query  →  commits real output to docs/artifacts/  →  Claude verifies
Claude writes data_gen/ SQL  →  CoCo reviews and runs it  →  CoCo captures the results
```

Why this was necessary:
- `connections.toml` uses `OAUTH_AUTHORIZATION_CODE` — browser-based, nothing reusable
  non-interactively
- `snow` CLI is not installed
- No secrets stored

**Nothing is required from the user.** If artifacts prove insufficient, Claude Code raises
it in `.agents/HANDOFF.md` under `## Blocked`.

---

## Rules

1. One card at a time. Finish it, pass its gate, then update this file.
2. A card is done when its **Gate** passes — not when the code runs.
3. **Task Planning & Card Rule**: Before implementing any task, enter plan mode, plan the task, author its markdown task card file (`.agents/tasks/coco/Bxx_...md` or `.agents/tasks/claude/Cxx_...md`), get user confirmation, and only then proceed with implementation.
4. `docs/CONTRACT.md` is binding. Deviations → Change Request in §11 + tell the user.
5. Append to `docs/SESSION_LOG.md` when you stop working.
6. Do not commit or push. The user does that.
7. Every card keeps the 9 core system rules at the top of `.agents/tasks/COCO_TASKS.md`.
8. One owner per file. Claude Code's SQL goes through the handoff lock ("Ready for CoCo to
   run" in `.agents/HANDOFF.md`).
