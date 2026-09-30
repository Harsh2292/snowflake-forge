# C14 — Faster answers: a KPI shortcut and a parallel multi-part router

| | |
|---|---|
| **Owner** | Claude Code (app only; no Snowflake object changes) |
| **Milestone** | Replan Day 3 (1 Oct), kept by the user 30 Sep |
| **Prerequisite** | C6c (the live Ask path, parser), C15 (Ask limits, answer cache), art 08 (latencies) |
| **Writes** | new `app/utils/router.py`, `app/ui/screens/ask.py`, `app/ui/payloads.py` + `app/ui/views/answer.html` (the "answered instantly" chip, multi-part cards), `app/utils/config.py` (synonyms), tests |
| **Status** | ✅ DONE 2026-09-30 (offline gate). The live check (a suggested question in ~1–2 s) is part of B15a / the rehearsal |

---

## Goal
The questions people ask most answer in about a second instead of 12, and multi-part
questions take as long as their slowest part, not the sum. The numbers stay the governed
ones, and the card says how each answer was produced.

## Why (measured, art 08, 30 questions)
- **The 8 suggested questions take ~12.6 s each**, even though they're verified queries:
  the time is the orchestrator LLM planning and writing, not Snowflake. Other questions
  take 20–33 s, and multi-part ones 29–38 s. Median 17.7 s, p95 48.8 s.
- On a public demo link the first click matters most, and it's almost always a suggested
  question.

