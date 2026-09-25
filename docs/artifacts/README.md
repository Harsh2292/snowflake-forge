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

**The MCP server is still built (B14).** It is a *product feature* demonstrated to judges —
"the governed ontology is reachable by any MCP client" — not a development dependency.
Those two concerns are now cleanly separated.

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

| File | Produced at | Contents | Consumed by |
|------|------------|----------|-------------|
| `01_default_role.md` | **B02** | The user's default role + default warehouse (agents use default role, not session role) | reference |
| `02_raw_metrics.md` | **B05** | Raw metric values before any semantic layer: naive ERP-date OTD, governed-date OTD, fill rate, DOI, landed cost | C05 demo script, Tab 3 |
| `03_governed_columns.json` | **B07** | `INFORMATION_SCHEMA.COLUMNS` dump for all 9 governed views — real column names and types | **C6a** |
| `04_persona_outputs.json` | **B07b** | Actual output of all three persona procedures, showing real masked values | **C6a** |
| `05_metric_values.json` | **B08** | All 4 metric values, plus each metric broken out by every valid dimension | **C6b** |
| `06_dimension_matrix.md` | **B08** | Every metric × dimension pairing actually tested: pass/fail, with the error text for failures | **C6b** |
| `07_agent_response.json` | **B10** | ⭐ **A real, complete `DATA_AGENT_RUN` response** — unabridged | **C6c** |
| `08_agent_answers.md` | **B10** | All 8 canonical questions with the agent's actual answers and generated SQL | **C6c** |
| `09_consistency_proof.json` | **B11** | 4 metrics × 3 personas, real values, to 6 decimal places | **C6c** |
| `10_dmf_results.json` | **B12** | `DATA_QUALITY_MONITORING_RESULTS` snapshot | Tab 5 |
| `11_contract_audit.md` | **B13** | Line-by-line conformance result against `docs/CONTRACT.md` | all |

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

## Upgrade path (only if artifacts prove insufficient)

If Claude Code hits something it genuinely cannot verify from a file, escalate to live
read-only access:

1. CoCo creates role `FORGE_MCP_READER` — `USAGE` on database/`GOVERNED`/`SEMANTIC`,
   `SELECT` on governed views, `USAGE` on the persona procedures. **No write privileges.**
2. CoCo deploys `SUPPLY_CHAIN_MCP_RO` with a single read-only `SYSTEM_EXECUTE_SQL` tool
3. **User** creates a PAT in Snowsight bound to `FORGE_MCP_READER` — never `ACCOUNTADMIN`
4. **User** stores it via `/secrets`. Never paste a token into chat.
5. CoCo writes the MCP client config. Hostnames use **hyphens, not underscores**.

This is build step **B07c**, currently deferred. Do not do this work speculatively — it is
only worth the setup cost if artifacts actually fall short.
