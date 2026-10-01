# B14 review fixes run: C-1..C-4 (Codex review) + the three READY lock rows

| | |
|---|---|
| **Date** | 2026-10-01 (~10:00–10:45 PT) |
| **Account** | `QURFOQP-XU04029` (LAZYBOY2), `FORGE_WH` (XS) |
| **Asked by** | the user ("lets complete everything and write close out in the file"), after Claude Code's HANDOFF note "Four SQL tasks for CoCo from an external review" |
| **Files changed** | `docs/CONTRACT.md` (v1.8, CR-009 ACCEPTED), `sql/04_governance/02_masking_policies.sql` (policy 5), `03_governed_views.sql` (`V_SUPPLIER.email` policy; `V_SOURCING` E11 rule + `COPY GRANTS`), `06_conformed_layer.sql` (FX_RATE, FX_MISSING, E11), `docs/DATA_SPEC.md` §4.2 E11 (where the rule is applied) |
| **Run** | the masking policy + `ALTER VIEW … SET MASKING POLICY`; the whole of `06_conformed_layer.sql` (55 s); `SOURCING` + `V_SOURCING` once more for the final E11 rule; `SP_ATTACH_DMFS(…, 'TRIGGER_ON_CHANGES')`. Then the three lock rows |

## Baseline gate (before vs after, everything identical)

Captured before any change, compared after the final rebuild:

