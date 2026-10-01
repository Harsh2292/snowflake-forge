"""C15: the public link on Streamlit Community Cloud, live on Snowflake.

The session factory (key-pair from a PEM string in secrets), live-by-default, reconnect
once, a fallback that stays on screen, and the Ask cost guard (rate limiter, caps, answer
cache). All offline: Snowpark's Session is replaced by a fake.
"""

import threading
import tomllib
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

import pytest
import streamlit as st
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from streamlit.testing.v1 import AppTest

from utils import ask_guard, config, forge_data

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"
FAKE_ACCOUNT = "test-org-test-account"


@pytest.fixture(scope="module")
def key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def _pem(key, password=None) -> str:
    encryption = (serialization.BestAvailableEncryption(password.encode()) if password
                  else serialization.NoEncryption())
    return key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, encryption).decode()


def _der(key) -> bytes:
    return key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8,
                             serialization.NoEncryption())


@pytest.fixture
def section(key):
    return {"account": FAKE_ACCOUNT, "user": "FORGE_APP_SVC", "role": "FORGE_APP_ROLE",
            "warehouse": "FORGE_WH", "private_key": _pem(key)}


@pytest.fixture(autouse=True)
def clean_state(monkeypatch):
    """Module globals that configure() and the session factory change, restored after."""
    monkeypatch.setattr(config, "USE_MOCK_DATA", True)
    monkeypatch.setattr(forge_data, "_session", None)
    monkeypatch.setattr(forge_data, "_connection", None)
    monkeypatch.setitem(forge_data._login, "failed_at", None)
    monkeypatch.setitem(forge_data._sis, "checked", True)
    monkeypatch.setitem(forge_data._sis, "session", None)
    monkeypatch.delenv("SNOWFLAKE_CONNECTION_NAME", raising=False)
    forge_data.pop_notices()
    st.cache_data.clear()
    st.cache_resource.clear()
    yield
    forge_data.pop_notices()


# ── Session parameters from secrets ─────────────────────────────────────────

def test_pem_key_from_secrets_becomes_der_bytes_for_a_jwt_login(section, key):
    params = forge_data.session_params(section)
    assert params["private_key"] == _der(key)
    assert "private_key_file" not in params
    assert params["authenticator"] == "SNOWFLAKE_JWT"
    assert (params["account"], params["user"], params["role"]) == (FAKE_ACCOUNT, "FORGE_APP_SVC", "FORGE_APP_ROLE")
    assert params["database"] == config.DATABASE and params["warehouse"] == config.WAREHOUSE
    assert params["session_parameters"]["STATEMENT_TIMEOUT_IN_SECONDS"] == config.STATEMENT_TIMEOUT_SECONDS
    assert params["login_timeout"] == config.LOGIN_TIMEOUT_SECONDS


def test_an_encrypted_key_needs_its_passphrase(section, key):
    section["private_key"] = _pem(key, "s3cret")
    section["private_key_passphrase"] = "s3cret"
    assert forge_data.session_params(section)["private_key"] == _der(key)


def test_missing_secrets_are_named_without_values(section):
    del section["user"], section["private_key"]
    with pytest.raises(ValueError) as err:
        forge_data.session_params(section)
    assert str(err.value) == "Snowflake secrets are missing: user, private_key"


def test_an_unreadable_key_never_echoes_the_key(section):
    section["private_key"] = "-----BEGIN PRIVATE KEY-----\nNOTAKEYNOTAKEY\n-----END PRIVATE KEY-----"
    with pytest.raises(ValueError) as err:
        forge_data.session_params(section)
    assert "NOTAKEY" not in str(err.value)
    assert err.value.__cause__ is None and err.value.__suppress_context__


@pytest.mark.parametrize("damage", [
    lambda pem: "\n".join("    " + line for line in pem.splitlines()),       # indented by the editor
    lambda pem: pem.replace("\n", "\\n"),                                     # a one-line value with \n
    lambda pem: " ".join(pem.split()),                                        # all on one line
    lambda pem: "\n\n" + pem.replace("\n", "\r\n") + "\n\n",                  # Windows line ends, blank lines
    lambda pem: "\n".join(pem.strip().splitlines()[1:-1]),                    # the body without BEGIN / END
])
def test_a_key_damaged_by_pasting_still_works(section, key, damage):
    """Community Cloud, 1 Oct: the pasted key failed as "not a readable PEM private key"."""
    section["private_key"] = damage(_pem(key))
    assert forge_data.session_params(section)["private_key"] == _der(key)


