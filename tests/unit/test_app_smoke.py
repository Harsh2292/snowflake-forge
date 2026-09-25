"""C03 gate: every screen renders without exceptions, in light and dark; navigation and the
Ask flow work; each HTML view gets well-formed data.

Uses Streamlit's headless AppTest (no browser). The in-view JavaScript is checked
separately in a real browser by tests/ui (pytest -m ui).
"""

import json
from pathlib import Path

import pytest
from streamlit.testing.v1 import AppTest

from utils import config, forge_data
from ui import payloads, theme, view

APP = Path(__file__).resolve().parents[2] / "app" / "streamlit_app.py"

SCREENS = ["problem", "fix", "same", "ask", "explore", "health"]


def run_app(**state) -> AppTest:
    at = AppTest.from_file(str(APP), default_timeout=30)
    for key, value in state.items():
        at.session_state[key] = value
    at.run()
    assert not at.exception, at.exception
    return at


@pytest.fixture(autouse=True)
def fresh_cache():
    import streamlit as st
    st.cache_data.clear()


@pytest.mark.parametrize("dark", [False, True])
@pytest.mark.parametrize("step", SCREENS)
def test_every_screen_renders(step, dark):
    run_app(step=step, dark=dark)


@pytest.mark.parametrize("step", SCREENS)
def test_header_navigation_reaches_every_screen(step):
    at = run_app(step="problem")
    at.button(key=f"nav_{step}").click().run()
    assert not at.exception
    assert at.session_state.step == step


def test_next_buttons_follow_the_story():
    at = run_app(step="problem")
    for current, expected in [("problem", "fix"), ("fix", "same"), ("same", "ask")]:
        at.button(key=f"next_{current}").click().run()
        assert at.session_state.step == expected


def test_ask_starts_with_eight_question_cards_and_one_click_answers():
    at = run_app(step="ask")
    cards = [b for b in at.button if b.key and b.key.startswith("qcard_")]
    assert [b.label for b in cards] == config.CANONICAL_QUESTIONS
    at.button(key="qcard_1").click().run()
    assert not at.exception
    assert len(at.session_state.chat) == 1
    assert at.session_state.chat[0]["result"]["sql"]


def test_ask_renders_every_answer_and_can_start_over():
    chat = [{"question": q, "result": forge_data.ask_agent(q)} for q in config.CANONICAL_QUESTIONS]
    at = run_app(step="ask", chat=chat)
    at.button(key="ask_clear").click().run()
    assert at.session_state.chat == []


# ── The data handed to each HTML view ────────────────────────────────────────

@pytest.mark.parametrize("name", ["problem", "fix", "same", "explore", "health"])
def test_view_documents_embed_valid_json(name):
    data = getattr(payloads, name)("mock")
    document = view.build(name, data, theme.LIGHT)
    raw = document.split('id="forge-data">')[1].split("</script>")[0]
    assert json.loads(raw.replace("<\\/", "</")) == json.loads(json.dumps(data, default=str))
    assert "--page:#EDF1F6" in document


def test_problem_payload_tells_the_two_answers_story():
    data = payloads.problem("mock")
    assert [s["code"] for s in data["systems"]] == ["ERP", "WMS", "TMS", "SRM"]
    assert data["naive"] != data["governed"]
    assert len(data["catalog"]) > 60


def test_explore_payload_follows_contract_pairings():
    data = payloads.explore("mock")
    for key, items in data["breakdowns"].items():
        for item in items:
            dimension = next(b[3] for b in payloads.BREAKDOWNS if b[0] == item["id"])
            assert item["allowed"] == (dimension in config.VALID_PAIRINGS[key])
            assert bool(item["rows"]) == item["allowed"]
            assert bool(item["reason"]) == (not item["allowed"])


def test_same_payload_marks_masking_per_persona():
    data = payloads.same("mock")
    seen = {p["label"]: {c["label"]: c["visible"] for c in p["visibility"]} for p in data["personas"]}
    assert seen["Procurement Lead"] == {"Customer names": False, "Unit cost": True, "Payment terms": True, "Credit limit": False}
    assert seen["Production Planner"]["Unit cost"] is False
    assert all(row["identical"] for row in data["grid"].values())


def test_answer_payload_has_chart_only_for_breakdowns():
    overall = payloads.answer("q", forge_data.ask_agent(config.CANONICAL_QUESTIONS[0]))
    by_region = payloads.answer("q", forge_data.ask_agent(config.CANONICAL_QUESTIONS[1]))
    assert overall["chart"] is None  # a single number is never a one-bar chart
    assert len(by_region["chart"]["rows"]) == 3
    assert by_region["definitions"][0]["label"] == "On-Time Delivery"
