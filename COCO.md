# COCO.md — CoCo Agent Entry Point

> **Read this file at the start of every CoCo session.**
>
> Then read, in this order:
> 1. **`.agents/NEXT.md`** — names the exact task card to open. Start here.
> 2. `docs/CONTRACT.md` — the frozen interface. Binding. Do not deviate.
> 3. The task card named in `NEXT.md` — self-contained, has its own gate
>
> Reference when needed: `docs/HLD.md` (architecture), `docs/LLD.md` (exact schemas),
> `docs/GAPS_RESOLVED.md` (resolved design questions), `docs/SESSION_LOG.md` (history).

## How Work Is Organised

Work is broken into **task cards** — one per build step, each executable in about one
session, each carrying its own gate.

```
.agents/NEXT.md                 ← what to do right now
.agents/tasks/coco/B01…B15.md   ← your cards (replanned 2026-09-29: see COCO_TASKS.md)
.agents/tasks/claude/C01…C06.md ← Claude Code's cards
```

Execute one card at a time. A card is done when its **Gate** passes, not when the SQL
runs. Then update `NEXT.md`, `HANDOFF.md`, and `SESSION_LOG.md` as the card instructs.

**Task Card & Planning Rule**: When moving to the next task, first enter plan mode, plan the task, author the task card markdown file (`.agents/tasks/coco/Bxx_...md`), get user confirmation, and only then proceed with implementation. **Waived by the user from 30 Sep** for the cards already specified in `.agents/tasks/COCO_TASKS.md`: write or update the card and build it straight away. Stop and ask only for a contract change (a CR), anything destructive, or a spending limit.

## The Contract Is Binding

`docs/CONTRACT.md` is frozen (now **v1.6**, CR-007 applied 30 Sep). Claude Code is building the entire application
against it **in parallel, right now**, using a mock data layer. Every metric identifier,
dimension identifier, governed view column name, role name, and FQN you create must
match it exactly.

If reality forces a deviation, append a Change Request to `CONTRACT.md` §11 and tell the
user. **Never silently rename anything** — that is the one action that breaks the other
agent's work irrecoverably.

Build step **B13** is a full conformance audit against the contract. Do not skip it.

## Auto-Mode Rules

- **Auto-mode is ON** — execute commands without asking for confirmation each time.
- **DO NOT** create git commits, push, or create PRs automatically.
- Everything else (SQL execution, file writes, deployments) — just do it.

## Working Branch

`development` — all dev happens here. Merge to `main` only after testing.

## Project: Supply Chain Forge

**Hackathon**: Snowflake CoCo CLI Hackathon (GCC Edition) — Hack2Skill
**Problem Statement**: Supply Chain Ontology and Governed Conversational Analytics

### What We're Building

A governed "single source of truth" for supply chain data in Snowflake:

1. **Supply Chain Ontology** — Entity-relationship model: Supplier → Part → Plant → Shipment → Order → Customer
2. **Semantic Views** — Business meaning encoded as semantic views with canonical metrics (OTD, Fill Rate, DOI, Landed Cost)
3. **Cortex Agent** — Natural language analytics grounded in the semantic views
4. **Cross-Persona Proof** — Same question from Planning, Procurement, or Logistics returns the same answer

### Judging Criteria

| Criteria | What Judges Want |
|----------|-----------------|
| Real World Relevance | Realistic data model, actual supply chain metrics |
| Technical Execution | Semantic views + Cortex Agent working end-to-end |
| Solution Completeness | Ontology → Semantic Views → Agent → Multi-persona demo |

## CoCo Ownership (YOU own these)

