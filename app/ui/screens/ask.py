"""Step 4: ask the Cortex Agent in plain English. Native Streamlit, because every question
needs a server round trip. Each answer is drawn as an HTML answer card (ui/views/answer.html)."""

import math

import streamlit as st

from utils import config, forge_data
from ui import payloads, view
from ui.components import html


def _ask(question: str) -> None:
    question = (question or "").strip()
    if question:
        with st.spinner("Asking the agent…"):
            st.session_state.chat.append({"question": question, "result": forge_data.ask_agent(question)})


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
    lines = math.ceil(len(card["answer"]) / 85)  # conservative: narrower screens wrap more
    return 190 + 28 * lines + (215 if card["chart"] else 0) + 44 * len(card["warnings"])


def render(t: dict, nav) -> None:
    _, middle, _ = st.columns([1, 5.2, 1])
    with middle:
        if not st.session_state.chat:
            html('''<h1 class="sf-h1">Ask a question in plain English</h1>
                <p class="sf-lede">The agent answers from the governed semantic view and shows its working:
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
                card = payloads.answer(turn["question"], turn["result"])
                view.render("answer", card, t, height=_card_height(card))
            asked = {turn["question"] for turn in st.session_state.chat}
            remaining = [q for q in config.CANONICAL_QUESTIONS if q not in asked]
            if remaining:
                st.pills("Try another", remaining, key="ask_pick", on_change=_picked)
        st.caption(f"Answers are grounded in {config.SEMANTIC_VIEW}.")

    prompt = st.chat_input("Ask about on-time delivery, fill rate, inventory or landed cost")
    if prompt:
        _ask(prompt)
        st.rerun()