## Design
1. **KPI shortcut (`router.match(question)`).** A small, deterministic intent matcher:
   - **metrics** from contract §3 labels plus synonyms ("on-time delivery", "OTD",
     "delivery performance"; "fill rate"; "days of inventory", "DOI", "inventory cover";
     "landed cost")
   - **dimensions** from §4 ("by region", "by plant", "by product/part category", "by
     quarter", "by customer segment", "by carrier", "by order status", …)
   - **ranking words** ("worst", "best", "top", "lowest")
   - It **only fires when certain**: exactly the metric(s) and at most one dimension, a
     §4-valid pairing, and no other content words such as a time period, a filter or a
     named entity. Anything else goes to the agent.
   - The answer comes from `forge_data.get_metric`: the same `SEMANTIC_VIEW` query, the same
     contract default window. It's shown on the usual answer card with the SQL, the
     definition, the chart, a plain-English sentence (the mock's canned-answer wording,
     now live), and a chip **"Instant answer · governed semantic view"**.
   - It costs no Cortex call, so the C15 limits don't count it.
2. **Multi-part router (`router.split(question)`).** Splits on clear boundaries only: `?`
   between sentences, `; `, " and also ", or "A and B" when both sides are full
   metric-by-dimension phrases. Each part is routed on its own: known parts use the
   shortcut, the others go to the agent. **Agent parts run in parallel** (a thread pool,
   at most `ASK_LIMITS.concurrent`), and each counts against the limits. One card per part,
   in the question's order, under the one question.
3. **Safety:**
   - The router never changes a number. It only chooses between two governed paths (the
     same semantic view).
   - A test replays all 30 art 08 questions: the shortcut must fire only where the agent's
     answer used the same contract metric and dimension, and must never fire for refusals,
     clarifications, lookups or free text.
   - A setting, `[forge] shortcut = false` in secrets, turns it off without a commit.
4. **Honesty in the UI:** the chip says which path answered ("Instant answer · governed
   semantic view" or "Supply Chain Agent"), and the demo script explains the design as a
   production pattern: fixed paths for known intents, the LLM for everything else.

## Not in C14
Streaming responses (needs the REST API, too big for now); Snowflake-side speed (more
verified queries: CoCo's B09a).

## Steps
1. Tests first:
   - the matcher on the 8 canonical questions + ~20 variants (should fire) + the art 08
     refusal / lookup / free-text / multi-part questions (should not, or should split)
   - the splitter cases
   - the parallel path with a fake slow agent: total time ≈ the slowest part
2. `router.py`; wire it into `ask._ask` (shortcut → limiter-free; agent parts → the pool
   through the existing guard); the payload and chip; multi-part cards.
3. `pytest -q`, `pytest -m ui` (an instant card in both themes, a 2-part question); timed
   locally in mock mode and with the replay.
4. Records (card, NEXT, HANDOFF, SESSION_LOG).

## Gate
- [x] The 8 suggested questions answer via the shortcut, with the same numbers as the
      agent's verified queries: each runs the verified query's own SQL (semantic/01,
      compared text for text; the worst-plants query ranks the same rows in Python instead
      of `ORDER BY … LIMIT 3`), and the numbers equal art 05 through the replay
- [x] 0 false shortcuts on the 30 art 08 questions (fires on Q01–08, Q19 and the metric
      parts of Q22/Q23, each with the metric and dimension the agent itself used); Q22 and
      Q23 split; Q20 and Q10 stay whole
- [x] Parallel agent parts: 0.6 + 0.3 + 0.5 s jobs finish in ~0.6 s
- [x] `pytest -q` 619 passed, 0 failed; `pytest -m ui` 24/24; screenshots checked (light, dark)
- [ ] Live (B15a / rehearsal): a suggested question answers in ~1–2 s on the public link

**Estimate:** 3–4 hours.

## As built (2026-09-30)

- **`app/utils/router.py`** (pure Python):
  - `match()`: one contract metric (synonyms in `config.METRIC_SYNONYMS`, from the semantic
    view's own), at most one dimension after "by / per / for each / across" or "which …" /
    "top …" (`config.DIMENSION_SYNONYMS`), a §4-valid pairing, and only filler words left.
    Periods, filter values, numbers, "why", other languages → the agent.
  - "By quarter" is `orders.order_year_quarter`, as the verified query and the agent's rule 4
    use (the mock's canned map still says `order_quarter`; that only affects the agent's mock).
  - Ranking: "lowest/highest/top/bottom" literally; "worst/best" by metric (a high landed
    cost is worst); "best days of inventory" → the agent (it's a judgement).
  - `split()`: numbered parts (with an optional "Two questions:" preamble only), `;`,
    consecutive questions that each end in `?`, " and also ", and "A and B" when every side
    is a known metric question. No split when a later part points back ("its", "that", …)
    or a preamble carries context ("For APAC: 1) … 2) …"). At most 4 parts.
  - `instant_answer()`: `forge_data.get_metric` (the §5.1/§5.2 SQL with the §3a window),
    shaped like a parsed agent answer: a sentence with the value and its window, the SQL,
    the table (ranked when asked), the chart title.
  - `run_parallel()`: a thread pool; each worker's fallback notices are handed back to the
    UI thread (`forge_data.add_notices`).
- **`ask.py`**: route → instant parts first (cached with the screens' 12 h TTL, never a
  fallback) → agent parts reserved through the limiter (the cooldown is per question, each
  part counts toward the caps) → run at once. The chat stores `{"question", "parts": [...]}`;
  one card per part, the question bubble once.
- **The card** says which path answered ("Instant answer · governed semantic view" or
  "Supply Chain Agent") and the time taken; a split card shows its part.
- **"Ask is paused"** (CoCo's ask): `forge_data.ask_agent` returns `status: "paused"` on
  "does not exist or not authorized", with no fallback notice. The Ask screen shows a note
  (not the banner), pauses agent calls for `ASK_PAUSE_SECONDS` (10 min) process-wide, caches
  nothing, and instant answers keep working.
- **Off switch:** `[forge] shortcut = false` in secrets.
- `app/requirements.txt`: Snowpark ≥ 1.24 (thread-safe sessions, for the parallel parts).
- Tests: `tests/unit/test_router.py` (103), a browser test for an instant card and a 2-part
  question in both themes; the older Ask tests updated for the new chat shape.

**Found on the way (for the demo script, C05, and CoCo):** in art 08 Q23 the agent didn't use
the governed metric for landed cost. Analyst wrote its own CTE
(`AVG(freight_cost + duty_cost + handling_cost)` on `V_SHIPMENT`), which skips the metric's
rules: missing duty counts as zero, and implausible costs are excluded. It answered $604.81;
art 05's governed value is $604.84 (a day earlier, so the window differs too). The shortcut
answers that part with the governed metric.
