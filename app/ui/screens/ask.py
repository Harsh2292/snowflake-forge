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
import re
import time

import streamlit as st

from utils import ask_guard, config, forge_data, router
from ui import payloads, settings, view
from ui.components import esc, html

log = logging.getLogger("forge")


@st.cache_resource(show_spinner=False)
def _limiter(per_hour: int, per_day: int, concurrent: int) -> ask_guard.AskLimiter:
    """One per process: the limits count every visitor together."""
    return ask_guard.AskLimiter({"per_hour": per_hour, "per_day": per_day, "concurrent": concurrent})


@st.cache_resource(show_spinner=False)
def _answers() -> ask_guard.AnswerCache:
    return ask_guard.AnswerCache()


@st.cache_data(ttl=config.SCREEN_CACHE_SECONDS, show_spinner=False)
def _instant(version: str, metric: str, dimension, order, rank_word: str, value) -> dict:
    """An instant answer, shared by every visitor like the other screens' data."""
    return router.instant_answer(router.Intent(metric, dimension, order, rank_word, value))


@st.cache_data(ttl=config.SCREEN_CACHE_SECONDS, show_spinner=False)
def _learned(version: str) -> dict:
    """The names the semantic view lists (plants, carriers, …), for "fill rate at <plant>".
    Only fetched when a question isn't understood without them. A fallback is never kept."""
    values = router.learn_values()
    if forge_data.pop_notices():  # saved names are fine to read, but retry live next time
        _learned.clear()
    return values


def _setting_on(name: str, default: bool) -> bool:
    value = settings.app_settings().get(name, default)
    return str(value).strip().lower() not in ("false", "0", "no", "off")


def _shortcut_on() -> bool:
    return _setting_on("shortcut", config.ASK_SHORTCUT)


def _stream_allowed() -> bool:
    """Streaming is possible: live, and not switched off in secrets."""
    return forge_data.data_mode() == "live" and _setting_on("stream", config.ASK_STREAM)


def _stream_on() -> bool:
    """...and the visitor's own switch on the Ask screen is on (default on)."""
    return _stream_allowed() and st.session_state.get("ask_stream", True)


STOPPED_NOTE = "Stopped before the answer was finished."


def stopped_turn(partial: dict):
    """The conversation turn for a stopped answer: what was written so far, marked as
    stopped. None when nothing was being answered (the answer finished first)."""
    question = (partial or {}).get("question")
    if not question:
        return None
    text = (partial.get("text") or "").strip() or "The agent hadn't written anything yet."
    result = {"answer": text, "sql": "", "metric_used": [], "verified_query_used": None, "tools_used": [],
              "tables": [], "row_counts": [], "table_titles": [], "suggestions": [], "data_health": None,
              "warnings": [{"message": STOPPED_NOTE}], "status": "stopped", "raw": {"stopped": True},
              "source": "live", "route": "agent"}
    return {"question": question, "parts": [{"question": question, "result": result}]}


def _stop() -> None:
    """The Stop button: the click ends the running answer (Streamlit reruns), and what was
    written so far is kept, marked as stopped. Its limit slot was already counted."""
    turn = stopped_turn(st.session_state.get("ask_partial"))
    if turn:
        st.session_state.chat.append(turn)
    st.session_state.ask_partial = None
    st.session_state.ask_pending = None
    st.session_state.ask_open = None


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


def _answer(parts: list, stream=None) -> list:
    """Each part's result, in order (None where a limit refused it). Instant parts run first,
    on this thread; then the agent parts, all at once. A single agent part is streamed on
    this thread instead: stream = (on_text, on_status) from _thinking (CR-008)."""
    mode = forge_data.data_mode()
    live = mode == "live"
    results = [None] * len(parts)
    waiting = []  # parts that need an agent call
    for i, part in enumerate(parts):
        if part.intent is None:
            cached = _answers().get(part.text, version=payloads.data_version()) if live else None
            if cached is not None:
                results[i] = cached
            else:
                waiting.append(i)

    # Instant parts first, before any agent slot is reserved: if one of them raised after a
    # reservation, that slot would never be released (review #15, 1 Oct).
    version = payloads.data_version()
    for i, part in enumerate(parts):  # the thinking card is on screen meanwhile (_thinking)
        if part.intent is not None:
            start = time.perf_counter()
            intent = part.intent
            result = _instant(version, intent.metric, intent.dimension, intent.order, intent.rank_word,
                              intent.value)
            if result.get("source") == "mock_fallback":
                _instant.clear()  # never keep saved results: the next question retries
            results[i] = {**result, "elapsed": time.perf_counter() - start}

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

    if stream is not None and len(waiting) == 1 and _stream_on():
        start = time.perf_counter()
        try:  # one reservation, as before: a fallback inside it is the same question
            answered = [(forge_data.ask_agent_stream(parts[waiting[0]].text, *stream), None)]
        finally:
            if limiter is not None:
                limiter.release()
        answered = [(answered[0][0], time.perf_counter() - start)]
    else:
        answered = router.run_parallel([ask(parts[i].text) for i in waiting], max_workers=lim["concurrent"])
    for i, (result, seconds) in zip(waiting, answered):
        if result.get("status") == "paused":
            if limiter is not None:
                limiter.pause(config.ASK_PAUSE_SECONDS)
                _refuse("paused", lim, limiter)
            continue
        if live:
            _answers().put(parts[i].text, result, version=payloads.data_version())
        results[i] = {**result, "elapsed": seconds}
    return results


