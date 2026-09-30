"""Step 4: ask the Cortex Agent in plain English. Native Streamlit, because every question
needs a server round trip. Each answer is drawn as an HTML answer card (ui/views/answer.html).

Every question is routed first (utils/router.py, C14). A known metric question answers in
about a second, straight from the governed semantic view; everything else goes to the agent.
A multi-part question is split, and its agent parts run in parallel, one card per part.

On live data every agent call costs money, so the public link guards it
(utils/ask_guard.py): cached answers first, then per-visitor and global limits. Instant
answers make no agent call, so no limit counts them."""

import logging
import math
import time

import streamlit as st

from utils import ask_guard, config, forge_data, router
from ui import payloads, settings, view
from ui.components import esc, html

log = logging.getLogger("forge")
SPINNER = ("Asking the agent… this usually takes 20–30 seconds: it reads your question, "
           "queries the governed semantic view, then writes the answer.")
SPINNER_INSTANT = "Querying the governed semantic view…"


@st.cache_resource(show_spinner=False)
def _limiter(per_hour: int, per_day: int, concurrent: int) -> ask_guard.AskLimiter:
    """One per process: the limits count every visitor together."""
    return ask_guard.AskLimiter({"per_hour": per_hour, "per_day": per_day, "concurrent": concurrent})


@st.cache_resource(show_spinner=False)
def _answers() -> ask_guard.AnswerCache:
    return ask_guard.AnswerCache()


@st.cache_data(ttl=config.SCREEN_CACHE_SECONDS, show_spinner=False)
def _instant(mode: str, metric: str, dimension, order, rank_word: str, value) -> dict:
    """An instant answer, shared by every visitor like the other screens' data."""
    return router.instant_answer(router.Intent(metric, dimension, order, rank_word, value))


@st.cache_data(ttl=config.SCREEN_CACHE_SECONDS, show_spinner=False)
def _learned(mode: str) -> dict:
    """The names the semantic view lists (plants, carriers, …), for "fill rate at <plant>".
    Only fetched when a question isn't understood without them. A fallback is never kept."""
    values = router.learn_values()
    if forge_data.pop_notices():  # saved names are fine to read, but retry live next time
        _learned.clear()
    return values


def _shortcut_on() -> bool:
    value = settings.app_settings().get("shortcut", config.ASK_SHORTCUT)
    return str(value).strip().lower() not in ("false", "0", "no", "off")


def _refuse(reason: str, lim: dict, limiter) -> None:
    text = ask_guard.message(reason, lim)
    if reason == "paused" and _shortcut_on():
        text += ask_guard.PAUSED_INSTANT
    st.session_state.ask_refused = text
    log.warning("forge: Ask refused (%s); usage %s", reason, limiter.usage())


def _reserve(count: int, lim: dict, limiter) -> int:
    """Reserve up to `count` agent calls for this visitor (limiter.release() after each).
    The cooldown applies per question, not per part."""
    now = time.time()
    reason = ask_guard.session_refusal(st.session_state, now, lim)
    granted = 0
    while reason is None and granted < count:
        if granted and st.session_state.get("ask_calls", 0) >= lim["per_session"]:
            reason = "session"
            break
        reason = limiter.try_acquire()
        if reason is None:
            ask_guard.record_session_call(st.session_state, now)
            granted += 1
    if reason is not None:
        _refuse(reason, lim, limiter)
    return granted


def _answer(parts: list) -> list:
    """Each part's result, in order (None where a limit refused it). Instant parts run first,
    on this thread; then the agent parts, all at once."""
    mode = forge_data.data_mode()
    live = mode == "live"
    results = [None] * len(parts)
    waiting = []  # parts that need an agent call
    for i, part in enumerate(parts):
        if part.intent is None:
            cached = _answers().get(part.text) if live else None
            if cached is not None:
                results[i] = cached
            else:
                waiting.append(i)

    lim, limiter = config.ASK_LIMITS, None
    if live and waiting:
        lim = ask_guard.limits(settings.app_settings())
        limiter = _limiter(lim["per_hour"], lim["per_day"], lim["concurrent"])
        waiting = waiting[:_reserve(len(waiting), lim, limiter)]

    def ask(text):
        def job():
            try:
                return forge_data.ask_agent(text)
            finally:
                if limiter is not None:
                    limiter.release()
        return job

    with st.spinner(SPINNER if waiting else SPINNER_INSTANT):
        for i, part in enumerate(parts):
            if part.intent is not None:
                start = time.perf_counter()
                intent = part.intent
                result = _instant(mode, intent.metric, intent.dimension, intent.order, intent.rank_word,
                                  intent.value)
                if result.get("source") == "mock_fallback":
                    _instant.clear()  # never keep saved results: the next question retries
                results[i] = {**result, "elapsed": time.perf_counter() - start}
        answered = router.run_parallel([ask(parts[i].text) for i in waiting], max_workers=lim["concurrent"])
    for i, (result, seconds) in zip(waiting, answered):
        if result.get("status") == "paused":
            if limiter is not None:
                limiter.pause(config.ASK_PAUSE_SECONDS)
                _refuse("paused", lim, limiter)
            continue
        if live:
            _answers().put(parts[i].text, result)
        results[i] = {**result, "elapsed": seconds}
    return results