def test_a_public_key_by_mistake_is_named(section, key):
    public = key.public_key().public_bytes(serialization.Encoding.PEM,
                                           serialization.PublicFormat.SubjectPublicKeyInfo).decode()
    section["private_key"] = public
    with pytest.raises(ValueError, match="PUBLIC key: paste rsa_key.p8"):
        forge_data.session_params(section)


def test_an_encrypted_key_without_its_passphrase_is_named(section, key):
    section["private_key"] = _pem(key, "s3cret")
    with pytest.raises(ValueError, match="encrypted: add private_key_passphrase"):
        forge_data.session_params(section)


def test_a_missing_pem_block_is_named(section):
    section["private_key"] = "MIIEvQIBADANBgkqhkiG9w0BAQEFAASC"
    with pytest.raises(ValueError, match="no '-----BEGIN PRIVATE KEY-----'") as err:
        forge_data.session_params(section)
    assert "MIIE" not in str(err.value)


# ── Live by default ──────────────────────────────────────────────────────────

def test_a_secrets_connection_switches_live_on(section):
    forge_data.configure(section, {})
    assert forge_data.data_mode() == "live"


def test_secrets_can_force_mock_without_a_commit(section):
    forge_data.configure(section, {"mode": "mock"})
    assert forge_data.data_mode() == "mock"


def test_no_connection_leaves_local_and_ci_on_mock():
    forge_data.configure({}, {})
    assert forge_data.data_mode() == "mock"


def test_streamlit_in_snowflake_switches_live_on(monkeypatch):
    sis_session = object()
    monkeypatch.setitem(forge_data._sis, "session", sis_session)
    forge_data.configure(None, None)
    assert forge_data.data_mode() == "live"
    assert forge_data.get_session() is sis_session


# ── Session factory, login breaker, reconnect once ──────────────────────────

class FakeRows:
    def __init__(self, rows):
        self._rows = rows

    def collect(self):
        return [SimpleNamespace(as_dict=lambda r=r: r) for r in self._rows]


class FakeSession:
    def __init__(self, fail=None):
        self.fail = fail
        self.query_tag = None
        self.closed = False

    def sql(self, sql, params=None):
        if self.fail:
            raise self.fail
        return FakeRows([{"COLUMN": 0.5}])

    def close(self):
        self.closed = True


class ExpiredToken(Exception):
    sql_error_code = 390114


@pytest.fixture
def builder(monkeypatch):
    """snowflake.snowpark.Session with a fake builder: records logins, returns queued sessions."""
    import snowflake.snowpark
    state = SimpleNamespace(logins=[], queue=[])

    class Builder:
        def configs(self, params):
            state.logins.append(params)
            return self

        def create(self):
            item = state.queue.pop(0)
            if isinstance(item, Exception):
                raise item
            return item

    monkeypatch.setattr(snowflake.snowpark, "Session", SimpleNamespace(builder=Builder()))
    return state


def test_the_secrets_connection_logs_in_once_and_is_shared(section, builder):
    builder.queue.append(FakeSession())
    forge_data.configure(section, {})
    first = forge_data.get_session()
    assert forge_data.get_session() is first and len(builder.logins) == 1
    assert builder.logins[0]["authenticator"] == "SNOWFLAKE_JWT"


def test_a_failed_login_falls_back_at_once_for_a_while(section, builder):
    builder.queue.append(RuntimeError("login failed"))
    forge_data.configure(section, {})
    assert forge_data.get_naive_otd() == forge_data.mock_data.MOCK_NAIVE_OTD
    forge_data.get_naive_otd()  # within LOGIN_RETRY_SECONDS: no second login attempt
    assert len(builder.logins) == 1
    assert len(forge_data.pop_notices()) == 2


def test_the_real_login_error_reaches_the_log_and_later_notices(section, builder, caplog):
    builder.queue.append(RuntimeError("JWT token is invalid"))
    forge_data.configure(section, {})
    forge_data.get_naive_otd()
    assert "login as FORGE_APP_SVC failed: JWT token is invalid" in caplog.text
    assert "JWT token is invalid" in forge_data.pop_notices()[0].message


def test_an_expired_session_logs_in_again_once(section, builder, monkeypatch):
    dead = FakeSession(fail=ExpiredToken("Authentication token has expired."))
    builder.queue.append(FakeSession())
    forge_data.configure(section, {})
    monkeypatch.setattr(forge_data, "_session", dead)
    assert forge_data.get_naive_otd() == 0.5
    assert dead.closed and len(builder.logins) == 1
    assert forge_data.pop_notices() == []


