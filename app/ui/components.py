"""Small HTML helpers for the native (Streamlit-drawn) parts: header and Ask."""

import html as _html

import streamlit as st


def logo(t: dict) -> str:
    return (f'<svg width="30" height="30" viewBox="0 0 30 30" fill="none" aria-hidden="true">'
            f'<path d="M3 6 L15 15 M3 15 L15 15 M3 24 L15 15" stroke="{t["src"]}" stroke-width="2.2" stroke-linecap="round"/>'
            f'<path d="M15 15 L27 15" stroke="{t["blue"]}" stroke-width="3.2" stroke-linecap="round"/>'
            f'<circle cx="15" cy="15" r="3.4" fill="{t["blue"]}"/></svg>')


def esc(value) -> str:
    return _html.escape(str(value))


def html(markup: str) -> None:
    """Render HTML. Lines are stripped so Markdown never mistakes indentation for code."""
    st.markdown(" ".join(line.strip() for line in markup.splitlines() if line.strip()), unsafe_allow_html=True)
