"""C6c: the live Ask path against the real agent's output, offline.

- art 07 (B10): one full DATA_AGENT_RUN response. The replay session answers the app's
  agent call with it, and fails unless the bound value is the CR-007 request JSON.
- art 08 (B10): all 30 evaluation answers (text, SQL, tools). Each one must parse and fit
  the answer card: prose only in the answer, the SQL in its own tab, no internal tools shown.
"""

import json
import re
from pathlib import Path

import pytest
import streamlit as st
from streamlit.testing.v1 import AppTest

from ui import payloads
from utils import agent_response, config, forge_data

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app" / "streamlit_app.py"


# ── art 07: the whole live path ──────────────────────────────────────────────

@pytest.mark.parametrize("forge", ["replay"], indirect=True)
class TestLiveAsk:

    def test_the_bound_request_is_the_cr007_json(self, forge):
        question = config.CANONICAL_QUESTIONS[1]
        result = forge.ask_agent(question)
        session = forge_data.get_session()
        assert session.agent_requests == [forge_data.agent_request(question)]
        assert json.loads(session.agent_requests[0])["messages"][0]["content"][0]["text"] == question
        assert result["source"] == "live"

    def test_the_answer_card_shows_what_the_agent_returned(self, forge):
        result = forge.ask_agent(config.CANONICAL_QUESTIONS[1])
        card = payloads.answer(config.CANONICAL_QUESTIONS[1], result)
        assert card["answer"].startswith("On-time delivery rate for the last 12 months")
        assert "```" not in card["answer"] and "SELECT" not in card["answer"]
        assert card["sql"].startswith("SELECT * FROM SEMANTIC_VIEW(") and "plants.plant_region" in card["sql"]
        assert card["verified"] and card["tools"] == [] and not card["practice"]
        assert card["metrics"] == ["On-Time Delivery"]
        assert card["chart"]["title"] == "On-Time Delivery Rate by Region"
        assert {r["label"] for r in card["chart"]["rows"]} == {"AMER", "APAC", "EMEA"}
        assert len(result["tables"]) == 1 and len(result["suggestions"]) == 3

    def test_the_ask_screen_runs_live_with_no_fallback(self, forge):
        st.cache_data.clear()
        st.cache_resource.clear()
        at = AppTest.from_file(str(APP), default_timeout=30)
        at.secrets["forge"] = {"shortcut": False}  # the agent path (the shortcut: test_router.py)
        at.session_state["step"] = "ask"
        at.run()
        at.button(key="qcard_1").click().run()
        turn = at.session_state["chat"][0]
        assert turn["parts"][0]["result"]["source"] == "live"
        page = "\n".join(m.value for m in at.markdown)
        assert 'data-source="mock_fallback"' not in page  # the C15 banner: nothing fell back
        # "Try another" leads with the agent's own follow-ups
        pills = at.button_group[0] if at.button_group else None
        options = pills.options if pills is not None else []
        assert any("carriers" in str(o) for o in options)


# ── art 08: every evaluation answer ──────────────────────────────────────────

def _art08() -> list[dict]:
    path = ROOT / "docs" / "artifacts" / "08_agent_answers.md"
    if not path.exists():
        pytest.skip("art 08 not captured yet")
    text = path.read_text(encoding="utf-8")
    tools = {m[0]: m[1] for m in re.findall(r"^\| (Q\d\d) \|(?:[^|]*\|){5} ([^|]*) \|$", text, re.M)}
    answers = []
    for block in re.split(r"^### ", text, flags=re.M)[1:]:
        qid = block.split(" ", 1)[0]
        if not re.fullmatch(r"Q\d\d", qid):
            continue
        answer = re.search(r"\*\*Answer\*\*:\s*````text\n(.*?)\n````", block, re.S)
        sql = re.search(r"\*\*Agent SQL\*\*[^\n]*\n\s*````sql\n(.*?)\n````", block, re.S)
        answers.append({"id": qid, "category": block.split(" · ")[1],
                        "question": re.search(r"\*\*Question\*\*: (.*)", block).group(1),
                        "answer": answer.group(1) if answer else "",
                        "sql": sql.group(1).strip() if sql else "",
                        "tools": [t.strip() for t in tools.get(qid, "").split(",") if t.strip() not in ("", "—")]})
    return answers


ART08 = _art08() if (ROOT / "docs" / "artifacts" / "08_agent_answers.md").exists() else []


def _response(a: dict) -> dict:
    """The answer rebuilt in art 07's shape: the tools it used, its SQL, its verbatim text."""
    content = [{"type": "tool_use", "tool_use": {"name": t, "type": t, "input": {}}} for t in a["tools"]]
    if a["sql"]:
        first = a["sql"].split("\n\n")[0].strip()
        content.append({"type": "tool_result", "tool_result": {"name": "system_execute_sql", "content": [
            {"type": "json", "json": {"sql": first, "query_id": "q"}}]}})
    content.append({"type": "text", "text": a["answer"]})
    return {"role": "assistant", "content": content, "status": "completed"}


def test_art08_has_all_30_answers():
    assert [a["id"] for a in ART08] == [f"Q{n:02d}" for n in range(1, 31)]


@pytest.mark.parametrize("a", ART08, ids=[a["id"] for a in ART08])
def test_every_real_answer_parses_and_fits_the_card(a):
    parsed = agent_response.parse_agent_response(_response(a))
    card = payloads.answer(a["question"], {**parsed, "source": "live"})
    assert card["answer"].strip() and card["answer"] != "The agent returned no text."
    assert "```" not in card["answer"], "a code block leaked into the answer"
    assert not any(t.startswith("system_") for t in card["tools"]), card["tools"]
    json.dumps(card)  # travels to the browser as JSON
    if a["category"] in ("OUT_OF_SCOPE", "AMBIGUOUS", "CROSS_GRAIN") or not a["sql"]:
        assert card["chart"] is None  # a refusal or clarifying question: text only
    else:
        assert card["sql"], "the SQL tab would be empty"


def test_the_data_health_answer_names_its_tool():
    q29 = next(a for a in ART08 if a["id"] == "Q29")
    parsed = agent_response.parse_agent_response(_response(q29))
    assert parsed["tools_used"] == ["Data health check"]
