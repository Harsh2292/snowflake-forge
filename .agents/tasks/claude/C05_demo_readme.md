# C05 — Demo script, talking points and README

| | |
|---|---|
| **Owner** | Claude Code (writes); CoCo reviews the Snowflake setup section of the README |
| **Milestone** | M6 (Demo script rehearsed to 5 minutes; Submission README) |
| **Prerequisite** | C03 ✅ (the app), C04 ✅, C6a ✅. Pass 2 also needs C6b/C6c and B15 (app live in Snowflake) |
| **Est. effort** | Pass 1: one session. Pass 2: half a session |
| **Writes** | `demo/demo_script.md` (rewrite), `demo/talking_points.md` (new), `README.md` (new, repo root), `demo/screenshots/*.png` + `demo/capture_screenshots.py` (new) |
| **Status** | ⏸ **PLANNED, DEFERRED** 2026-09-28. The user decided C05 runs **after all other tasks are complete** (C6b, C6c, and CoCo through B15). Then both passes run back to back, and approval is asked again at that point. |

---

## Goal

A judge who spends 90 seconds on the repo understands the problem, the fix and the proof.
The user can record a 5-minute video by following a script, with the exact clicks,
questions and numbers, and no surprises.

---

## Why

- **Judging criteria (COCO.md):** Real World Relevance, Technical Execution and Solution
  Completeness. MILESTONES M6 exit: *every judging criterion has a specific moment in the
  demo that addresses it.* The script is built around that.
- **The old `demo/demo_script.md` is out of date.** It describes a persona dropdown, tabs
  and a "Consistency Proof" tab that no longer exist (C03 Revision 2 is a guided story),
  and column names that aren't in the data (`ORD_DLV_DT`). Recorded as written, the video
  would not match the app.
- **There is no `README.md`.** That is the first thing a judge opens.
- **The user has about 4 working days (30 Sep – 3 Oct)**, including recording. Writing
  everything now, while CoCo does B08, means the last days only need numbers swapped
  and a rehearsal.

---

## Steps

### Pass 1: now, in parallel with CoCo's B08

1. **`demo/demo_script.md`**: a timed walk through the real app screens. Each beat has
   *what to click*, *what to say* (one or two sentences), *the number to point at* and
   *which judging criterion it serves*.

   | Time | Screen | The moment |
   |---|---|---|
   | 0:00–0:35 | 1 The problem | Is on-time delivery **78.4% or 87.4%**? Four systems, two promised dates (`ERDAT` vs `PROM_DLV_DT`), 160 of 800 orders in conflict |
   | 0:35–1:15 | 2 The fix | Source → Governed → Semantic → Conversation. Metrics defined once; the ontology |
   | 1:15–2:15 | 3 Same for everyone | Three teams, one number to 6 decimals. Open the rows drawer: same record, different masking. Why procedures, not `USE ROLE` |
   | 2:15–3:30 | 4 Ask | Two canonical questions (SQL, definition, verified query shown), then one tricky one (out of scope, or an impossible breakdown) |
   | 3:30–4:00 | Explore metrics | An impossible breakdown is switched off, with the reason |
   | 4:00–4:25 | Data health | DMF checks, all passing |
   | 4:25–5:00 | Under the hood | CI badge and green tests, semantic view / agent in Snowsight, MCP server (if B14 is done). Close with the claim |

   Plus:
   - A **numbers table**: every number spoken in the video, its source artifact, and
     whether it is final.
   - A **before recording checklist**: live mode, warehouse warmed up, browser width,
     theme, starting screen, closed drawers, cleared chat.
   - A **plan B** if the agent is slow or fails on camera.
2. **`demo/talking_points.md`**: one short answer per judging criterion, plus crisp
   answers to likely judge questions:
   - Why owner's-rights procedures and not `USE ROLE`?
   - How do you know the numbers match?
   - What stops a wrong breakdown?
   - Is the data real?
   - What does the MCP server add?
3. **`README.md`** (repo root), written for a 90-second skim:
   - One-line pitch, CI badge, and one hero screenshot.
   - The problem in three sentences, and the fix as a Mermaid architecture diagram
     (GitHub renders it; no image to keep in sync).
   - **The proof**: the three claims (same number, different visibility, one source
     query), each with where it is shown and which test proves it.
   - What's in Snowflake: an objects table linking to `sql/`, `semantic/`, `agent/`, `mcp/`.
   - How to run it:
     - The Snowflake setup order (from CoCo's `sql/` files; CoCo reviews it).
     - App deploy (`deploy/deploy_app.py`).
     - Local practice mode.
     - Tests.
   - Repo map, and how it was built: two agents, one frozen contract, artifacts as the
     handoff.
   - Honest notes: synthetic data, and what is mock until live.
4. **`demo/capture_screenshots.py`**: reuses the Playwright driver from `tests/ui/` to
   save 4–5 README screenshots to `demo/screenshots/` at 1600 px in light mode. Pass 1
   uses practice data, which is labelled "Mock data" in the header.

### Pass 2: after C6b/C6c and B15 (app live in Snowflake)

5. Swap in the final numbers from art 05/06/09 (the numbers table says which ones). Check
   that the deployed app runs on live data: `USE_MOCK_DATA` in `app/utils/config.py` is
   still `True` today and is flipped in C6b/C6c. Otherwise the video shows the
   "Mock data" badge.
6. Retake the screenshots from the live app (the script, or the user in Snowsight).
7. **Rehearse**: run the script end to end against the live app and time it, then trim
   to 5:00 or less. Record the timing and any fixes here.

Not in scope:
- Recording or editing the video (the user does this).
- Slides.
- Changes to the app, unless the rehearsal finds a bug. That gets its own fix and a note
  here.

---

## Gate

- **Pass 1:** a stranger can follow `demo_script.md` against the local app (practice
  mode) click by click; every judging criterion has at least one named moment. The
  README renders on GitHub (Mermaid included) and every link in it resolves. The numbers
  table lists every spoken number with its source. `pytest -q` and `pytest -m ui` are
  still green.
- **Pass 2:** every number in the script and README equals its artifact. One timed run
  on the live app is at most 5:00 with no failure.

---

## Open questions for the user

1. **Submission rules from the Hack2Skill page:**
   - the video length limit
   - where it's uploaded (YouTube, Drive, …)
   - the deadline date, time and time zone
   - whether the README or repo must be public or include set sections
2. **Voice:** you narrate live while clicking (the script is written for this), or record
   the screen and voice over it later?

---

## On completion

1. This card
2. `.agents/NEXT.md` (C05 ✅, with pass 1 and pass 2 noted)
3. `.agents/HANDOFF.md` ("Latest from Claude Code"): ask CoCo to review the README's
   Snowflake section and the "under the hood" beat
4. `docs/SESSION_LOG.md`
5. `.agents/tasks/README.md` "Written:" list
