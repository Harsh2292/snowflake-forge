# Artifact Handoff

> **How Claude Code verifies against real Snowflake without needing Snowflake credentials.**
>
> CoCo runs the live query. CoCo writes the **real output** here. Claude Code verifies
> against the file. No PAT, no MCP client, no setup required from the user.

---

## Why this exists

Claude Code has no Snowflake access:

- `connections.toml` uses `OAUTH_AUTHORIZATION_CODE` — browser-based, nothing reusable
  non-interactively
- `snow` CLI is not installed
- No secrets are stored

Rather than block on credential setup, CoCo captures real outputs as committed files.
Claude Code parses actual Snowflake output instead of guessing, and no one has to create a
token.

**The MCP server was dropped on 2026-09-29** (user decision): it doesn't help the core
system deliver correct answers. Artifact handoff stays the only verification path.

The same no-credentials rule covers the realistic data (from the 2026-09-29 replan):
Claude Code writes the SQL generator in `data_gen/`, CoCo reviews and runs it, and the
results come back here as artifacts.

---

## Rules

| Rule | |
|---|---|
| **CoCo writes, Claude reads** | Claude Code never edits files in this folder |
| **Real output only** | Never hand-write or approximate an artifact. Capture actual query output. |
| **No secrets** | Never commit tokens, passwords, or connection strings |
| **Stamp everything** | Every artifact records the build step and timestamp that produced it |
| **Contract is still the arbiter** | If an artifact contradicts `docs/CONTRACT.md`, that is a **Change Request**, not a licence to adapt the app |

---

## Artifact schedule

Replanned 2026-09-29: the data becomes realistic (10 years, real-world mess) at **B08c**,
so art 02–06 were captured on the v1 data and are re-captured on the new data.

| File | Produced at | Contents | Consumed by |
|------|------------|----------|-------------|
| `01_default_role.md` | **B02** | The user's default role + default warehouse (agents use default role, not session role) | reference |
| `02_raw_metrics.md` | **B05** (v1 data; the B08c gate re-measures it) | Raw metric values before any semantic layer: naive ERP-date OTD, governed-date OTD, fill rate, DOI, landed cost | C05 demo script, Tab 3 |
| `03_governed_columns.json` | **B07**, re-captured at **B08c** | `INFORMATION_SCHEMA.COLUMNS` dump for all 9 governed views — real column names and types | **C6a** |
| `04_persona_outputs.json` | **B07b**, re-captured at **B08c** | Actual output of all three persona procedures, showing real masked values | **C6a** |
| `05_metric_values.json` | **B08**, re-captured at **B09** | All 4 metric values, plus each metric broken out by every valid dimension | **C6b** |
| `06_dimension_matrix.md` | **B08**, re-captured at **B09** | Every metric × dimension pairing actually tested: pass/fail, with the error text for failures | **C6b** |
| `07_agent_response.json` | **B10** ✅ 30 Sep | ⭐ **A real, complete `DATA_AGENT_RUN` response**, unabridged: the raw text byte for byte (Q02, OTD by region, 10:22 UTC, the CR-007 call form; stamp in `runs/C11_run.md`) | **C6c** |
| `08_agent_answers.md` | **B10** ✅ 30 Sep | The whole evaluation set (30 questions, 27 passed): answers, generated SQL, pass/fail, latency | **C6c** |
| `09_consistency_proof.json` | **B09** (old B11 merged in) | 4 metrics × 3 personas, real values, to 6 decimal places | **C6c** |
| `10_dmf_results.json` | **B12** ✅ 30 Sep | `DATA_QUALITY_MONITORING_RESULTS` snapshot (latest per association, 77), plus `SP_DATA_HEALTH('ALL')` per role and the shipments entity | Tab 5 |
| `11_contract_audit.md` | **B14** ✅ 1 Oct | The live contract audit (148/148 as admin and as the public app user) plus the security review (identity, masking, AI safety, abuse/cost, observability, findings F1–F9; F8/F9 fixed late 1 Oct) | all |
| `12_scale_report.md` | **B13** ⏹ not written (stopped by the user 1 Oct; `runs/B13_partial_run.md`) | The scale proof on a clone: timings, partition pruning, credits, and proof the definitions and SQL shape didn't change | C05, README |

### Run reports: `runs/`

From the 2026-09-29 replan, Claude Code writes Snowflake SQL (`data_gen/`, `quality/`,
`eval/`, `tests/scale/`) and CoCo runs it. Every run produces
`docs/artifacts/runs/<card>_run.md`:
- the file(s), role, warehouse, parameters and timestamp
- each statement's outcome, with verbatim error text for failures
- row counts, timings and the self-check results
- any small run-blocking fix CoCo applied, as a diff (Claude Code adopts it in its file)
- the verdict: **DONE** or **RETURNED** (also set in the "Ready for CoCo to run" table in
  `.agents/HANDOFF.md`)

Run reports are working records, not contract artifacts; the numbered artifacts above stay
the fixtures.

---

## The critical artifact: `07_agent_response.json`

This is the one that most affects Claude Code's work. The app's entire "Ask" tab depends on
parsing the agent response, and that JSON shape is the biggest unknown in the project.

At **B10**, CoCo must capture a **complete, unmodified** response — every field, every
nesting level, including tool-call traces and citations. Not a summary. Not the answer text
alone. The raw object.

Claude Code writes its parser against that file. When live access eventually arrives, the
parser should already be correct.

---

## Capture pattern

```sql
-- Capture as JSON for machine-readable artifacts
SELECT TO_JSON(OBJECT_CONSTRUCT(
  'build_step',  'B08',
  'captured_at', CURRENT_TIMESTAMP()::VARCHAR,
  'payload',     <the actual result>
));
```

Write the output verbatim into the artifact file. Add a short header noting what the query
was, so the capture is reproducible.

---

## If artifacts prove insufficient

If Claude Code hits something it genuinely can't verify from a file, it raises it in
`.agents/HANDOFF.md` under `## Blocked`, naming exactly what it needs. CoCo then captures
an extra artifact. The read-only MCP upgrade path (old B07c) was dropped on 2026-09-29,
together with the MCP server.
