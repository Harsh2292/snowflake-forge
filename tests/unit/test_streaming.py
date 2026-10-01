"""CR-008 (contract v1.7 §5.3b): the agent's answer streamed over the REST agent:run API.

- An SSE fixture built from the real agent response (art 07), split into the documented
  events (docs/references/agent_run_rest.md), parses to exactly the same answer as the §5.3
  DATA_AGENT_RUN path.
- The request reuses the app's session token (no second login).
- Every failure falls back to §5.3; "not authorized" is "Ask is paused".
- The Ask screen streams one agent part; several still run in parallel, unstreamed.
"""

import json
from pathlib import Path
from types import SimpleNamespace

import pytest
import streamlit as st
from streamlit.testing.v1 import AppTest

from utils import agent_response, config, forge_data

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app" / "streamlit_app.py"
ART07 = json.loads((ROOT / "docs" / "artifacts" / "07_agent_response.json").read_text(encoding="utf-8"))
RESPONSE = ART07.get("payload", ART07)


def sse(*events) -> list[bytes]:
    """Wire lines, as requests' iter_lines() yields them."""
    lines = []
    for name, data in events:
        lines += [f"event: {name}".encode(), f"data: {json.dumps(data)}".encode(), b""]
    return lines


def stream_of(response: dict, pieces: int = 5) -> list[bytes]:
    """The documented event sequence for one response: status, its blocks one by one (text
    as deltas, then the completed text), then the final aggregated `response`."""
    events = [("response.status", {"status": "planning", "message": "Planning the next steps"})]
    for item in response["content"]:
        kind = item.get("type")
        if kind == "text":
            text = item["text"]
            size = max(1, len(text) // pieces)
            events += [("response.text.delta", {"content_index": 0, "text": text[i:i + size]})
                       for i in range(0, len(text), size)]
            events.append(("response.text", {"content_index": 0, "text": text}))
        elif kind in ("tool_use", "tool_result", "table"):
            events.append((f"response.{kind}", item[kind]))
        elif kind == "thinking":
            events.append(("response.thinking.delta", {"content_index": 0, "text": "…"}))
    events.append(("response", response))
    return sse(*events)


def texts(response: dict) -> str:
    return "".join(item["text"] for item in response["content"] if item.get("type") == "text")


# ── The wire format ──────────────────────────────────────────────────────────

def test_sse_lines_become_events():
    lines = [b": keep-alive", b"event: response.text.delta", b'data: {"text": "Hel', b'data: lo"}', b"",
             b"event: response.status\r", b'data: {"status": "done"}\r', b"",
             b'data: {"text": "no event name"}']  # the last one has no blank line after it
    assert list(forge_data.sse_events(lines)) == [
        ("response.text.delta", '{"text": "Hel\nlo"}'),
        ("response.status", '{"status": "done"}'),
        ("message", '{"text": "no event name"}')]


def test_the_streamed_answer_equals_the_data_agent_run_answer():
    seen = []
    raw = forge_data.assemble_stream(forge_data.sse_events(stream_of(RESPONSE)), seen.append)
    assert "".join(seen) == texts(RESPONSE)  # the text arrived as it was written
    streamed, direct = agent_response.parse_agent_response(raw), agent_response.parse_agent_response(RESPONSE)
    for field in ("answer", "sql", "metric_used", "verified_query_used", "tools_used", "tables", "suggestions", "status"):
        assert streamed[field] == direct[field], field


def test_without_the_final_event_the_answer_is_interrupted_not_complete():
    """Review #13: no terminal `response` event means the run didn't finish."""
    lines = stream_of(RESPONSE)[:-3]  # drop the final `response` event
    with pytest.raises(forge_data.StreamInterrupted) as err:
        forge_data.assemble_stream(forge_data.sse_events(lines), lambda text: None)
    assert err.value.text == texts(RESPONSE)  # what was written is kept


def test_an_error_event_or_an_empty_stream_is_an_interruption():
    with pytest.raises(forge_data.StreamInterrupted, match="399504") as err:
        forge_data.assemble_stream(forge_data.sse_events(sse(
            ("response.text.delta", {"text": "Partial"}),
            ("error", {"code": "399504", "message": "Error during execution", "request_id": "r"}))), lambda t: None)
    assert err.value.text == "Partial"
    with pytest.raises(forge_data.StreamInterrupted, match="without its final response"):
        forge_data.assemble_stream(forge_data.sse_events([b": nothing"]), lambda t: None)


# ── The request: the app's own session, no second login ─────────────────────

class FakeResponse:
    def __init__(self, status: int, lines=(), text: str = ""):
        self.status_code, self._lines, self.text = status, list(lines), text

    def iter_lines(self):
        return iter(self._lines)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


@pytest.fixture
def live_session(monkeypatch):
    """Live mode on a session whose connector connection has a token and a host."""
    session = SimpleNamespace(connection=SimpleNamespace(rest=SimpleNamespace(token="tok-123"), host="acct.example"))
    monkeypatch.setattr(config, "USE_MOCK_DATA", False)
    monkeypatch.setattr(forge_data, "_session", session)
    forge_data.pop_notices()
    return session


def test_the_request_reuses_the_session_token_and_streams(live_session, monkeypatch):
    import requests
    calls = []

    def post(url, **kwargs):
        calls.append((url, kwargs))
        return FakeResponse(200, stream_of(RESPONSE))

    monkeypatch.setattr(requests, "post", post)
    seen = []
    result = forge_data.ask_agent_stream("What is on-time delivery rate by region?", seen.append)
    (url, kwargs), = calls
    assert url == ("https://acct.example/api/v2/databases/SUPPLY_CHAIN_FORGE/schemas/SEMANTIC/agents/"
                   "SUPPLY_CHAIN_AGENT:run")
    assert kwargs["headers"]["Authorization"] == 'Snowflake Token="tok-123"'
    assert kwargs["headers"]["Accept"] == "text/event-stream" and kwargs["stream"] is True
    assert kwargs["json"] == {**json.loads(forge_data.agent_request("What is on-time delivery rate by region?")),
                              "stream": True}
    assert result["streamed"] is True and result["source"] == "live" and "".join(seen) == texts(RESPONSE)
    assert not forge_data.pop_notices()


@pytest.mark.parametrize("failure", [
    FakeResponse(401, text='{"message": "Authentication token is invalid"}'),  # the policy refuses the token
    ConnectionError("network down"),  # before the request reached Snowflake
])
def test_a_failure_before_the_stream_starts_falls_back_to_data_agent_run(live_session, monkeypatch, failure):
    import requests

    def post(url, **kwargs):
        if isinstance(failure, Exception):
            raise failure
        return failure

    fallback = {"answer": "via DATA_AGENT_RUN", "status": "completed", "source": "live"}
    monkeypatch.setattr(requests, "post", post)
    monkeypatch.setattr(forge_data, "ask_agent", lambda question, role=None: fallback)
    assert forge_data.ask_agent_stream("q") is fallback


def test_a_revoked_agent_is_paused_not_a_fallback(live_session, monkeypatch):
    import requests
    monkeypatch.setattr(requests, "post", lambda url, **kw: FakeResponse(
        404, text='{"message": "Agent SUPPLY_CHAIN_AGENT does not exist or not authorized."}'))
    monkeypatch.setattr(forge_data, "ask_agent", lambda *a, **k: pytest.fail("no fallback call when paused"))
    result = forge_data.ask_agent_stream("q")
    assert result["status"] == "paused" and result["source"] == "live"


def test_without_a_session_token_it_falls_back(monkeypatch):
    """SiS (warehouse runtime) or the replay: no connector token, so §5.3 answers."""
    monkeypatch.setattr(config, "USE_MOCK_DATA", False)
    monkeypatch.setattr(forge_data, "_session", SimpleNamespace(connection=SimpleNamespace()))
    monkeypatch.setattr(forge_data, "ask_agent", lambda question, role=None: {"answer": "fallback"})
    assert forge_data.ask_agent_stream("q") == {"answer": "fallback"}


def test_mock_mode_has_nothing_to_stream(monkeypatch):
    monkeypatch.setattr(config, "USE_MOCK_DATA", True)
    result = forge_data.ask_agent_stream(config.CANONICAL_QUESTIONS[1])
    assert result["source"] == "mock" and "streamed" not in result


# ── The Ask screen ───────────────────────────────────────────────────────────

def _app(**state) -> AppTest:
    st.cache_data.clear()
    st.cache_resource.clear()
    at = AppTest.from_file(str(APP), default_timeout=30)
    at.session_state["step"] = "ask"
    for name, value in state.items():
        at.session_state[name] = value
    return at.run()


def _fake_result(question: str) -> dict:
    return {"answer": f"Answer to {question}", "sql": "", "metric_used": [], "verified_query_used": False,
            "tools_used": [], "tables": [], "row_counts": [], "warnings": [], "suggestions": [],
            "status": "completed", "raw": {}, "source": "live"}


@pytest.fixture
def agent_calls(monkeypatch):
    monkeypatch.setattr(config, "USE_MOCK_DATA", False)
    calls = {"stream": [], "plain": []}

    def stream(question, on_text=None, on_status=None):
        calls["stream"].append(question)
        on_status("Planning the next steps")
        for word in ("Answer ", "to ", "it"):
            on_text(word)
        return {**_fake_result(question), "streamed": True}

    def plain(question, role=None):
        calls["plain"].append(question)
        return _fake_result(question)

    monkeypatch.setattr(forge_data, "ask_agent_stream", stream)
    monkeypatch.setattr(forge_data, "ask_agent", plain)
    return calls


@pytest.mark.parametrize("forge", ["replay"], indirect=True)
def test_one_agent_question_is_streamed_and_counted_once(forge, agent_calls):
    at = _app()
    at.chat_input[0].set_value("How many suppliers do we have?").run()
    assert not at.exception
    assert agent_calls == {"stream": ["How many suppliers do we have?"], "plain": []}
    assert at.session_state["ask_calls"] == 1
    assert at.session_state["chat"][0]["parts"][0]["result"]["streamed"] is True


@pytest.mark.parametrize("forge", ["replay"], indirect=True)
def test_several_agent_parts_still_run_in_parallel_unstreamed(forge, agent_calls):
    at = _app()
    at.chat_input[0].set_value("1) How many suppliers do we have? 2) How many orders are open right now?").run()
    assert agent_calls["stream"] == [] and len(agent_calls["plain"]) == 2


@pytest.mark.parametrize("forge", ["replay"], indirect=True)
def test_the_secrets_switch_turns_streaming_off(forge, agent_calls, monkeypatch):
    monkeypatch.setattr(config, "ASK_STREAM", False)
    at = _app()
    at.chat_input[0].set_value("How many suppliers do we have?").run()
    assert agent_calls == {"stream": [], "plain": ["How many suppliers do we have?"]}


# ── The switch, Stop and the agent's progress line (the user, 1 Oct) ──────────

def test_status_events_reach_the_progress_line():
    statuses = []
    forge_data.assemble_stream(forge_data.sse_events(stream_of(RESPONSE)), lambda t: None, statuses.append)
    assert statuses == ["Planning the next steps"]


def test_a_stop_click_ends_the_stream_instead_of_falling_back(live_session, monkeypatch):
    """Streamlit stops a run with a BaseException (its rerun), raised inside our callback.
    It must pass through: a fallback here would ask the agent again after the user stopped."""
    import requests
    from streamlit.runtime.scriptrunner_utils.exceptions import RerunException

    assert issubclass(RerunException, BaseException) and not issubclass(RerunException, Exception)

    class Stop(BaseException):
        pass

    def on_text(text):
        raise Stop()

    monkeypatch.setattr(requests, "post", lambda url, **kw: FakeResponse(200, stream_of(RESPONSE)))
    monkeypatch.setattr(forge_data, "ask_agent", lambda *a, **k: pytest.fail("no fallback after a stop"))
    with pytest.raises(Stop):
        forge_data.ask_agent_stream("q", on_text)


def test_a_stopped_answer_keeps_what_was_written():
    from ui.screens import ask
    assert ask.stopped_turn(None) is None and ask.stopped_turn({"text": "x"}) is None
    turn = ask.stopped_turn({"question": "Which carrier is slowest?", "text": "Maersk Logistics is the "})
    result = turn["parts"][0]["result"]
    assert turn["question"] == "Which carrier is slowest?" and result["answer"] == "Maersk Logistics is the"
    assert result["status"] == "stopped" and result["warnings"] == [{"message": ask.STOPPED_NOTE}]
    from ui import payloads
    card = payloads.answer(turn["question"], result)
    assert card["warnings"] == [ask.STOPPED_NOTE] and not card["practice"]


@pytest.mark.parametrize("forge", ["replay"], indirect=True)
def test_the_visitors_switch_turns_streaming_off(forge, agent_calls):
    at = _app(ask_stream=False)
    at.chat_input[0].set_value("How many suppliers do we have?").run()
    assert agent_calls == {"stream": [], "plain": ["How many suppliers do we have?"]}


@pytest.mark.parametrize("forge", ["replay"], indirect=True)
def test_the_switch_shows_live_only(forge, monkeypatch):
    at = _app()
    assert [t.label for t in at.toggle if t.key == "ask_stream"] == ["Stream answers"]
    monkeypatch.setattr(config, "USE_MOCK_DATA", True)
    at = _app()
    assert not [t for t in at.toggle if t.key == "ask_stream"]


# ── Review #12 / #13 (1 Oct): no second paid call once it started; never cached ──

class DroppingResponse(FakeResponse):
    """The connection drops after some of the answer has arrived."""

    def iter_lines(self):
        yield from self._lines[:9]
        raise ConnectionError("connection reset by peer")


@pytest.mark.parametrize("response", [
    FakeResponse(200, sse(("response.text.delta", {"text": "We sent 95,513 "}),
                          ("error", {"code": "399504", "message": "Error during execution"}))),
    FakeResponse(200, stream_of(RESPONSE)[:-3]),  # no final event
    DroppingResponse(200, stream_of(RESPONSE)),   # the network drops mid-stream
])
def test_an_interrupted_stream_keeps_its_text_and_asks_no_second_time(live_session, monkeypatch, response):
    import requests
    from utils import ask_guard
    monkeypatch.setattr(requests, "post", lambda url, **kw: response)
    monkeypatch.setattr(forge_data, "ask_agent", lambda *a, **k: pytest.fail("a second paid agent call"))
    result = forge_data.ask_agent_stream("q", lambda t: None)
    assert result["status"] == "incomplete" and result["source"] == "live"
    assert result["warnings"] == [{"message": forge_data.INTERRUPTED_NOTE}] and result["answer"]
    cache = ask_guard.AnswerCache()
    cache.put("q", result)
    assert cache.get("q") is None  # an incomplete answer is never served as an answer


def test_the_answer_cache_is_per_data_version():
    """Review #5: the nightly load moves the as-of date; cached answers roll over with it."""
    from utils import ask_guard
    cache = ask_guard.AnswerCache()
    cache.put("q", {"answer": "a", "status": "completed", "source": "live"}, version="live|30 Sep 2026")
    assert cache.get("q", version="live|30 Sep 2026")["answer"] == "a"
    assert cache.get("q", version="live|01 Oct 2026") is None
