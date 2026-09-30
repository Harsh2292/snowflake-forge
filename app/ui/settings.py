"""Streamlit secrets, read safely (C15). Without a secrets file (local dev, CI, SiS) every
section is empty. The shape: .streamlit/secrets.toml.example at the repo root."""

import streamlit as st


def _section(*path) -> dict:
    try:
        node = st.secrets
        for name in path:
            node = node[name]
        return {k: v for k, v in node.items()}
    except Exception:  # no secrets file, no such section, or a malformed file
        return {}


def connection() -> dict:
    """[connections.snowflake]: account, user, role, warehouse, private_key, ..."""
    return _section("connections", "snowflake")


def app_settings() -> dict:
    """[forge]: mode ("live" / "mock") and any config.ASK_LIMITS override."""
    return _section("forge")
