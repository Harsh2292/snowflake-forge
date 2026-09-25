# C03 — Streamlit App (guided story + Explore, mock-driven)

| | |
|---|---|
| **Owner** | Claude Code |
| **Milestone** | M2 (parallel with CoCo B02 → B06) |
| **Prerequisite** | C02 ✅ (`app/utils/forge_data.py`) |
| **Est. effort** | One to two sessions |
| **Writes** | `app/streamlit_app.py`, `app/ui/**`, `app/environment.yml`, `app/requirements.txt`, `app/.streamlit/config.toml`, `tests/unit/test_app_smoke.py` |
| **Status** | ✅ **DONE** 2026-09-24, Revision 2 complete. 125 unit/app tests pass; 24 in-browser interaction checks pass (Playwright, 1366 and 1600 wide, light and dark, no JS errors). |

---

## Goal

A demo app judges can follow without help: a guided four-step story that proves "one
governed number for every team", plus an Explore screen for charts and a Data health
screen. It runs fully in mock mode and is deployable to Streamlit in Snowflake.

---

## Why this design

- **User-approved design:** option **C: Guided flow** on the Claude Design canvas
  <https://claude.ai/artifact/Gzj72vRfw7Skj6k2JnBhNS> (private to the user). Options A and B
  were rejected because the sidebar persona picker contradicted a screen that already showed
  all three personas, and too many elements competed for attention.
- **UX principles applied:** one job per screen, a numbered path that follows the demo
  story, plain-language labels, big hit targets, a visible "next" action on every step,
  status always visible (mock/live, which step), and meaning never carried by colour alone.
- **Colour meaning:** grey = scattered source-system data, blue = the governed number.
- **The user asked for** a modern, interactive, visually engaging UI and one switch for
  light and dark.

### Structure (replaces the five tabs in CLAUDE_TASKS.md Track C3)

| Header item | Screen | Covers the old spec's |
|-------------|--------|-----------------------|
| 1 The problem | Four source systems + ERP-vs-TMS "promised date" gap (79.4% vs 87.1%) | Tab 3 · The Problem |
| 2 The fix | One governed definition per metric, source→governed column map | (new) |
| 3 Same for everyone | Metric tiles, three persona cards with 6-dp values and masking chips | Tab 2 · Consistency Proof |
| 4 Ask | Suggested questions, chat with the agent, answer + chart + SQL + definition | Tab 1 · Ask |
| Explore metrics (tool) | Metric tiles, breakdown buttons (impossible ones disabled with the reason), click-to-focus bar chart, table view | Tab 4 · Metrics |
| Data health (tool) | Plain-English DMF check list with status | Tab 5 · Data Quality |
| Light/Dark switch | Whole app re-themes | — |

The old spec's "persona selector changes the divergence table" becomes three persona cards
shown side by side, each built from that persona's real masked sample.

---

## Design tokens (from design C)

| Token | Light | Dark |
|-------|-------|------|
| Page | `#EDF1F6` | `#121821` |
| Surface | `#FFFFFF` | `#1B2330` |
| Ink | `#16233B` | `#EAF0F8` |
| Secondary ink | `#4A5870` | `#AAB6C7` |
| Governed blue (text) | `#1F63C4` | `#6AAEFF` |
| Bar | `#2A78D6` | `#3987E5` |
| Source grey | `#8C96A5` | `#6B788C` |
| Good (with icon + label) | `#0A8A0A` | `#34C759` |

Font: Instrument Sans (loaded with `@font-face` from fonts.gstatic.com; the SiS CSP allows
fonts but blocks external stylesheets), falling back to `system-ui`.

---

## Steps

1. Environment: `streamlit==1.52.2` and Plotly 5.x in `.venv`; `app/requirements.txt`
   (local) and `app/environment.yml` (SiS Conda) pinned to the same versions;
   `app/.streamlit/config.toml` base theme.
2. `app/ui/theme.py`: light/dark tokens, the injected CSS (font, surfaces, widget
   restyling via `st-key-*` classes), and a Plotly layout per theme.
3. `app/ui/components.py`: small HTML builders (cards, chips, icons) and the clickable
   tile pattern (a keyed container whose Streamlit button covers the card).
4. `app/ui/charts.py`: Plotly figures (dumbbell, focus bar chart, answer mini-chart)
   following the dataviz skill (single hue, hairline grid, direct labels, zero baseline).
5. `app/ui/screens/*.py`: one module per screen, each calling only `utils.forge_data`.
6. `app/streamlit_app.py`: page config, session state, header nav, theme switch,
   screen routing, fallback notices shown as toasts.
7. `tests/unit/test_app_smoke.py`: Streamlit `AppTest` renders every screen in both
   themes without exceptions.

---

## Gate

- `pytest tests/unit` passes (C02 tests + app smoke tests)
- `streamlit run streamlit_app.py` (from `app/`) serves every screen in mock mode, in
  light and dark