def _ask(question: str) -> None:
    question = (question or "").strip()[:config.ASK_MAX_CHARS]
    if not question:
        return
    st.session_state.ask_refused = None
    parts = router.route(question, shortcut=_shortcut_on(), values=lambda: _learned(forge_data.data_mode()))
    answers = [{"question": part.text, "result": result}
               for part, result in zip(parts, _answer(parts)) if result is not None]
    if answers:
        st.session_state.chat.append({"question": question, "parts": answers})


def _picked() -> None:
    _ask(st.session_state.get("ask_pick"))
    st.session_state.ask_pick = None


def _asker(question: str):
    def ask():
        _ask(question)
    return ask


def _clear() -> None:
    st.session_state.chat = []


def _card_height(card: dict) -> int:
    paragraphs = card["answer"].split("\n\n")
    lines = sum(math.ceil(max(len(line), 1) / 85) for p in paragraphs for line in p.split("\n"))  # conservative
    return (190 + 28 * lines + 10 * (len(paragraphs) - 1) + (215 if card["chart"] else 0)
            + 44 * (len(card["warnings"]) + bool(card.get("health")))
            - (0 if card["question"] else 62) + (30 if card["part"] else 0)
            + 26 * max(0, math.ceil(len(card["question"]) / 60) - 1)  # a long question wraps
            + (40 if card["instant"] else 0))  # its longer header can wrap under its chips


MAX_PILLS = 6


def _next_questions(chat: list) -> list[str]:
    """"Try another": the agent's own follow-up suggestions for the last answer first, then
    the suggested questions not asked yet (limits apply to those the agent answers)."""
    asked = {q for turn in chat for q in [turn["question"], *(p["question"] for p in turn["parts"])]}
    suggested = [q for p in chat[-1]["parts"] for q in p["result"].get("suggestions") or []] if chat else []
    options = [q for q in [*suggested, *config.CANONICAL_QUESTIONS] if q not in asked]
    return list(dict.fromkeys(options))[:MAX_PILLS]


def render(t: dict, nav) -> None:
    _, middle, _ = st.columns([1, 5.2, 1])
    with middle:
        if not st.session_state.chat:
            html('''<h1 class="sf-h1">Ask a question in plain English</h1>
                <p class="sf-lede">Every answer comes from the governed semantic view and shows its working:
                the SQL it ran and the metric definition it used. Start with one of these.</p>''')
            st.write("")
            questions = config.CANONICAL_QUESTIONS
            for row in (questions[:4], questions[4:]):
                for i, (col, q) in enumerate(zip(st.columns(4, gap="small"), row)):
                    with col:
                        st.button(q, key=f"qcard_{questions.index(q)}", on_click=_asker(q), width="stretch")
        else:
            head, clear = st.columns([5, 1.4], vertical_alignment="center")
            with head:
                html('<div class="sf-h2" style="font-size:28px">Ask a question in plain English</div>')
            with clear:
                st.button("New conversation", key="ask_clear", icon=":material/refresh:", on_click=_clear, width="stretch")
            st.write("")
            for turn in st.session_state.chat:
                split = len(turn["parts"]) > 1
                for i, part in enumerate(turn["parts"]):  # one card per part, under the one question
                    card = payloads.answer(turn["question"] if i == 0 else "", part["result"],
                                           part=part["question"] if split else "")
                    view.render("answer", card, t, height=_card_height(card))
            remaining = _next_questions(st.session_state.chat)
            if remaining:
                st.pills("Try another", remaining, key="ask_pick", on_change=_picked)
        if st.session_state.get("ask_refused"):
            html(f'<div class="sf-alert note" data-ask-limit="1" role="status"><span>{esc(st.session_state.ask_refused)}</span></div>')
        st.caption(f"Answers are grounded in {config.SEMANTIC_VIEW}.")

    prompt = st.chat_input("Ask about on-time delivery, fill rate, inventory or landed cost",
                           max_chars=config.ASK_MAX_CHARS)
    if prompt:
        _ask(prompt)
        st.rerun()
