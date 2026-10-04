"""One MP3 per scene line with a free Microsoft neural voice (edge-tts), plus durations."""
import asyncio
import json
import subprocess
import sys
from pathlib import Path

import edge_tts

OUT = Path(__file__).parent / "audio"
OUT.mkdir(exist_ok=True)
VOICE = sys.argv[1] if len(sys.argv) > 1 else "en-US-AndrewNeural"
RATE = "+4%"

LINES = {
    "s1": "Ask a supply chain team one simple question: what is our on-time delivery rate? And you get two answers. Planning says sixty-eight percent. Logistics says eighty-seven and a half. Same shipments. Four systems, four versions of the truth.",
    "s2": "Supply Chain Forge fixes this in Snowflake. Messy data from ERP, warehouse, transport and supplier systems is cleaned, governed, and described once in a semantic view: our supply chain ontology. Every metric has one definition, and everything reads from it.",
    "s3a": "This was built, and is operated, with CoCo CLI. First, the data-quality skill. The input is a plain request. CoCo runs our data-health procedure in Snowflake, and reports back: every table fresh, every check passing.",
    "s3b": "Second, the data-governance skill. CoCo computes all four metrics as the planner, the buyer, and the logistics coordinator, each under its own access rules. The numbers are identical to six decimal places, but each role sees different details: the buyer can't see customer names, and the planner can't see contract prices.",
    "s3c": "Third, the agent-studio skill, and our Cortex Agent. CoCo asks the agent a question in plain English. The agent uses Cortex Analyst on the semantic view, writes the SQL, and answers with the five suppliers. Input, processing, output. All governed.",
    "s4a": "The same proof is in the app. Three teams, three access rules, and one number, identical to six decimal places, for everyone.",
    "s4b": "Anyone can ask in plain English. Known metric questions answer instantly from the semantic view, with no AI call at all. Everything else goes to the Cortex Agent, which streams its answer with a chart, and shows exactly which SQL it ran.",
    "s5": "And the data is watched all the time. Seventy-seven Data Metric Functions check every load for duplicates, bad codes and missing dates, so a bad load is caught before it reaches an answer.",
    "s6": "The result: one trusted number for every team, answered in seconds, with governance enforced by Snowflake itself. The agent scores twenty-eight out of thirty on our evaluation set, and the whole system rebuilds from the repository with no manual fixes. Try it yourself, at supply-chain-forge dot streamlit dot app.",
}


async def main():
    for key, text in LINES.items():
        await edge_tts.Communicate(text, VOICE, rate=RATE).save(str(OUT / f"{key}.mp3"))
    durations = {}
    for key in LINES:
        d = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0",
                            str(OUT / f"{key}.mp3")], capture_output=True, text=True).stdout.strip()
        durations[key] = round(float(d), 2)
    (OUT / "durations.json").write_text(json.dumps(durations, indent=1))
    print(json.dumps(durations), "total", round(sum(durations.values()), 1))


asyncio.run(main())