def test_other_errors_fall_back_without_logging_in_again(section, builder, monkeypatch):
    forge_data.configure(section, {})
    monkeypatch.setattr(forge_data, "_session", FakeSession(fail=RuntimeError("SQL compilation error")))
    assert forge_data.get_naive_otd() == forge_data.mock_data.MOCK_NAIVE_OTD
    assert builder.logins == []
    assert [n.label for n in forge_data.pop_notices()] == ["get_naive_otd"]


def test_one_visitors_fallback_never_reaches_another_visitor(monkeypatch):
    monkeypatch.setattr(config, "USE_MOCK_DATA", False)
    worker = threading.Thread(target=forge_data.get_naive_otd)  # no session: falls back
    worker.start()
    worker.join()
    assert forge_data.pop_notices() == []


# ── Ask cost guard: rate limiter and caps ────────────────────────────────────

class Clock:
    def __init__(self, now=datetime(2026, 10, 3, 12, tzinfo=timezone.utc).timestamp()):
        self.now = now

    def __call__(self):
        return self.now


LIM = ask_guard.limits()


def test_limit_defaults_and_secrets_overrides():
    assert LIM == config.ASK_LIMITS
    tuned = ask_guard.limits({"per_day": "50", "per_hour": "oops", "unknown": 1, "concurrent": -1})
    assert tuned["per_day"] == 50 and tuned["per_hour"] == LIM["per_hour"]
    assert tuned["concurrent"] == LIM["concurrent"] and "unknown" not in tuned


def test_per_visitor_cooldown_and_session_cap():
    state, now = {}, 1000.0
    for i in range(LIM["per_session"]):
        assert ask_guard.session_refusal(state, now, LIM) is None
        ask_guard.record_session_call(state, now)
        assert ask_guard.session_refusal(state, now + 1, LIM) == "cooldown"
        now += LIM["cooldown_seconds"]
    assert ask_guard.session_refusal(state, now, LIM) == "session"


def test_global_concurrency_cap():
    limiter = ask_guard.AskLimiter(LIM, clock=Clock())
    assert [limiter.try_acquire() for _ in range(LIM["concurrent"] + 1)][-1] == "busy"
    limiter.release()
    assert limiter.try_acquire() is None


def test_global_rolling_hour_cap():
    clock = Clock()
    start = clock.now
    limiter = ask_guard.AskLimiter(LIM, clock=clock)
    for _ in range(LIM["per_hour"]):
        assert limiter.try_acquire() is None
        limiter.release()
        clock.now += 60
    assert limiter.try_acquire() == "hour"
    clock.now = start + 3600  # the first call leaves the window
    assert limiter.try_acquire() is None
    assert limiter.try_acquire() == "hour"


def test_global_daily_cap_resets_at_utc_midnight():
    clock = Clock(datetime(2026, 10, 3, 0, 0, tzinfo=timezone.utc).timestamp())
    limiter = ask_guard.AskLimiter({**LIM, "per_hour": 10_000}, clock=clock)
    for _ in range(LIM["per_day"]):
        assert limiter.try_acquire() is None
        limiter.release()
        clock.now += 1
    assert limiter.try_acquire() == "day"
    clock.now = datetime(2026, 10, 4, 0, 0, 1, tzinfo=timezone.utc).timestamp()
    assert limiter.try_acquire() is None


def test_answer_cache_keeps_suggested_questions_longer_and_never_fallbacks():
    clock = Clock()
    cache = ask_guard.AnswerCache(clock=clock)
    live = {"answer": "x", "source": "live"}
    cache.put(config.CANONICAL_QUESTIONS[0], live)
    cache.put("How many plants are there", live)
    cache.put("A question that fell back", {"answer": "y", "source": "mock_fallback"})
    assert cache.get(config.CANONICAL_QUESTIONS[0].upper().rstrip("?") + " ?") is live  # normalised
    assert cache.get("A question that fell back") is None
    clock.now += config.ANSWER_CACHE_SECONDS["free_text"] + 1
    assert cache.get("How many plants are there") is None
    assert cache.get(config.CANONICAL_QUESTIONS[0]) is live
    clock.now += config.ANSWER_CACHE_SECONDS["canonical"]
    assert cache.get(config.CANONICAL_QUESTIONS[0]) is None


# ── The app: Ask guard, fallback banner ──────────────────────────────────────

