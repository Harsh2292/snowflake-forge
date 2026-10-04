# Video shot list: what to record, and what the voice says

## Step 0: brief CoCo first (don't record this)

Paste this into CoCo CLI before recording. It explains the plan, checks every object, and runs
each step once, so the recorded run is quick and clean. Wait until CoCo answers READY.

```
Context: I'm recording a 4-minute demo video of Supply Chain Forge for the Snowflake CoCo CLI
Hackathon. In the recording I will paste three prompts, one at a time. Each one asks you to use
one skill and run one read-only step in Snowflake. Before we record, please prepare.

Rules for this session (now and during the recording):
1. Read-only. Do not create, alter, drop, grant or insert anything, and do not edit any file.
2. Always use connection QURFOQP-XU04029, role FORGE_ADMIN, warehouse FORGE_WH, database
   SUPPLY_CHAIN_FORGE.
3. Keep every answer short and readable on screen: start with one line naming the skill you are
   using, then the result as a small table, then at most two lines of summary. No long
   explanations, no extra queries beyond what the prompt asks.

Preparation, now:
a. List your available skills and tell me the exact names that match these three:
   data-quality, data-governance, agent-studio. If a name differs, tell me the real one.
b. Dry-run the three steps once, silently, and tell me only whether each worked:
   - CALL SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH('ALL');
   - CALL SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_PLANNER(); and the same for _BUYER and _LOGISTICS;
     then SP_SAMPLE_AS_PLANNER() and SP_SAMPLE_AS_BUYER()
   - ask the Cortex Agent SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT, through
     SNOWFLAKE.CORTEX.DATA_AGENT_RUN as in docs/CONTRACT.md section 5.3 (bind the whole request
     JSON as one parameter): "List the top 5 suppliers in EMEA with the shortest lead times"
c. Reply with one line per step (OK, or the exact error), the skill names from (a), and the
   word READY when everything works.
```

If CoCo gives different skill names in (a), swap them into the three prompts below before
recording. Once it says READY, start recording and paste prompt 1.

About 4 minutes 10 seconds in total. Record each scene as its own clip; afterwards put the
matching voice line under each clip. The scene timings are for the finished, edited video.

The app is at https://supply-chain-forge.streamlit.app/ (light theme, every screen opened once
beforehand so nothing loads slowly on camera).

---

## Scene 1: The problem (0:00–0:20)

**Show**
- 0:00: The live app, **The problem** screen, at the top. Keep still for 2 seconds.
- 0:06: Move the mouse slowly across the four system cards (ERP, WMS, TMS, SRM).
- 0:12: Hover over **68.2%**, then **87.5%**, in the bottom card.

**Voice**
> Ask a supply chain team one simple question, what is our on-time delivery rate, and you get two answers. Planning says sixty-eight percent. Logistics says eighty-seven and a half. Same shipments. Four systems, four versions of the truth.

---

## Scene 2: The fix (0:20–0:40)

**Show**
- 0:20: Click **The fix** in the top bar.
- 0:24: Hover down the left column: Source → Governed → Semantic → Conversation.
- 0:32: Scroll down a little to the four metric cards ("Four metrics, each defined once").

**Voice**
> Supply Chain Forge fixes this in Snowflake. Messy data from ERP, warehouse, transport and supplier systems is cleaned, governed, and described once in a semantic view, our supply chain ontology. Every metric has one definition, and everything reads from it.

---

## Scene 3a: CoCo CLI, data-quality skill (0:40–1:15)

**Show**
- 0:40: Switch to the **CoCo CLI terminal**. Paste prompt 1 (below) and press Enter.
- 0:48: CoCo picks the skill and runs `SP_DATA_HEALTH`. Cut the waiting in the edit.
- 1:00: CoCo's summary table appears: status OK, as-of date, every entity fresh. Hold it for
  5 seconds.

**Prompt 1 (paste exactly)**
```
Use the data-quality skill. Read-only: do not create, alter or drop anything.
On connection QURFOQP-XU04029, run CALL SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH('ALL');
as role FORGE_ADMIN on warehouse FORGE_WH. Summarise in a short table: overall status,
as-of date, each entity's freshness and row count, and any check that is not OK.
```

**Voice**
> This was built and is operated with CoCo CLI. First, the data-quality skill. The input is a plain request. CoCo runs our data-health procedure in Snowflake and reports back: every table fresh, every check passing.

---

## Scene 3b: CoCo CLI, data-governance skill (1:15–1:55)

**Show**
- 1:15: Paste prompt 2 and press Enter.
- 1:22: CoCo calls the three persona procedures (cut the waiting).
- 1:35: The side-by-side table: four metrics × Planner / Buyer / Logistics, all identical. Hold it.
- 1:45: Scroll to the masked-columns list (Buyer: customer names masked; Planner: contract
  price hidden).

