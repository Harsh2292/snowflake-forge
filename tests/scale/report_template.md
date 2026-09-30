# Art 12 — Scale report (template)

> Template for `docs/artifacts/12_scale_report.md`, filled by CoCo at **B13** from
> `tests/scale/99_run.sql`. Written by Claude Code (C12). Keep the headings, so C05's
> scalability doc can quote it section by section.

| | |
|---|---|
| **Date / account** | |
| **Clone** | `SUPPLY_CHAIN_FORGE_SCALE` (zero-copy clone of `SUPPLY_CHAIN_FORGE`) |
| **Data** | C08 at scale factor `…`, seed `20260929`, END_DATE `2026-09-30` |
| **Warehouses** | `FORGE_WH` (XS) · `…` (size `…`, resource monitor `…` credits) |
| **Runs** | `sf1-xs` (original, SF 1) · `clone-xs` · `clone-large` |

## 1. What was measured

- Every query the core system sends, from `OPS.SCALE_QUERIES`, which is generated from the
  app's own SQL builders:
  - the 4 metrics, all-time and in the §3a window
  - the 58 valid metric × dimension pairings
  - the 3 persona metric procedures
  - the §8 naive query
  - (the agent questions, if B13 ran them)
- The same catalogue in all three runs.

## 2. Data volume

The row counts per `CONFORMED` table, from the data-volume query in `99_run.sql`:

| Table | SF 1 rows | Clone rows | Clone GB |
|---|---|---|---|
| SALES_ORDER | | | |
| ORDER_LINE | | | |
| SHIPMENT | | | |
| INVENTORY | | | |
| … | | | |

Dynamic-table refresh times after the large load:

| Table | Refresh | Seconds |
|---|---|---|
| | | |

## 3. Claim 1: the same SQL at every scale

The claim 1 query returns **0 rows**: every query has one `SQL_HASH` across `sf1-xs`,
`clone-xs` and `clone-large`.

Result: …

## 4. Claim 2: the same numbers for every persona

| Run | Persona fingerprints | Procedures |
|---|---|---|
| sf1-xs | 1 | 3 |
| clone-xs | 1 | 3 |
| clone-large | 1 | 3 |

## 5. Claim 3: warehouse size changes speed, never answers

The claim 3 query returns **0 rows**: `clone-xs` and `clone-large` give identical
`RESULT_HASH` for every fingerprinted query.

Result: …

## 6. Speed and pruning, by path

| Run | Warehouse | Path | Queries | Failed | p50 ms | max ms | GB scanned | Pruned share |
|---|---|---|---|---|---|---|---|---|
| sf1-xs | XS | SEMANTIC_VIEW | | | | | | |
| clone-xs | XS | SEMANTIC_VIEW | | | | | | |
| clone-large | … | SEMANTIC_VIEW | | | | | | |
| … | | PROCEDURE / NAIVE | | | | | | |

The slowest 5 per run, and where an infrastructure knob would help:

| Run | Query | ms | Partitions scanned / total | Knob to turn (clustering, warehouse size, materialization) |
|---|---|---|---|---|
| | | | | |

## 7. Cost

| Warehouse | Credits (B13 window) |
|---|---|
| | |

## 8. Conclusion

In three sentences:
1. What stayed the same: the SQL, the definitions, the governance and the answers.
2. What changed: time and credits, and by how much.
3. Which knob a production deployment would turn first, with the evidence from §6.

## Notes and deviations

The items CoCo recorded in `docs/artifacts/runs/C12_run.md`:
- the history source used for timings
- whether `RESULT_SCAN` worked on `CALL`
- grants in the clone
- any query that failed, and why