- Explore: invalid breakdowns disabled with a reason; clicking a bar focuses it; table view works
- Same for everyone: three persona values identical; masking chips follow contract §6
- Ask: all 8 suggested questions answer with chart, SQL and definition
- No source-schema query outside `get_naive_otd()` (contract §8)

---

## Revision 2 (2026-09-24, after user review) ✅

**User feedback:** the built app looked older and more cramped than the approved Claude
Design prototype. Specifically: the Ask bar and components looked old-fashioned, screens
weren't full width, too much was forced onto one screen, and header menu clicks only
worked around the text, not on it. The user chose "build straight away" for Ask and The
fix, with no separate design approval (they were away).

**Root cause:** stock Streamlit widgets (expanders, dataframes, chat input) can only be
restyled so far. The prototype was hand-built HTML.

**Plan:**
1. Rebuild The problem, The fix, Same for everyone, Explore and Data health as
   **self-contained HTML views** ported from prototype C (`app/ui/views/*.html`, shared
   `base.css`/`base.js`), embedded with `st.components.v1.html`. That's Components v1,
   which SiS supports; everything is inlined, with no external scripts. All in-screen
   interaction (tiles, bar focus, table toggle, drawers) runs client-side on data
   prepared by `app/ui/payloads.py` from `forge_data`.
2. Full-width layout everywhere.
3. Ask stays native (it needs a server round trip) but is redesigned: an empty state with
   question cards, each answer as one card with the number first, an SVG mini chart and
   tabs (Answer / SQL / Definition / Raw), chips above a rounded composer.
4. More of the problem statement in the story: Planning 79.4% vs Logistics 87.1% ("nobody
   trusts the numbers"), the four layers (Source → Governed → Semantic → Agent + app), and
   the ontology chain Supplier → Part → Plant → Shipment → Order → Customer.
5. Header click bug fixed: Streamlit's invisible fixed top bar was covering the menu.
   Verified with Playwright.
6. Contract v1.2 applied: Q8 is now "Which plants have the worst on-time delivery?";
   `SP_METRICS_AS_*` procedures are official (CR-002 and CR-003 accepted).
7. Every screen screenshotted with Playwright (webapp-testing skill) in light and dark
   before handing back.

### Revision 2: what was actually built
- `app/ui/views/`: `base.css`, `base.js` and one HTML view each for problem, fix, same,
  explore, health and answer. `app/ui/view.py` inlines the CSS, JS, data and theme into
  `st.components.v1.html`. `app/ui/payloads.py` builds each view's data from `forge_data`
  (cached 5 minutes per data mode).
- Native parts: the header (brand, story steps, tools, theme switch), the "next" buttons,
  and the Ask screen: 8 question cards, then answer cards, "Try another" chips and a
  rounded composer.
- Removed: the Plotly charts, the native screen modules for the five rebuilt screens, and
  `plotly` from `requirements.txt` / `environment.yml`.
- View heights are fixed per screen: the content height measured in a browser plus a
  margin. Explore is sized for its tallest breakdown (12 plants) and has no button below it.
- In-browser checks: drawer open, filter and close; layer click; metric tiles update all
  three cards; bar focus; table view; impossible breakdowns disabled; question card →
  answer card; SQL and Definition tabs. The Playwright scripts used are in the session
  scratchpad, not committed; C04 can adopt them.

**Deploy risk (SiS):** the views use inline `<script>` inside Components v1 iframes. The
SiS CSP blocks external scripts and `eval`, which these views don't use. If Snowflake still
blocks inline scripts, the fallback is the Revision 1 native screens (in git history).
Verify at B15.

## Decisions made during the build

| Decision | Why |
|----------|-----|
| Theme switch = our own `st.toggle` + re-injected CSS | Streamlit can't change its theme from code. Custom HTML and charts read the same tokens. |
| Clickable tiles = keyed container + invisible full-size `st.button` | Keeps real keyboard focus and a screen-reader label while looking like a card. |
| Tables drawn as HTML, not `st.dataframe` | `st.dataframe` is canvas-drawn and ignores our dark theme. |
| Single-number agent answers get no chart | A one-bar chart is a dataviz anti-pattern; the number is shown as text. |
| Explore uses zero-baseline bars with an "Overall" line; click focuses a bar | Honest magnitudes; emphasis form (selected blue, others muted). |
| Font via `@font-face` from fonts.gstatic.com | The SiS CSP allows fonts but blocks external stylesheets. |
| AppTest can't drive single-select `st.pills` | The Ask test preloads answers through the same `ask_agent()` call. |

## On completion ✅

1. ✅ `.agents/NEXT.md`: C03 ticked, C04 NEXT
2. ✅ `.agents/HANDOFF.md`: app structure, deploy files for B15
3. ✅ `docs/SESSION_LOG.md`: Session 10
4. ✅ This card updated
