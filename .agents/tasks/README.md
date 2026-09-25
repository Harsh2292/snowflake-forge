# Task Cards

Self-contained work units. Each card is executable in roughly one session and carries its
own gate.

## How to use

1. Read `.agents/NEXT.md` — it names the card to open
2. Open that card and execute it
3. Pass the **Gate** before moving on
4. Update `NEXT.md`, `HANDOFF.md`, and `SESSION_LOG.md` as the card instructs

## Layout

```
.agents/
├── NEXT.md              ← START HERE
├── HANDOFF.md           ← cross-agent state
├── DECISIONS.md         ← ADRs
└── tasks/
    ├── coco/            B01 … B17
    └── claude/          C01 … C06
```

## Card anatomy

| Section | Purpose |
|---------|---------|
| Header table | Owner, milestone, prerequisite, effort, files written |
| **Goal** | One sentence |
| **Why** | Context that prevents wrong shortcuts |
| **Steps** | Ordered, concrete |
| **Gate** | Runnable checks. The card is not done until these pass. |
| **On completion** | Which tracking files to update |

## Cards not yet written

Cards are authored a step or two ahead of execution, so each one can incorporate what was
actually learned from the previous gate rather than guessing.

Written: `B01`, `B02`, `C01`, `C02`, `C03`, `C04`
(Claude Code writes each of its cards at planning time, before executing it.)
Specified in `.agents/tasks/COCO_TASKS.md` and `CLAUDE_TASKS.md` (the full queues), with
exact specs in `docs/LLD.md` and `docs/GAPS_RESOLVED.md`.