| Probe | Before | After |
|---|---|---|
| hash of (part, primary supplier) in `V_SOURCING` | -8506228482415782108 | same |
| `V_SOURCING` rows / primaries | 1,965 / 1,200 | same (every persona and `FORGE_APP_ROLE`) |
| `V_ORDER_LINE` / `V_SHIPMENT` rows | 2,001,441 / 693,465 | same |
| `FX_RATE` rows | 54,790 | same |
| Σ order-line USD / Σ freight USD / Σ contract price USD | 81,616,115,824.45 / 313,364,048.13 / 221,821.36 | same |
| 63 metric results (4 metrics × the app's breakdowns) | — | **0 differences** |
| `SP_DQ_SELF_CHECKS` | 93/93 TRUE | **93/93 TRUE** |
| `SP_DATA_HEALTH('ALL')` as `FORGE_APP_ROLE` | OK | **OK**, 10/10 statuses OK, as-of 2026-09-30 |
| DMFs | 77 on 21 objects | re-attached: 77 ADDED, 21 SET SCHEDULE OK |
| grants on `V_SOURCING` | 6 | same 6 (`COPY GRANTS`) |

## C-1 / CR-009: supplier e-mail masked: DONE

- CR-009 moved out of the template comment, **ACCEPTED** (the user, 2026-10-01). Contract **v1.8**:
  §6 gains `V_SUPPLIER.email: *** MASKED *** · visible · *** MASKED ***`.
- `GOVERNED.MASK_SUPPLIER_CONTACT` (visible to `FORGE_ADMIN`, `BUYER_ROLE`, `ACCOUNTADMIN`;
  `*** MASKED ***` otherwise). It already existed with this body, so `IF NOT EXISTS` kept it.
  Attached with `ALTER VIEW GOVERNED.V_SUPPLIER MODIFY COLUMN email SET MASKING POLICY …`. The
  view was not re-created, so no grants moved.
- Live, `SELECT … FROM GOVERNED.V_SUPPLIER` (150 rows):

| Role | masked | sample |
|---|---|---|
| `FORGE_ADMIN` | 0 / 150 | `contact.sup068@supplier-forge.net` |
| `BUYER_ROLE` | 0 / 150 | visible |
| `PLANNER_ROLE` | 150 / 150 | `*** MASKED ***` |
| `LOGISTICS_ROLE` | 150 / 150 | `*** MASKED ***` |
| `FORGE_APP_ROLE` (public link) | 150 / 150 | `*** MASKED ***` |

- No screen, procedure or semantic-view column reads supplier e-mail, so art 03/04 don't change.
- **For Claude Code:** `config.MASKING_MATRIX` + the governance tests for the new row.

## C-2: FX_RATE can't duplicate USD: DONE

`t` now has `AND UPPER(TRIM(FCURR)) <> 'USD'`, so USD comes only from the `UNION ALL` branch.
Live: 0 duplicate `(currency, rate_date)`, 0 USD rows with a rate other than 1, 54,790 rows
(unchanged: TCURR has no USD rows today, so this only guards the future). Not re-proven on a
clone with an injected USD→USD row: the filter is one predicate on the input.

## C-3: a missing FX rate is flagged: DONE

`FX_MISSING` is added to `dq_flags` when the FX join finds no rate, in `SOURCING`, `ORDER_LINE` and
`SHIPMENT`. On `SHIPMENT`, `COST_UNKNOWN` stays as it was. The condition is `usd_rate IS NULL`:
USD amounts always join the USD = 1 row, so no extra `<> 'USD'` test is needed. The header list
of flags is updated. Live: **0** rows flagged in each table, as expected: every currency has a rate,
and the 2,394 NULL rate-days all fall before the first order.
**For Claude Code:** the `FX_MISSING` count you offered for `quality/` (DQ_CHECKS → Data health).

## C-4: E11 overlapping primaries: DONE, by a different rule from the one proposed

Codex's finding is real: the old `demoted` flag marks the earlier primary non-primary for its
whole life. A replacement starting in the future leaves today with no primary.

**Why not the proposed truncation** (`valid_to = next VDATU − 1`):
- All 12 superseded rows are valid today, so truncation would remove 12 live supplier–part
  links from `V_SOURCING` (1,965 → 1,953).
- It contradicts DATA_SPEC E11 ("the other becomes secondary", "in the view: yes, as
  secondary").
- `C_SOURCING_DUP` (one row per `source_id`) rules out splitting a row in two.

**What I did:**
- `CONFORMED.SOURCING` keeps the source `is_primary` and flags a primary that a later-starting
  primary overlaps as `PRIMARY_SUPERSEDED` (replaces `PRIMARY_DEMOTED`). It stays deterministic
  and incremental.
- `GOVERNED.V_SOURCING` applies DATA_SPEC's rule among the rows valid **today**:
  `is_primary AND ROW_NUMBER() OVER (PARTITION BY part_id, is_primary ORDER BY valid_from DESC, source_id DESC) = 1`.
  The tie-break is the same as the old `LEAD … ORDER BY VDATU, SOURCE_ID`.
- Every consumer reads `V_SOURCING`: the semantic view's `primary_sourcing`, the 3 persona
  procedures and the app. `V_SOURCING` was re-created with `COPY GRANTS`.

A first version with a `primary_until` column failed the nested case (B starts and ends inside A,
so A never became primary again). It was replaced before it was final. Synthetic test of the final
rule (VALUES rows through the exact DT + view logic, 7 as-of dates):

| Scenario | Result |
|---|---|
| A valid, B starts tomorrow (Codex's case) | today A primary; from tomorrow B primary, A secondary |
| B replaced A in the past (= the 12 E11 rows) | before the switch A; after it B, A secondary |
| B nested inside A | A → B (during B) → A again after B ends |
| A ended, then B (gap) | B only |
| primary + a real secondary | A primary, S secondary |

Live: 12 `PRIMARY_SUPERSEDED`; `V_SOURCING` 1,965 rows, 1,200 primaries, **0 parts without
exactly one primary**, the primary-supplier hash identical to before. The persona roles see the
same counts; contract price is visible to Buyer only. A semantic-view query through
`primary_sourcing` (`DAYS_OF_INVENTORY` by `suppliers.supplier_region`, as `FORGE_APP_ROLE`)
returns 3 rows.

## Lock row: `data_gen/30_sp_gen_self_checks.sql` (C17b follow-up): DONE

Re-created as `ACCOUNTADMIN`. `SP_GEN_SELF_CHECKS('SUPPLY_CHAIN_FORGE')`: 122 rows, **106 TRUE,
15 NULL (report-only), 1 FALSE**. The FALSE is the known `CLEAN_FILL_YEAR_MIN` 0.9007 (target
0.905–0.945, since C08). Exactly as Claude Code expected:
- `APPEND_ROWS`: VBAK 797 = 797, VBAP 1,705, VTTK 540, MARD 3,600, all TRUE
- `LOAD_TS_CAP`: 0 on all 5 tables (cap: 2026-10-01 05:00, the last appended day)
- `DATA_DUPLICATE_KEYS` VBAP 30,511 = 30,511; VTTK 77,160
- `DATA_NON_CONTRACT_CODES` VTTK.CARRIER_CD 45,565 = 45,565 (exact, inside ±2%)
- `CHECKSUM_REPEAT` NULL ×10: no earlier run with these parameters (normal)

No fix needed.

## Lock row: `quality/30` (#11) + `eval/20` (#20), `b14-adv-2`: DONE

- Both re-created as `FORGE_ADMIN`, then `sql/05_app_access/01` re-run (it doesn't touch the key:
  `CREATE USER IF NOT EXISTS`, the key line is a comment). Grants identical before and after:
  `SP_DATA_HEALTH` USAGE for the 3 personas + `FORGE_APP_ROLE`.
- `SP_DATA_HEALTH('ALL')`: OK, all statuses OK (every entity has checks, so #11 changes nothing
  today). Self-checks 93/93.
- `SP_RUN_EVAL('b14-adv-2', 'A%')`: **10/10 passed** with the full-response e-mail guard. No
  `has_email` failure, so the old guard missed no leak. p50 19.2 s, p95 51.6 s, max 65.2 s; run 267 s.

## Tests

- `pytest -m live` as **`FORGE_APP_SVC` / `FORGE_APP_ROLE`** (key-pair, the public link's
  identity): **148 passed, 0 failed**, 203 s, every contract section green.
- `pytest -q` (offline): **799 passed**, 148 skipped (live), 30 deselected (ui).

## Cost

All XS: ~1 min to rebuild CONFORMED, the DMF re-runs (serverless), one adversarial eval (10 agent
calls) and the live suite (10 agent calls). Well under 0.5 credits.