def _ask(question: str, stream=None) -> None:
    question = (question or "").strip()[:config.ASK_MAX_CHARS]
    if not question:
        return
    st.session_state.ask_refused = None
    forge_data.set_visitor(st.session_state.get("visitor"))  # callbacks run before streamlit_app.py sets it
    parts = router.route(question, shortcut=_shortcut_on(), values=lambda: _learned(payloads.data_version()))
    answers = [{"question": part.text, "result": result}
               for part, result in zip(parts, _answer(parts, stream)) if result is not None]
    if answers:
        st.session_state.chat.append({"question": question, "parts": answers})
        st.session_state.ask_open = None  # the previous answer folds into its row
    st.session_state.ask_partial = None  # finished: nothing left for Stop to keep


def _picked() -> None:
    st.session_state.ask_pending = st.session_state.get("ask_pick")  # answered in render()
    st.session_state.ask_pick = None


def _asker(question: str):
    def ask():
        st.session_state.ask_pending = question  # answered in render(), with the thinking card
    return ask


def _clear() -> None:
    st.session_state.chat = []
    st.session_state.ask_open = None


# ── The conversation: the newest answer open, earlier ones folded into rows ──

def _toggle(index: int) -> None:
    st.session_state.ask_open = None if st.session_state.get("ask_open") == index else index


def _cards(turn: dict, t: dict, bubble: bool) -> None:
    """A turn's answer cards: one per part, the question bubble above the first (when shown)."""
    split = len(turn["parts"]) > 1
    for i, part in enumerate(turn["parts"]):
        card = payloads.answer(turn["question"] if bubble and i == 0 else "", part["result"],
                               part=part["question"] if split else "")
        view.render("answer", card, t, height=_card_height(card))


def turn_summary(turn: dict) -> str:
    """The folded row's right-hand side: which path answered, and how long it took."""
    results = [p["result"] for p in turn["parts"]]
    routes = {"Instant" if r.get("route") == "instant" else "Agent" for r in results}
    seconds = [r["elapsed"] for r in results if r.get("elapsed") is not None]
    words = [" + ".join(sorted(routes))]
    if len(results) > 1:
        words.append(f"{len(results)} parts")
    if seconds:
        words.append(f"{max(seconds):.1f} s")
    return " · ".join(words)


def _history(earlier: list, t: dict) -> None:
    """Earlier questions as one row each. A click opens that answer under its row (one at
    a time); asking a new question folds everything again."""
    open_index = st.session_state.get("ask_open")
    rules = []
    for i, turn in enumerate(earlier):
        chevron = "▴" if open_index == i else "▾"
        rules.append(f'.stApp .st-key-hist_{i} button::after {{ content: "{turn_summary(turn)}   {chevron}"; }}')
        if open_index == i:
            rules.append(f".stApp .st-key-hist_{i} button {{ border-color: {t['blue']}; background: {t['sel']}; }}")
    html(f'<style>{"".join(rules)}</style><div class="sf-hist-title">Earlier in this conversation</div>')
    for i, turn in enumerate(earlier):
        label = " · ".join(line.strip() for line in turn["question"].splitlines() if line.strip())
        st.button(label, key=f"hist_{i}", on_click=_toggle, args=(i,), width="stretch")
        if open_index == i:
            _cards(turn, t, bubble=False)
    html('<div class="sf-hist-gap"></div>')


def _chart_height(chart: dict) -> int:
    """answer.html's chart: horizontal bars grow with their rows; period columns are fixed."""
    if chart.get("kind") == "columns":
        return 300
    return 100 + 30 * len(chart["rows"])


def _card_height(card: dict) -> int:
    paragraphs = card["answer"].split("\n\n")
    lines = sum(math.ceil(max(len(line), 1) / 85) for p in paragraphs for line in p.split("\n"))  # conservative
    question_lines = sum(math.ceil(max(len(line), 1) / 60) for line in card["question"].splitlines()) or 1
    return (214 + 28 * lines + 10 * (len(paragraphs) - 1)
            + sum(_chart_height(c) for c in card.get("charts") or ([card["chart"]] if card["chart"] else []))
            + 44 * (len(card["warnings"]) + bool(card.get("health")))
            - (0 if card["question"] else 62) + (30 if card["part"] else 0)
            + 26 * (question_lines - 1)  # a long or multi-line question wraps
            + (40 if card["instant"] else 0))  # its longer header can wrap under its chips


MAX_PILLS = 6