**Prompt 2 (paste exactly)**
```
Use the data-governance skill. Read-only: do not create, alter or drop anything.
On connection QURFOQP-XU04029 as FORGE_ADMIN, call SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_PLANNER(),
SP_METRICS_AS_BUYER() and SP_METRICS_AS_LOGISTICS(). Show the four metrics side by side, one column
per role, to 6 decimal places, and say whether they are identical. Then call SP_SAMPLE_AS_PLANNER()
and SP_SAMPLE_AS_BUYER() and list which columns each role sees masked or hidden.
```

**Voice**
> Second, the data-governance skill. CoCo computes all four metrics as the planner, the buyer and the logistics coordinator, each under its own access rules. The numbers are identical to six decimal places, but each role sees different details: the buyer can't see customer names, the planner can't see contract prices.

---

## Scene 3c: CoCo CLI, agent-studio skill and the Cortex Agent (1:55–2:25)

**Show**
- 1:55: Paste prompt 3 and press Enter.
- 2:02: CoCo calls the agent (cut the waiting; the agent takes 15–35 s).
- 2:12: The agent's answer: 5 suppliers with their lead times. Then scroll to the generated SQL
  (`FROM SEMANTIC_VIEW(...)` or the view name).

**Prompt 3 (paste exactly)**
```
Use the agent-studio skill. Read-only: do not create, alter or drop anything.
On connection QURFOQP-XU04029, ask the Cortex Agent SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT
this question through SNOWFLAKE.CORTEX.DATA_AGENT_RUN as in docs/CONTRACT.md section 5.3:
"List the top 5 suppliers in EMEA with the shortest lead times".
Show the agent's answer text, the tools it used, and the SQL it generated on the semantic view.
```

**Voice**
> Third, the agent-studio skill and our Cortex Agent. CoCo asks the agent a question in plain English. The agent uses Cortex Analyst on the semantic view, writes the SQL, and answers with the five suppliers. Input, processing, output, all governed.

---

## Scene 4a: Same for everyone, in the app (2:25–2:50)

**Show**
- 2:25: Back to the browser. Click **Same for everyone**.
- 2:30: Hover over the three persona cards: all show the same number and "Matches".
- 2:38: Hover over "What this team can see" (the ticks and locks differ per team).
- 2:44: Click the **Fill Rate** card at the top: all three numbers change together and still match.

**Voice**
> The same proof is in the app. Three teams, three access rules, and one number, identical to six decimal places, for everyone.

---

## Scene 4b: Ask (2:50–3:25)

**Show**
- 2:50: Click **Ask**. If an old conversation shows, click **New conversation**.
- 2:53: Click the suggested question **"What is on-time delivery rate by region?"**. It answers in
  about 1 second ("Instant answer · governed semantic view") with a bar chart.
- 3:00: Type: **List the top 5 suppliers in EMEA with the shortest lead times** and press Enter.
- 3:03: The "Thinking" card, then the answer streams in. Cut the wait so this part is about
  10 seconds.
- 3:15: The answer shows 5 suppliers listed and a bar chart. Click the **SQL** tab for 3 seconds.

**Voice**
> Anyone can ask in plain English. Known metric questions answer instantly from the semantic view, with no AI call at all. Everything else goes to the Cortex Agent, which streams its answer with a chart, and shows exactly which SQL it ran.

---

## Scene 5: Data health (3:25–3:45)

**Show**
- 3:25: Click **Data health**. Hold on "35 of 35 checks passing" (or whatever the live count is).
- 3:30: Scroll slowly down the checks, then to "Freshness by table" at the bottom.

**Voice**
> And the data is watched all the time. Seventy-seven Data Metric Functions check every load for duplicates, bad codes and missing dates, so a bad load is caught before it reaches an answer.

---

## Scene 6: Close (3:45–4:10)

**Show**
- 3:45: The deck's **Impact** slide, full screen (PowerPoint slide show, or the PDF at full
  screen).
- 4:00: Back to the live app, **The problem** screen, with the address bar visible. End on that.

**Voice**
> The result: one trusted number for every team, answered in seconds, with governance enforced by Snowflake itself. The agent scores twenty-eight out of thirty on our evaluation set, and the whole system rebuilds from the repository with no manual fixes. Try it yourself at supply-chain-forge dot streamlit dot app.

---

## What the judges need to see (the form's checklist)

| The form asks for | Where it is in the video |
|---|---|
| An end-to-end workflow run through CoCo CLI | Scenes 3a–3c: prompts typed into CoCo, run in Snowflake, results shown |
| Input → Processing → Output | Each CoCo prompt (input), CoCo and Snowflake working (processing), the table or answer (output); the same in Ask (scene 4b) |
| At least one fully working workflow | The question → agent → semantic view → SQL → answer, in CoCo (3c) and in the app (4b) |
| 2–3 modular skills or capabilities | data-quality (3a), data-governance (3b), agent-studio and the Cortex Agent (3c) |
| 3 to 5 minutes | About 4:10 |