def _app(step: str, secrets=None, **state) -> AppTest:
    """A fresh visitor. AppTest can't run again once st.pills is on screen (it appears after
    the first answer), so each visit asks at most one question; the process-wide limiter
    and answer cache carry over between visitors, as on Community Cloud."""
    at = AppTest.from_file(str(APP / "streamlit_app.py"), default_timeout=30)
    for name, value in (secrets or {}).items():
        at.secrets[name] = value
    at.session_state["step"] = step
    for name, value in state.items():
        at.session_state[name] = value
    return at.run()


def _markdown(at) -> str:
    return "\n".join(m.value for m in at.markdown)


@pytest.fixture
def live_agent(monkeypatch):
    """Live mode with a fake agent that counts its calls. Everything else falls back. The
    instant answers are off, so the suggested questions reach the agent (C14 tests them)."""
    monkeypatch.setattr(config, "USE_MOCK_DATA", False)
    monkeypatch.setattr(config, "ASK_SHORTCUT", False)
    calls = []

    def ask_agent(question, role=None):
        calls.append(question)
        return {"answer": f"Answer to {question}", "sql": "", "metric_used": [], "verified_query_used": False,
                "tools_used": [], "tables": [], "warnings": [], "status": "ok", "raw": {}, "source": "live"}

    monkeypatch.setattr(forge_data, "ask_agent", ask_agent)
    return calls


def test_a_repeated_suggested_question_is_answered_from_the_cache(live_agent):
    first = _app("ask")
    first.button(key="qcard_0").click().run()
    assert first.session_state["ask_calls"] == 1
    second = _app("ask")  # another visitor, same question
    second.button(key="qcard_0").click().run()
    assert live_agent == [config.CANONICAL_QUESTIONS[0]]  # one agent call for both
    assert len(second.session_state["chat"]) == 1 and "ask_calls" not in second.session_state


def test_the_session_cap_refuses_with_a_plain_message(live_agent):
    at = _app("ask", {"forge": {"per_session": 1}}, ask_calls=1)
    at.button(key="qcard_1").click().run()
    assert live_agent == [] and at.session_state["chat"] == []
    assert "allows 1 new questions per visit" in _markdown(at)


def test_the_global_daily_cap_refuses_every_visitor(live_agent):
    _app("ask", {"forge": {"per_day": 1}}).button(key="qcard_0").click().run()
    at = _app("ask", {"forge": {"per_day": 1}})
    at.button(key="qcard_1").click().run()
    assert live_agent == [config.CANONICAL_QUESTIONS[0]]
    assert "question budget for today" in _markdown(at)


def test_mock_mode_is_not_rate_limited(monkeypatch):
    at = _app("ask", {"forge": {"per_session": 0}})
    at.button(key="qcard_0").click().run()
    assert len(at.session_state["chat"]) == 1


def test_a_fallback_shows_a_banner_that_stays_and_leaks_nothing(section, builder, monkeypatch):
    builder.queue.extend([RuntimeError(f"Could not connect to {FAKE_ACCOUNT}")] * 5)
    at = _app("problem", {"connections": {"snowflake": section}})
    page = _markdown(at)
    assert 'data-source="mock_fallback"' in page and "Live connection paused" in page
    assert 'sf-tag">Saved results<' in page
    assert FAKE_ACCOUNT not in page and "BEGIN" not in page


def test_mock_mode_shows_no_fallback_banner():
    assert "mock_fallback" not in _markdown(_app("problem"))


# ── Community Cloud files ────────────────────────────────────────────────────

def test_app_has_exactly_one_dependency_file():
    names = {"uv.lock", "Pipfile", "environment.yml", "requirements.txt", "pyproject.toml"}
    assert {p.name for p in APP.iterdir()} & names == {"requirements.txt"}
    assert not (names - {"pyproject.toml"}) & {p.name for p in ROOT.iterdir()}


def test_requirements_cover_key_pair_auth():
    reqs = (APP / "requirements.txt").read_text(encoding="utf-8")
    assert "streamlit==1.52.2" in reqs and "cryptography" in reqs and "snowflake-snowpark-python" in reqs


def test_theme_config_at_the_repo_root_matches_the_app_copy():
    """Community Cloud reads .streamlit/config.toml only from the repo root."""
    root_copy = (ROOT / ".streamlit" / "config.toml").read_text(encoding="utf-8")
    assert root_copy == (APP / ".streamlit" / "config.toml").read_text(encoding="utf-8")
    assert tomllib.loads(root_copy)["theme"]["primaryColor"]
