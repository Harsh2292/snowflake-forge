"""Supply Chain Forge: governed supply chain analytics, as a guided demo.

Run locally from this folder:  streamlit run streamlit_app.py
Deployed to Streamlit in Snowflake as SUPPLY_CHAIN_FORGE.APP.FORGE_DEMO (warehouse runtime).
All data comes through utils/forge_data.py. Flip utils/config.py USE_MOCK_DATA to go live.

Screens other than Ask are self-contained HTML views (ui/views/), fed by ui/payloads.py.
"""

import streamlit as st

from utils import forge_data
from ui import payloads, theme, view
from ui.components import esc, html, logo
from ui.screens import ask

st.set_page_config(page_title="Supply Chain Forge", page_icon=":material/hub:", layout="wide",
                   initial_sidebar_state="collapsed")

STEPS = [("problem", "The problem"), ("fix", "The fix"), ("same", "Same for everyone"), ("ask", "Ask")]
TOOLS = [("explore", "Explore metrics", ":material/bar_chart:"), ("health", "Data health", ":material/monitor_heart:")]

# step -> (view file, payload builder, iframe height, next button (label, step) or None)
VIEWS = {
    "problem": ("problem", payloads.problem, 820, ("See how we fix it", "fix")),
    "fix": ("fix", payloads.fix, 1120, ("Check every team gets the same number", "same")),
    "same": ("same", payloads.same, 745, ("Ask your own question", "ask")),
    # Explore's height fits its tallest breakdown (12 plants); it has no button below it,
    # so spare space under shorter breakdowns is just page background.
    "explore": ("explore", payloads.explore, 990, None),
    "health": ("health", payloads.health, 690, None),
}


def _default_dark() -> bool:
    try:
        return st.context.theme.type == "dark"
    except Exception:
        return False


for key, value in {"step": "problem", "chat": []}.items():
    st.session_state.setdefault(key, value)
st.session_state.setdefault("dark", _default_dark())


def go(step: str) -> None:
    st.session_state.step = step


t = theme.tokens(st.session_state.dark)
st.markdown(theme.page_css(t, st.session_state.step, []), unsafe_allow_html=True)

# ── Header: brand, the four-step story, tools and the theme switch ───────────
brand, story, tools = st.columns([2.7, 5.0, 3.3], vertical_alignment="center")
with brand:
    mode = "Live" if forge_data.data_mode() == "live" else "Mock data"
    html(f'<div class="sf-brand">{logo(t)}<span>Supply Chain Forge</span><span class="sf-tag">{esc(mode)}</span></div>')
with story:
    for col, (i, (key, label)) in zip(st.columns([1.15, 0.9, 1.45, 0.7]), enumerate(STEPS, start=1)):
        with col:
            st.button(label, key=f"nav_{key}", icon=f":material/counter_{i}:", on_click=go, args=(key,),
                      width="stretch")
with tools:
    cols = st.columns([1.35, 1.15, 0.9], vertical_alignment="center")
    for col, (key, label, icon) in zip(cols, TOOLS):
        with col:
            st.button(label, key=f"nav_{key}", icon=icon, on_click=go, args=(key,), width="stretch")
    with cols[2]:
        st.toggle("Dark", key="dark")
html(f'<div style="height:1px;background:{t["line"]};margin:6px 0 24px"></div>')

# ── The current screen ───────────────────────────────────────────────────────
step = st.session_state.step
if step == "ask":
    ask.render(t, go)
else:
    name, build, height, next_step = VIEWS[step]
    view.render(name, build(forge_data.data_mode()), t, height)
    if next_step:
        _, right = st.columns([4, 1.25])
        with right:
            st.button(next_step[0], type="primary", key=f"next_{step}", on_click=go, args=(next_step[1],),
                      width="stretch")

for notice in forge_data.pop_notices():
    st.toast(f"Couldn’t reach Snowflake for {notice.label}. Showing saved practice values.",
             icon=":material/cloud_off:")
