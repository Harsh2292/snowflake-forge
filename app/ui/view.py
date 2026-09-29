"""Embed an HTML view (ui/views/<name>.html) with its data and the current theme.

Views are self-contained: shared CSS/JS and the data are inlined, nothing loads from the
network except the font files (allowed by the Streamlit-in-Snowflake CSP). Rendered with
st.components.v1.html (Components v1, supported in SiS), so all in-view interaction runs
in the browser without a server round trip.
"""

import json
from functools import lru_cache
from pathlib import Path

import streamlit.components.v1 as components

from .theme import FONT_FACES

VIEWS = Path(__file__).parent / "views"


@lru_cache(maxsize=None)
def _read(name: str) -> str:
    return (VIEWS / name).read_text(encoding="utf-8")


def _json_safe(value):
    """NaN and infinity become null. JSON.parse rejects NaN, so one stray NULL-as-NaN
    from Snowflake would otherwise blank the whole screen."""
    if isinstance(value, float) and value != value or value in (float("inf"), float("-inf")):
        return None
    if isinstance(value, dict):
        return {k: _json_safe(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(v) for v in value]
    return value


def build(name: str, data: dict, tokens: dict) -> str:
    """The full HTML document for one view (also used by tests)."""
    variables = ":root{" + ";".join(f"--{k.replace('_', '-')}:{v}" for k, v in tokens.items()) + "}"
    payload = json.dumps(_json_safe(data), default=str, allow_nan=False).replace("</", "<\\/")
    return (
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        f"<style>{FONT_FACES}{variables}{_read('base.css')}</style></head><body>"
        '<div id="app"></div>'
        f'<script type="application/json" id="forge-data">{payload}</script>'
        f"<script>{_read('base.js')}</script>{_read(name + '.html')}</body></html>"
    )


def render(name: str, data: dict, tokens: dict, height: int) -> None:
    components.html(build(name, data, tokens), height=height, scrolling=True)
