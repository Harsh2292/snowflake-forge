# NEXT — What To Do Right Now

> **Single source of truth for "what's next".** Read this, open the named card, execute it.
> Whichever agent finishes a card updates this file.

**Last updated**: 2026-09-29 (CR-006 accepted) · **Contract**: **v1.5** (CR-006 accepted by the user 2026-09-29) · **Branch**: `development`

> **DEADLINE (from the user): submission 4 Oct 2026. Everything done by end of 2 Oct.**
> Day 1 = 29 Sep · Day 2 = 30 Sep · Day 3 = 1 Oct · **2 Oct = buffer, fixes, rehearsal,
> the user records the video**. Both agents work to the same dates.

> **Replanned 2026-09-29 (user-approved).** Finish in **3 days, production-ready and
> deployed**. The core system (question → agent → semantic view → SQL → governed data →
> answer) must stay correct, fast and cheap from today's small data to billions of rows,
> and while the data keeps changing. The CoCo queue is in `.agents/tasks/COCO_TASKS.md`,
> which starts with the 9 core system rules. The post-hackathon work is in `docs/ROADMAP.md`.

---

## CoCo → `B08b` delivered; CR-006 accepted (contract v1.5) · next `B09`, then `B09a`

**B08b landed (2026-09-29):**
- `docs/DATA_SPEC.md`, the spec for all of Claude Code's SQL
- **CR-006 ACCEPTED** by the user; applied in `docs/CONTRACT.md` as **v1.5**
- 7 reference files in `docs/references/`
- card: `.agents/tasks/coco/B08b_data_spec.md`

The gate needs:
1. ~~the user to approve CR-006~~ ✅ accepted 2026-09-29
2. Claude Code to confirm in HANDOFF that the spec is implementable

Then **B09** (semantic view v2) and **B09a** (generator + name search) on today's data.
**B08c** starts when C08 is READY.

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

## Claude Code → C08 ✅ READY (handoff lock) · C09 ✅ · next: `C10` (data-quality SQL + `SP_DATA_HEALTH`), then `C11`

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

Already done: C01–C04, C07, C6a, C09 part A (`pytest -q` 250 passed, `pytest -m ui` 20 passed).

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
| B08b | Data spec v2 + context pack + CR-006 (Day 1) | 📝 delivered; CR-006 ✅ accepted (v1.5); gate: Claude Code's confirmation |
| B08c | Run C08 + `CONFORMED` cleansing layer + regenerate view → art 03, 04 again (Day 2) | 🔒 needs C08 |
| B09 | Semantic view v2: every business column, extra metrics, AI instructions, verified queries → art 05, 06, 09 (build Day 1, capture Day 2) | ⬜ NEXT |
| B09a | Metadata-driven view generator + name search (Day 1) | ⬜ |
| B10 | Cortex Agent (Analyst + chart + data-health tool); run C11 → art 07, 08 (Day 2) | ⬜ |
| B12 | Run C10 (DMFs + `SP_DATA_HEALTH`) → art 10 (Day 2) | 🔒 needs C10 |
| B08m | Move to the event account: trial move Day 2, cutover end of Day 3 | 🔒 needs the user's new account + connection |
| B13 | Run C12 scale harness on a clone → art 12 (Day 3, old account) | 🔒 needs C12 |
| B14 | Run C13 live tests + security review → art 11 (2 Oct, new account) | 🔒 needs C13 |
| B15 | Cost controls + deploy (2 Oct, new account) | ⬜ |
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
| C6a | Reconcile governed layer | ✅ art 03/04: 0 mismatches (re-check after B08c) |
| C09 | App production pass (Day 1–2) | ✅ 29 Sep: part A + part B (contract v1.5: time rule, as-of date, data health, MCP removed); 285 + 20 UI tests |
| C08 | Realistic data generator in `data_gen/` (Day 1, critical path) | ✅ READY 29 Sep: in the handoff lock for CoCo (dry run first); spec confirmed implementable |
| C10 | Data-quality SQL + `SP_DATA_HEALTH` in `quality/` (Day 1–2) | ⬜ unblocked (DATA_SPEC §7.2) |
| C11 | Evaluation set + runner in `eval/` (Day 1–2) | ⬜ unblocked (DATA_SPEC §7.3) |
| C6b | Reconcile semantic layer (Day 2) | 🔒 wait for the re-captured art 05/06 (B09) |
| C12 | Scale-test harness in `tests/scale/` (Day 2) | ⬜ unblocked (DATA_SPEC §7.4) |
| C6c | Agent parser + proof grid; flip to live (Day 2) | 🔒 needs art 07–09 |
| C13 | Live-test refresh for the audit (Day 2–3) | 🔒 needs CR-006 |
| C05 | Demo script, talking points, README, core-scalability doc (Day 3) | 📝 card written; scheduled for Day 3 |
| C14 | Stretch: parallel multi-part router + KPI shortcut (Day 3) | ⬜ only if time is left |

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
