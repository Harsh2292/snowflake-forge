# Demo video script: Supply Chain Forge

**Length:** about 4 minutes; the form allows 3 to 5.
**The form asks for** an end-to-end workflow run through **CoCo CLI**, recorded on screen as
**Input → Processing → Output**, with at least one fully working workflow and 2–3 modular
skills shown.
**This script covers that:**
- Scene 3 is the CoCo CLI workflow, with three skills: **data-quality**, **data-governance** and
  **agent-studio** (the Cortex Agent).
- Scenes 4–5 show the same governed output in the live app.

Live link: https://supply-chain-forge.streamlit.app/

---

## Before you record (15 minutes)

1. **The agent is fixed.** Run all of `agent/01_agent.sql` in Snowsight as `FORGE_ADMIN` if you
   haven't (5 statements). Then, on the live link, ask *"List the top 5 suppliers in EMEA with
   the shortest lead times"*: you should see 5 listed suppliers and a bar chart.
2. **Warm the app.** Open the live link and click through every screen once, so nothing loads
   slowly on camera. Leave it in the **light** theme.
3. **Dry-run scene 3 in CoCo CLI.** Paste the three prompts once before recording. CoCo's
   wording varies from run to run; the dry run shows you how long each one takes, so you can
   cut the waiting in the edit.
4. **Screen setup:** 1920×1080, browser zoom 100%, terminal font 16 pt or bigger, notifications
   off (Windows: Focus assist on).
5. **Recorder:** OBS Studio (free), or Windows **Win + Alt + R** (Xbox Game Bar), or the Snipping
   Tool's video mode. Record each scene as its own clip; that makes editing easy.

---

## The scenes

Timings are for the finished video. The voice-over is in the last column; the same text, in
one block for the voice tool, is at the end of this file.

| # | Time | On screen | Voice-over |
|---|---|---|---|
| 1 | 0:00–0:20 | Live app, **The problem** screen. Hover the 68.2% and 87.5% numbers | "Ask a supply chain team one simple question, *what is our on-time delivery rate?*, and you get two answers. Planning says sixty-eight percent. Logistics says eighty-seven and a half. Same shipments. Four systems, four versions of the truth." |
| 2 | 0:20–0:40 | **The fix** screen. Point at Source → Governed → Semantic → Conversation, then the four metric cards | "Supply Chain Forge fixes this in Snowflake. Messy data from ERP, warehouse, transport and supplier systems is cleaned, governed, and described once in a semantic view, our supply chain ontology. Every metric has one definition, and everything reads from it." |
| 3a | 0:40–1:15 | **CoCo CLI terminal.** Paste prompt 1 (below). Show CoCo picking the skill, running the procedure, and printing the summary | "This was built and is operated with CoCo CLI. First, the data-quality skill. The input is a plain request. CoCo runs our data-health procedure in Snowflake and reports back: every table fresh, every check passing." |
| 3b | 1:15–1:55 | Paste prompt 2. Show the side-by-side metrics table and the masked columns | "Second, the data-governance skill. CoCo computes all four metrics as the planner, the buyer and the logistics coordinator, each under its own access rules. The numbers are identical to six decimal places, but each role sees different details: the buyer can't see customer names, the planner can't see contract prices." |
| 3c | 1:55–2:25 | Paste prompt 3. Show the agent's answer and the SQL it wrote on the semantic view | "Third, the agent-studio skill and our Cortex Agent. CoCo asks the agent a question in plain English. The agent uses Cortex Analyst on the semantic view, writes the SQL, and answers with the five suppliers. Input, processing, output, all governed." |
| 4a | 2:25–2:50 | Live app, **Same for everyone**. Click On-Time Delivery, then Fill Rate | "The same proof is in the app. Three teams, three access rules, one number: point eight seven five three six nine for on-time delivery, for everyone." |
| 4b | 2:50–3:25 | **Ask** screen. Click *What is on-time delivery rate by region?* (instant answer, about 1 s). Then type *List the top 5 suppliers in EMEA with the shortest lead times* and let it stream; open the **SQL** tab | "Anyone can ask in plain English. Known metric questions answer instantly from the semantic view, with no AI call at all. Everything else goes to the Cortex Agent, which streams its answer with a chart, and shows exactly which SQL it ran." |
| 5 | 3:25–3:45 | **Data health** screen. Scroll the checks slowly | "And the data is watched all the time. Seventy-seven Data Metric Functions check every load for duplicates, bad codes and missing dates, so a bad load is caught before it reaches an answer." |
| 6 | 3:45–4:10 | Deck slide **Impact** (or the README Results table), then the live link | "The result: one trusted number for every team, answered in seconds, with governance enforced by Snowflake itself. The agent scores twenty-eight out of thirty on our evaluation set, and the whole system rebuilds from the repository with no manual fixes. Try it yourself at supply-chain-forge dot streamlit dot app." |

---

## Scene 3: the CoCo CLI prompts (paste exactly)

