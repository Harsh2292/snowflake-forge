"""Supply Chain Forge: governed supply chain analytics, as a guided demo.

Run locally from this folder:  streamlit run streamlit_app.py   (mock data)
The public link runs on Streamlit Community Cloud, live on Snowflake through the
[connections.snowflake] secrets (deploy/RUNBOOK.md). It also runs in Streamlit in Snowflake
(deploy/deploy_app.py). All data comes through utils/forge_data.py; live mode switches on
by itself wherever Snowflake is reachable.

Screens other than Ask are self-contained HTML views (ui/views/), fed by ui/payloads.py.
"""

import streamlit as st

from utils import forge_data
from ui import payloads, settings, theme, view
from ui.components import esc, html, logo
from ui.screens import ask

st.set_page_config(page_title="Supply Chain Forge", page_icon=":material/hub:", layout="wide",
                   initial_sidebar_state="collapsed")
forge_data.configure(settings.connection(), settings.app_settings())

STEPS = [("problem", "The problem"), ("fix", "The fix"), ("same", "Same for everyone"), ("ask", "Ask")]
TOOLS = [("explore", "Explore metrics", ":material/bar_chart:"), ("health", "Data health", ":material/monitor_heart:")]

# step -> (view file, payload builder, iframe height, next button (label, step) or None)
VIEWS = {
    "problem": ("problem", payloads.problem, 850, ("See how we fix it", "fix")),
    "fix": ("fix", payloads.fix, 1200, ("Check every team gets the same number", "same")),
    "same": ("same", payloads.same, 745, ("Ask your own question", "ask")),
    # Explore's height fits its tallest breakdown (12 plants); it has no button below it,
    # so spare space under shorter breakdowns is just page background.
    "explore": ("explore", payloads.explore, 990, None),
    "health": ("health", payloads.health, payloads.health_height, None),  # grows with the checks
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

# Build the screen's data first, so the header can say where it really came from.
step = st.session_state.step
data = None
if step != "ask":
    name, build, height, next_step = VIEWS[step]
    data = build(forge_data.data_mode())
notices = forge_data.pop_notices()
if notices and step != "ask":
    build.clear()  # never keep saved results in the cache: the next visit retries Snowflake


def source_label() -> str:
    if forge_data.data_mode() == "mock":
        return "Mock data"
    return "Saved results" if notices else "Live"  # the banner below says why


# ── Header: brand, the four-step story, tools and the theme switch ───────────
brand, story, tools = st.columns([2.7, 5.0, 3.3], vertical_alignment="center")
with brand:
    html(f'<div class="sf-brand">{logo(t)}<span>Supply Chain Forge</span><span class="sf-tag">{esc(source_label())}</span></div>')
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
html(f'<div style="height:1px;background:{t["line"]};margin:6px 0 8px"></div>')
# Contract §3a: every number covers a stated window, and the data's as-of date is shown.
as_of = payloads.as_of(forge_data.data_mode())
if not as_of and forge_data.data_mode() == "live":
    payloads.as_of.clear()  # a missed date isn't kept for the whole cache period: retry next run
html(f'<div class="sf-asof" style="text-align:right;font-size:13px;color:{t["muted"]};margin:0 0 14px">'
     f'{"Data as of " + esc(as_of) + " · " if as_of else ""}Metrics cover the last 12 months unless stated;'
     f' days of inventory uses the latest snapshot</div>')
# A fallback stays on screen, not only in a toast: the public link must never pass off
# saved results as live ones (C15). Only the fact is shown; the error goes to the log.
if notices:
    html('<div class="sf-alert" data-source="mock_fallback" role="status"><span><b>Live connection paused.</b>'
         ' This screen shows the last captured Snowflake results. It tries Snowflake again on your next click.'
         '</span></div>')

# ── The current screen ───────────────────────────────────────────────────────
if step == "ask":
    ask.render(t, go)
else:
    view.render(name, data, t, height(data) if callable(height) else height)
    if next_step:
        _, right = st.columns([4, 1.25])
        with right:
            st.button(next_step[0], type="primary", key=f"next_{step}", on_click=go, args=(next_step[1],),
                      width="stretch")

for notice in notices + forge_data.pop_notices():
    st.toast(f"Couldn’t reach Snowflake for {notice.label}. Showing the last captured results.",
             icon=":material/cloud_off:")
