"""Cost guard for the Ask screen on the public link (C15). Pure Python, no Streamlit.

Every new Ask question is a Cortex Agent call, and those cost money. The limits:
- per visitor: a cooldown between calls and a cap per browser session. A new tab resets
  these, so they only stop casual spamming.
- across all visitors: calls in flight, calls per rolling hour, and calls per UTC day. These
  protect the bill. They live in one process-wide AskLimiter (st.cache_resource), so they
  reset when the app restarts; CoCo's resource monitor and Cortex budget stay the hard cap.

A cached answer (AnswerCache) costs nothing and counts toward no limit.
"""

import re
import threading
import time
from collections import deque
from datetime import datetime, timezone

from . import config

MESSAGES = {
    "cooldown": "One moment: please wait a few seconds between questions.",
    "session": ("This public demo allows {per_session} new questions per visit. Questions someone has "
                "already asked still answer instantly, and every other screen keeps working."),
    "busy": "The agent is busy answering other visitors. Please try again in a minute.",
    "hour": ("The demo has reached its question budget for this hour. Please try again later; "
             "every other screen still shows live data."),
    "day": ("The demo has reached its question budget for today. Please come back tomorrow; "
            "every other screen still shows live data."),
    "paused": ("Ask is paused for now: the demo has used its budget for AI answers. Every other "
               "screen still shows live data."),
}
# Added to "paused" while the instant answers (utils/router.py) are on.
PAUSED_INSTANT = " Metric questions like the suggested ones still answer instantly from the governed semantic view."


def limits(overrides=None) -> dict:
    """config.ASK_LIMITS with any valid [forge] secrets overrides (positive integers)."""
    out = dict(config.ASK_LIMITS)
    for key, value in (overrides or {}).items():
        if key in out:
            try:
                number = int(value)
            except (TypeError, ValueError):
                continue
            if number >= 0:
                out[key] = number
    return out


def message(reason: str, lim: dict) -> str:
    return MESSAGES[reason].format(**lim)


def session_refusal(state, now: float, lim: dict):
    """Why this visitor can't make a new agent call now, or None. `state` is the visitor's
    session_state (any mutable mapping); nothing is recorded here."""
    last = state.get("ask_last_call")
    if last is not None and now - last < lim["cooldown_seconds"]:
        return "cooldown"
    if state.get("ask_calls", 0) >= lim["per_session"]:
        return "session"
    return None


def record_session_call(state, now: float) -> None:
    state["ask_calls"] = state.get("ask_calls", 0) + 1
    state["ask_last_call"] = now


class AskLimiter:
    """Global limits, shared by every visitor of this process. Thread-safe."""

    def __init__(self, lim: dict, clock=time.time):
        self._lim = lim
        self._clock = clock
        self._lock = threading.Lock()
        self._hour = deque()  # start times of calls in the last hour
        self._day = None
        self._day_count = 0
        self._in_flight = 0
        self._paused_until = 0.0

    def pause(self, seconds: float) -> None:
        """The agent is switched off (the Cortex budget): refuse every call for a while,
        rather than make each visitor wait for the same error."""
        with self._lock:
            self._paused_until = self._clock() + seconds

    def try_acquire(self):
        """Reserve one agent call: None on success (call release() afterwards), else the
        reason it's refused ("paused", "day", "hour" or "busy")."""
        with self._lock:
            now = self._clock()
            if now < self._paused_until:
                return "paused"
            day = datetime.fromtimestamp(now, timezone.utc).date()
            if day != self._day:
                self._day, self._day_count = day, 0
            while self._hour and now - self._hour[0] >= 3600:
                self._hour.popleft()
            if self._day_count >= self._lim["per_day"]:
                return "day"
            if len(self._hour) >= self._lim["per_hour"]:
                return "hour"
            if self._in_flight >= self._lim["concurrent"]:
                return "busy"
            self._hour.append(now)
            self._day_count += 1
            self._in_flight += 1
            return None

    def release(self) -> None:
        with self._lock:
            self._in_flight = max(0, self._in_flight - 1)

    def usage(self) -> dict:
        with self._lock:
            return {"in_flight": self._in_flight, "last_hour": len(self._hour), "today": self._day_count}


def normalise(question: str) -> str:
    return re.sub(r"\s+", " ", (question or "").strip().lower()).rstrip(" ?")


_CANONICAL = {normalise(q) for q in config.CANONICAL_QUESTIONS}


class AnswerCache:
    """Live agent answers, keyed by the normalised question. The suggested (canonical)
    questions keep their answer for 24 h, free text for 1 h. Thread-safe."""

    def __init__(self, clock=time.time, max_entries: int = 500):
        self._clock = clock
        self._max = max_entries
        self._lock = threading.Lock()
        self._items = {}  # key -> (expires_at, result, data version)

    def get(self, question: str, version=None):
        """The cached answer, if it's for the same data version (the as-of date: review #5)."""
        key = normalise(question)
        with self._lock:
            hit = self._items.get(key)
            if hit is None:
                return None
            if hit[0] <= self._clock() or hit[2] != version:
                del self._items[key]
                return None
            return hit[1]

    def put(self, question: str, result: dict, version=None) -> None:
        """Only complete live answers are kept: a fallback answer must never be served as
        live, a "paused" one must not outlast the pause, and an interrupted or stopped one
        is not an answer (review #13)."""
        if result.get("source") != "live" or result.get("status", "completed") != "completed":
            return
        key = normalise(question)
        ttl = config.ANSWER_CACHE_SECONDS["canonical" if key in _CANONICAL else "free_text"]
        with self._lock:
            if len(self._items) >= self._max:
                self._items.pop(min(self._items, key=lambda k: self._items[k][0]))
            self._items[key] = (self._clock() + ttl, result, version)
