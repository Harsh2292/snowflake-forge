""".github/scripts/keep_awake.py fails the job on a hang, a Streamlit error or the mock
fallback (review #19, 1 Oct), not only on the fallback. Offline, with a fake page."""

import importlib.util
from pathlib import Path

import pytest

pytest.importorskip("playwright")

ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("keep_awake", ROOT / ".github" / "scripts" / "keep_awake.py")
keep_awake = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(keep_awake)


class FakeLocator:
    def __init__(self, n):
        self.n = n

    def count(self):
        return self.n


class FakeFrame:
    def __init__(self, testids=(), html=""):
        self.testids, self.html = set(testids), html

    def locator(self, selector):
        return FakeLocator(sum(f'"{t}"' in selector for t in self.testids))

    def content(self):
        return self.html


class FakePage:
    def __init__(self, *frames):
        self.frames = list(frames)

    def wait_for_timeout(self, ms):
        pass


def test_a_screen_that_never_settles_fails(monkeypatch):
    clock = iter(range(0, 10_000, 50))
    monkeypatch.setattr(keep_awake.time, "time", lambda: next(clock))
    page = FakePage(FakeFrame(["stStatusWidget"]))
    assert keep_awake.settle(page, timeout=120) is False
    assert keep_awake.problem(page, False) == "still running after 2 minutes"


def test_a_streamlit_exception_fails():
    page = FakePage(FakeFrame(), FakeFrame(["stException"]))
    assert keep_awake.settle(page) is True
    assert keep_awake.problem(page, True) == "Streamlit error"


def test_the_mock_fallback_fails():
    page = FakePage(FakeFrame(html=f"<div {keep_awake.FALLBACK}></div>"))
    assert keep_awake.problem(page, True) == "live connection paused"


def test_a_healthy_screen_passes():
    page = FakePage(FakeFrame(html='<div data-source="live"></div>'))
    assert keep_awake.problem(page, keep_awake.settle(page)) is None