| Area | Path | Skills to Use |
|------|------|--------------|
| Database setup | `sql/01_setup/` | `sql-author` |
| Table DDL | `sql/02_tables/` | `sql-author` |
| Sample data | `sql/03_sample_data/` | `sql-author` |
| Governance + `CONFORMED` layer | `sql/04_governance/` | `data-governance`, `dynamic-tables` |
| Data quality (running Claude Code's `quality/` SQL; wiring DMFs) | — | `data-quality` |
| Semantic views + generator | `semantic/` | `agent-studio` |
| Cortex Agent | `agent/` | `agent-studio` |
| Lineage validation | — | `lineage` |

Full ownership table and the handoff lock for Claude Code's SQL:
`.agents/tasks/COCO_TASKS.md` § "Working with Claude Code" (replanned 2026-09-29).

### DO NOT TOUCH (Claude Code owns these)

- `app/` — Streamlit demo application
- `tests/` (incl. `tests/scale/`) — tests and the scale harness
- `demo/`, `deploy/`, `.github/`, `docs/references/`, `README.md`
- `data_gen/`, `quality/`, `eval/` — Claude Code's Snowflake SQL. **CoCo runs these files
  but never edits them**, except small run-blocking fixes recorded as a diff in
  `docs/artifacts/runs/<card>_run.md`.

## Snowflake Connection

- **Active account (from 30 Sep evening): the event account.** Connection **`QURFOQP-XU04029`**
  (locator `VC33954`, user `LAZYBOY2`, `AZURE_CENTRALINDIA`, Enterprise, $399.68 free usage on
  30 Sep). Pass `connection='QURFOQP-XU04029'` on every SQL call. The whole build was replayed
  there on 30 Sep (B08m ✅, `docs/artifacts/runs/B08m_run.md`).
- **Old account, no longer used:** connection `tyduokn-gf25237` (account `DA53081`). Never build
  or drop anything there.
- **Target Database**: `SUPPLY_CHAIN_FORGE`
- **Source schemas**: `ERP_SOURCE`, `WMS_SOURCE`, `TMS_SOURCE`, `SRM_SOURCE`
- **Derived schemas**: `CONFORMED`, `GOVERNED`, `SEMANTIC`, `APP`, `OPS`
- **Warehouse**: `FORGE_WH` (XSMALL, auto-suspend 60s)
- **Roles**: `FORGE_ADMIN`, `PLANNER_ROLE`, `BUYER_ROLE`, `LOGISTICS_ROLE`, `FORGE_APP_ROLE`
  (the public app's service user `FORGE_APP_SVC`)
- **Running repo SQL files:** `sql/replay_helper.py` (load it in the Python REPL; see its
  docstring). It handles the non-ASCII problem of the tool bridge.

### Verified account capabilities

- `CORTEX_ENABLED_CROSS_REGION = ANY_REGION` — all frontier models available
- Semantic views support `AI_VERIFIED_QUERIES`, `AI_SQL_GENERATION`,
  `AI_QUESTION_CATEGORIZATION` in DDL
- `SNOWFLAKE.CORTEX.DATA_AGENT_RUN()` available — agent callable from plain SQL
- **Budget (checked 2026-09-30 evening):** old account **$135.91** left (read-only from now on);
  event account **$399.68** (30 days from signup). Spend on 29 Sep was $126 (CoCo $109) and on
  30 Sep $49 by the evening (CoCo $36).
- **Earlier check (2026-09-29)**: $400 of free usage, **ending 2026-10-18**. About $138 spent,
  about $262 left.
  - Cortex Code is ~85% of spend. It's billed per token at $2/credit, and the 29 Sep session
    alone cost ~$45.
  - Warehouses are ~15% ($3/credit). COMPUTE_WH (10-min auto-suspend) is 94% of warehouse credits.
  - **Budget is a constraint.** Keep CoCo sessions short with small context, and use subagents
    sparingly.
  - Keep warehouses XS with 60s auto-suspend. Pick lags and schedules to save cost (see
    SESSION_LOG Session 24, "Credit check").

### Account switch plan (user-approved 2026-09-29)

The organisers issued a new **event account**: $400, 30 days from signup, and the claim
window closes **3 Oct 2026 UTC**. There's no top-up to the old account. The plan uses both:

| When | What | Account |
|---|---|---|
| **29 Sep (today)** | The user claims the event account: "AI Data Cloud" flow (not "Cortex Code CLI"), same registration email, **Enterprise** edition, **Azure Central India** if offered (fallback order: AWS Asia Pacific Mumbai → AWS US West Oregon; avoid GCP). Then adds a VS Code connection. | new (idle) |
| 29 Sep → 1 Oct | Build as planned (B09, B09a, B08c, B10, B12), plus the **B13 scale proof on Day 3**: its art 12 doesn't depend on the account, so old credits pay for the costly run | **old** `DA53081` |
| **30 Sep** | **B08m trial move**: account setup + replay the v1 baseline in the new account, to catch edition, region or Cortex problems early (~$3–5) | new |
| **End of 1 Oct** (or sooner if the old balance drops below ~$60) | **B08m cutover**: replay the full build from the repo, regenerate the data (deterministic), re-verify art 03–10 numbers match | new |
| 2 Oct → results | B14 live tests + security review, B15 cost controls + deploy (the submitted app link), a short eval smoke run, final artifacts, then the buffer. The old account is no longer used. | **new** |

**Rule until the cutover: nothing is built by hand.** Every object (DDL, grants, the agent,
Cortex Search, DTs, DMF attachments, schedules, the app deploy) must exist as a re-runnable
repo script, so the cutover is a replay. The code is account-agnostic (only docs name
`DA53081`); keep it that way.

## Coordination Protocol

1. At session start, read `docs/SESSION_LOG.md` for the exact next action
2. Work the queue in `.agents/tasks/COCO_TASKS.md`
3. A task is done when its **gate** passes, not when the SQL merely runs
4. At session end, append an entry to `docs/SESSION_LOG.md`
5. Update `docs/MILESTONES.md` progress tracker when a milestone completes
6. Update `.agents/HANDOFF.md` when Claude Code needs something from you
7. Log architecture decisions in `.agents/DECISIONS.md`

## Current State

**Updated 2026-09-30 late evening.** 16 of 21 CoCo cards are done (B09a and **B08m** today):
**the whole build now runs in the event account `QURFOQP-XU04029`** (`runs/B08m_run.md`). Next:
B15a (key + public link), B12a part 2 (C17 + the nightly task), B14, B15. Always start from
`.agents/NEXT.md` → "CoCo → NEXT SESSION STARTS HERE".

## Critical Gotchas

- **Tool bridge and non-ASCII text:** the Windows tool bridge garbles non-ASCII (`§`, `→`, `—`,
  Hindi). Send such SQL base64-encoded (`sql/replay_helper.py` does it), fetch such results
  base64-encoded, and edit repo files with the edit tool, never through the Python REPL.
- **Long calls:** the REPL can time out while the query keeps running: poll `QUERY_HISTORY`.
  The REPL can also restart and lose its variables: re-load the helper.
- **Timezone:** both accounts use America/Los_Angeles. Pass the UTC date explicitly to anything
  date-driven (the nightly day-append).
- **Clones:** a cloned dynamic table keeps reading the ORIGINAL database (the definitions name
  it in full): re-create the DTs in any clone test.
- **`CREATE OR REPLACE` drops grants made by OTHER scripts** (found at B08m: re-creating
  `SP_DATA_HEALTH` for C16 silently removed the public app's USAGE on it in the old account).
  After re-creating ANY object the app uses (the semantic view keeps grants via `COPY GRANTS`;
  procedures and the agent don't), **re-run `sql/05_app_access/01_app_service_user.sql`**. It's
  idempotent and doesn't touch `FORGE_APP_SVC`'s key.
- **Agent tools run as the CALLING role** (observed at B10), not the user's default role.
- **Semantic view clause order is enforced**: `TABLES` → `RELATIONSHIPS` → `FACTS` →
  `DIMENSIONS` → `METRICS`. Build incrementally (2 tables first), never all 9 blind.
- **Row access policies must not change metric aggregates** across personas, or the
  core hackathon claim breaks. Policies restrict detail rows; consistency tests assert
  aggregate equality.
- ERP `VBAK.ERDAT` and TMS `VTTK.PROM_DLV_DT` deliberately disagree. Only TMS is
  authoritative. Never expose ERP's date as a promised date in the governed layer.
