"""Shared test setup: app/ on sys.path, the mock/live `forge` fixture, and marker defaults.

Contract tests take the `forge` fixture, so each one runs twice:
  [mock]  offline, against the mock data layer
  [live]  against real Snowflake; skipped when no session can be opened

In live mode, forge_data's fallback to mock data (right for the demo) would let a test
pass on mock numbers. The `forge` proxy turns any such fallback into a test failure that
shows Snowflake's error.
"""

import functools
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "app"))

from utils import config, forge_data  # noqa: E402


@pytest.hookimpl(tryfirst=True)
def pytest_collection_modifyitems(items):
    """Everything that isn't live or ui is an offline test, so `-m mock` selects it."""
    for item in items:
        if not (item.get_closest_marker("live") or item.get_closest_marker("ui")):
            item.add_marker(pytest.mark.mock)


@functools.cache
def _no_live_session() -> str | None:
    """None if a Snowflake session opens, else why not (checked once per run)."""
    try:
        forge_data.get_session()
        return None
    except Exception as exc:  # no connector, no connection name, auth failure, ...
        return str(exc).splitlines()[0][:160]


class Forge:
    """forge_data, where a live call that falls back to mock data fails the test."""

    def __init__(self, mode: str):
        self.mode = mode
        self.live = mode == "live"

    def __getattr__(self, name):
        attr = getattr(forge_data, name)
        if not callable(attr):
            return attr

        def call(*args, **kwargs):
            result = attr(*args, **kwargs)
            notices = forge_data.pop_notices()
            if self.live and notices:
                pytest.fail("Live query fell back to mock data:\n"
                            + "\n".join(f"  {n.label}: {n.message}" for n in notices), pytrace=False)
            return result

        return call

    def raw(self, sql: str):
        """Run SQL directly on Snowflake, with no fallback (live only)."""
        assert self.live, "raw() needs Snowflake"
        return forge_data._query(sql)


@pytest.fixture(params=["mock", pytest.param("live", marks=pytest.mark.live)])
def forge(request, monkeypatch):
    if request.param == "live" and (reason := _no_live_session()):
        pytest.skip(f"No Snowflake connection ({reason}). Set SNOWFLAKE_CONNECTION_NAME to run live tests.")
    monkeypatch.setattr(config, "USE_MOCK_DATA", request.param == "mock")
    forge_data.pop_notices()
    yield Forge(request.param)
    forge_data.pop_notices()
