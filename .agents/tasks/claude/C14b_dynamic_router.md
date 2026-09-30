# C14b — A more dynamic router: vocabulary from the semantic view, filters, typos

| | |
|---|---|
| **Owner** | Claude Code (app only; no Snowflake objects, no contract change) |
| **Milestone** | Replan Day 3 (1 Oct), asked by the user 30 Sep after C14 |
| **Prerequisite** | C14 (router, instant answers) |
| **Writes** | new `tests/tools/build_vocabulary.py`, new `app/utils/vocabulary.json`, `app/utils/router.py`, `app/utils/config.py` (the hand lists shrink), `app/ui/payloads.py` (filtered answer), tests |
| **Status** | ✅ DONE 2026-09-30 (approved by the user the same day; no CoCo work) |

---

## Goal
The instant path understands many more ways of asking, without anyone hand-writing phrases.
Its words come from the semantic view itself, it answers "for one value" questions
("fill rate in APAC"), and it forgives small typos. It stays as safe as C14: when unsure, the
agent answers.

## Why
The user (30 Sep): "make it more dynamic as much as you can". C14's matcher uses
hand-written regex lists in `config.py`: 4 metrics' synonyms and 26 dimension phrases. It
misses anything not on the list ("by facility", "by transporter", "for SMB customers",
"fil rate"), and it drifts when CoCo changes the semantic view.

## Design
1. **Vocabulary generated from the semantic view** (`semantic/01_semantic_view.sql`):
   - `tests/tools/build_vocabulary.py` reads it and writes `app/utils/vocabulary.json`, the
     same pattern as `captured.json`.
   - For the 4 contract metrics: name words, `WITH SYNONYMS`, contract label.
   - For every contract §4 dimension: its name words (`plant_region` → "plant region",
     "region"), its own synonyms ("quarter", "segment", "transporter", "site name"), and its
     table's synonyms (plants: facility, site, DC; customers: client, account; parts:
     material, SKU, item).
   - A unit test fails when the JSON is out of date with the SQL, so a semantic-view change
     can't silently leave the app behind.
   - Kept by hand: only the tie-breaks the verified queries set ("region" → plant region,
     "quarter" → year-quarter, "country" → plant country).
   - Result: every valid metric × dimension pairing in §4 is reachable, not just the ~26
     phrases.
2. **One-value filters**, e.g. "fill rate in APAC", "on-time delivery for enterprise
   customers", "landed cost for DHL", "days of inventory at Singapore Logistics Gateway":
   - **No new SQL.** The answer is that value's row of the matching breakdown query ("fill
     rate by region" → the APAC row). It's the same query and the same number as Explore
     and the "by region" answer.
   - Known values: contract §4's value lists (regions, segments, statuses, priorities,
     categories, plant types, tiers), plus the names inside the breakdown results themselves
     (plants, carriers, countries). Those are learned at run time from the cached queries,
     so new names appear by themselves.
   - One filter only. A filter plus a breakdown ("fill rate by category in APAC") → the agent.
3. **Typo tolerance:** a word of 5+ letters that is one close spelling away from exactly one
   vocabulary word counts as that word ("fil rate", "inventroy", "deliverey").
4. **Safety, unchanged:** every word must be understood or be filler, or the agent answers.
   - Periods ("last quarter", "2025"), "why", comparisons and numbers still go to the agent.
   - The art 08 test must still show 0 false shortcuts.
   - A new test of ~80 phrasings (should / should not fire) guards the wider matching.

## Not in C14b
- **Time periods:** they change the governed window rule; the agent and its rules handle them.
- **The semantic view's 15 extra metrics** (revenue, counts, lead time): they aren't contract
  metrics, so no pairing rules are agreed for them.
- **Reading the vocabulary from Snowflake at run time** (`DESCRIBE SEMANTIC VIEW`): it needs a
  contract change and a CoCo grant for FORGE_APP_ROLE, days before the deadline. The generated
  file gives the same words, and a failing test says when to rebuild it.

## Steps
1. Tests first: the vocabulary build and its freshness check; ~80 phrasings; filters (the
   value equals the breakdown row, in mock and replay); typos; art 08 still clean.
2. `build_vocabulary.py` + `vocabulary.json`; `router.py` reads it (config lists shrink).
3. Filters: `Intent.value`, answer = the row, card sentence "Fill rate in APAC: 92.5% …", SQL
   tab = the breakdown query, the value's row marked in the table.
4. Typos (difflib, a strict cutoff).
5. `pytest -q`, `pytest -m ui` (a filtered answer, both themes), screenshots.
6. Records (card, NEXT, HANDOFF, SESSION_LOG, README "Written:").

## Gate
- [x] Every §4-valid metric × dimension pairing reachable by its own name (a generated test,
      one case per pairing)
- [x] Value answers equal the breakdown row (mock and replay), with no new SQL
- [x] 0 false shortcuts on art 08's 30 (now with every learned name loaded too), on the
      "should not fire" lists, and on a 23-question sweep of tricky phrasings
- [x] The vocabulary freshness test fails when `semantic/01` changes without a rebuild
- [x] `pytest -q` 725 passed, 0 failed; `pytest -m ui` 25/26 in the full run. The one failure
      was the Problem-screen drawer test (a click timed out, element outside the viewport),
      which passed 3 of 3 alone; it doesn't touch Ask. Screenshots checked

## As built (2026-09-30)
- **Reading a question:** words are lower-cased, made singular, and looked up longest phrase
  first. Each is a metric, a dimension, a table, a value, "by / per / for each …", a ranking
  word, "in / for / at / from", or filler. One unknown word → the agent.
- **Vocabulary** (`vocabulary.json`, from `semantic/01`) gives, per contract dimension:
  - its name, its alias, its synonyms
  - the name without its table's name ("region", "segment", "status")
  - that remainder after the table's name and synonyms ("client segment",
    "consignment status", "SKU category")

  "By plant" / "by facility" is the table's `<name>_name` dimension. Metric words are the
  view's synonyms, the name and the label, plus `config.EXTRA_METRIC_PHRASES` ("on time",
  "inventory cover").
- **A word with several meanings** is kept only if exactly one meaning pairs with the metric
  ("fill rate by status" → order status); else `config.DIMENSION_TIEBREAK` (region → plant
  region, quarter → year-quarter); else the agent ("OTD by status", "fill rate by name").
- **Values:**
  - a value needs "in / for / at / from" before it, or its dimension or table after it
    ("enterprise customers", "high priority orders", "APAC customers" → customer region)
  - number-only values and periods are never values
  - learned names (plants, carriers, countries, subcategories; ≤ 100 each, so not part names)
    come from `router.learn_values()` (the breakdown queries Explore runs). The Ask screen
    fetches them only when a question isn't understood without them, and caches them 12 h.
    A distinctive first word also counts ("FedEx", "Singapore")
- **Typos:** difflib, cutoff 0.85, exactly one close known word, 3+ letters, no digits.
- **Card:** "Fill rate for APAC (region): **92.5%** over the last 12 months, by order date.",
  with the whole breakdown as the chart and its SQL in the SQL tab.
- **Tests:** `tests/unit/test_router.py`, now 209, plus a browser test for a value question.

**Estimate:** 2–3 hours. C05 starts after it.