Each prompt is read-only, so it's safe to run on camera. Start CoCo CLI in the project folder
as you normally do, on the event-account connection.

**Prompt 1: data-quality skill**
```
Use the data-quality skill. Read-only: do not create, alter or drop anything.
On connection QURFOQP-XU04029, run CALL SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH('ALL');
as role FORGE_ADMIN on warehouse FORGE_WH. Summarise in a short table: overall status,
as-of date, each entity's freshness and row count, and any check that is not OK.
```

**Prompt 2: data-governance skill**
```
Use the data-governance skill. Read-only: do not create, alter or drop anything.
On connection QURFOQP-XU04029 as FORGE_ADMIN, call SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_PLANNER(),
SP_METRICS_AS_BUYER() and SP_METRICS_AS_LOGISTICS(). Show the four metrics side by side, one column
per role, to 6 decimal places, and say whether they are identical. Then call SP_SAMPLE_AS_PLANNER()
and SP_SAMPLE_AS_BUYER() and list which columns each role sees masked or hidden.
```

**Prompt 3: agent-studio skill (the Cortex Agent)**
```
Use the agent-studio skill. Read-only: do not create, alter or drop anything.
On connection QURFOQP-XU04029, ask the Cortex Agent SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT
this question through SNOWFLAKE.CORTEX.DATA_AGENT_RUN as in docs/CONTRACT.md section 5.3:
"List the top 5 suppliers in EMEA with the shortest lead times".
Show the agent's answer text, the tools it used, and the SQL it generated on the semantic view.
```

If CoCo names a skill differently on your machine, keep the rest of the prompt and drop the
"Use the … skill" line; CoCo picks the skill itself. If a step runs long, cut the waiting in the
edit: keep the prompt, the moment it starts working, and the result.

---

## Voice-over, in one block (paste into the voice tool)

About 350 words, roughly 2.5 minutes of speech; the rest of the 4 minutes is on-screen action (CoCo working, clicks). Each paragraph is one scene.

> Ask a supply chain team one simple question, what is our on-time delivery rate, and you get two answers. Planning says sixty-eight percent. Logistics says eighty-seven and a half. Same shipments. Four systems, four versions of the truth.
>
> Supply Chain Forge fixes this in Snowflake. Messy data from ERP, warehouse, transport and supplier systems is cleaned, governed, and described once in a semantic view, our supply chain ontology. Every metric has one definition, and everything reads from it.
>
> This was built and is operated with CoCo CLI. First, the data-quality skill. The input is a plain request. CoCo runs our data-health procedure in Snowflake and reports back: every table fresh, every check passing.
>
> Second, the data-governance skill. CoCo computes all four metrics as the planner, the buyer and the logistics coordinator, each under its own access rules. The numbers are identical to six decimal places, but each role sees different details: the buyer can't see customer names, the planner can't see contract prices.
>
> Third, the agent-studio skill and our Cortex Agent. CoCo asks the agent a question in plain English. The agent uses Cortex Analyst on the semantic view, writes the SQL, and answers with the five suppliers. Input, processing, output, all governed.
>
> The same proof is in the app. Three teams, three access rules, one number: point eight seven five three six nine for on-time delivery, for everyone.
>
> Anyone can ask in plain English. Known metric questions answer instantly from the semantic view, with no AI call at all. Everything else goes to the Cortex Agent, which streams its answer with a chart, and shows exactly which SQL it ran.
>
> And the data is watched all the time. Seventy-seven Data Metric Functions check every load for duplicates, bad codes and missing dates, so a bad load is caught before it reaches an answer.
>
> The result: one trusted number for every team, answered in seconds, with governance enforced by Snowflake itself. The agent scores twenty-eight out of thirty on our evaluation set, and the whole system rebuilds from the repository with no manual fixes. Try it yourself at supply-chain-forge dot streamlit dot app.

---

## Putting voice and video together (free)

1. **Voice:**
   - **ElevenLabs** (free tier, about 10,000 characters a month; this script is about 2,200):
     paste one paragraph at a time, pick a voice, download each MP3. One file per scene makes
     syncing easy.
   - Free alternative: **Clipchamp's** built-in text-to-speech (comes with Windows 11).
2. **Edit in Clipchamp** (free, Windows 11):
   - drop in the screen clips in scene order, then each voice MP3 under its clip
   - trim each clip to its voice line; cut CoCo's waiting time
   - export 1080p
3. **Check the length:** 3 to 5 minutes.
4. **Upload** to YouTube as *Unlisted* (or Google Drive, shared as "Anyone with the link"). Paste
   that link in the form's *Demo video link*.

## The form, in one place

| Field | What to put |
|---|---|
| Prototype/MVP Brief (max 1,024 characters) | The text in `demo/submission/BRIEF.md` (866 characters) |
| Demo video link | Your YouTube or Drive link |
| Prototype deck (PDF, max 5 MB) | `demo/submission/Supply_Chain_Forge_Prototype_Deck.pdf` (0.65 MB) |