def _next_questions(chat: list) -> list[str]:
    """"Try another": the agent's own follow-up suggestions for the last answer first, then
    the suggested questions not asked yet (limits apply to those the agent answers)."""
    asked = {q for turn in chat for q in [turn["question"], *(p["question"] for p in turn["parts"])]}
    suggested = [q for p in chat[-1]["parts"] for q in p["result"].get("suggestions") or []] if chat else []
    options = [q for q in [*suggested, *config.CANONICAL_QUESTIONS] if q not in asked]
    return list(dict.fromkeys(options))[:MAX_PILLS]


STREAM_REDRAW_SECONDS = 0.08  # the streamed text is redrawn at most this often


def _prose(text: str) -> str:
    """The agent's light markdown as HTML, like answer.html's prose(): escaped first, then
    **bold**, paragraphs and line breaks. A ```code block (the SQL) is left out while streaming."""
    text = re.sub(r"```.*?(```|$)", "", text, flags=re.S)
    paragraphs = [p for p in re.split(r"\n{2,}", text.strip()) if p.strip()]
    return "".join("<p>" + re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", esc(p)).replace("\n", "<br>") + "</p>"
                   for p in paragraphs)


def _thinking(question: str):
    """The asked question and a "thinking" card in the conversation while it's answered
    (1 Oct: the spinner sat outside the conversation). Returns (on_text, on_status): with
    streaming (CR-008) the card shows the agent's progress, then becomes the answer as it's
    written, with a Stop button under it."""
    parts = router.route(question, shortcut=_shortcut_on())
    agent_parts = sum(p.intent is None for p in parts)
    if not agent_parts:
        title, sub = "Querying the governed semantic view", "An instant answer: no AI call needed."
    else:
        many = f" {len(parts)} parts, answered at once." if len(parts) > 1 else ""
        title = "Thinking"
        sub = ("Reading your question, querying the governed semantic view, then writing the answer. "
               "Usually 10 to 30 seconds." + many)
    asked = "<br>".join(esc(line) for line in question.splitlines())  # html() joins lines: keep the breaks
    html(f'<div class="sf-q"><span>{asked}</span></div>')
    box = st.empty()
    state = {"text": "", "status": sub, "drawn": 0.0}
    st.session_state.ask_partial = {"question": question, "text": ""}

    def draw() -> None:
        text = state["text"]
        heading = esc(title) if not text else "Writing the answer"
        body = f'<div class="sub">{esc(state["status"])}</div>' if not text else f'<div class="sf-stream">{_prose(text)}</div>'
        box.markdown(f'<div class="sf-thinking" role="status" aria-live="polite"><span class="av">SC</span>'
                     f'<div class="sf-think-body"><div class="ttl">{heading}<span class="sf-dots"><i></i><i></i><i></i></span></div>'
                     f'{body}</div></div>', unsafe_allow_html=True)

    def on_text(delta: str) -> None:
        state["text"] += delta
        st.session_state.ask_partial = {"question": question, "text": state["text"]}
        now = time.perf_counter()
        if now - state["drawn"] >= STREAM_REDRAW_SECONDS:
            state["drawn"] = now
            draw()

    def on_status(message: str) -> None:
        if not state["text"]:  # the agent's own progress line, until the answer starts
            state["status"] = message.rstrip(".") + "…"
            draw()

    draw()
    if agent_parts == 1 and _stream_on():  # only a streamed answer can be stopped mid-way
        _, right = st.columns([5, 1.2])
        with right:
            st.button("Stop", key="ask_stop", icon=":material/stop_circle:", on_click=_stop, width="stretch")
    return on_text, on_status


def render(t: dict, nav) -> None:
    pending = st.session_state.get("ask_pending")
    _, middle, _ = st.columns([1, 5.2, 1])
    with middle:
        if not st.session_state.chat and not pending:
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
                st.button("New conversation", key="ask_clear", icon=":material/refresh:", on_click=_clear,
                          width="stretch", disabled=bool(pending))
            st.write("")
            chat = st.session_state.chat
            if pending:  # every earlier answer folds while the new one is worked on
                if chat:
                    _history(chat, t)
                stream = _thinking(pending)
                st.session_state.ask_pending = None
                _ask(pending, stream)
                st.rerun()
            *earlier, latest = chat
            if earlier:
                _history(earlier, t)
            _cards(latest, t, bubble=True)
            remaining = _next_questions(chat)
            if remaining:
                st.pills("Try another", remaining, key="ask_pick", on_change=_picked)
        if st.session_state.get("ask_refused"):
            html(f'<div class="sf-alert note" data-ask-limit="1" role="status"><span>{esc(st.session_state.ask_refused)}</span></div>')
        foot, switch = st.columns([4, 1.6], vertical_alignment="center")
        with foot:
            st.caption(f"Answers are grounded in {config.SEMANTIC_VIEW}.")
        if _stream_allowed():  # nothing streams on saved data, so the switch shows only live
            with switch:
                st.toggle("Stream answers", key="ask_stream", value=True,
                          help="Show the agent's answer as it's written. Off: the whole answer appears at once.")

    prompt = st.chat_input("Ask about on-time delivery, fill rate, inventory or landed cost",
                           max_chars=config.ASK_MAX_CHARS)
    if prompt:
        st.session_state.ask_pending = prompt.strip()[:config.ASK_MAX_CHARS]
        st.rerun()
