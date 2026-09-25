"""Browser test setup: a local Streamlit server (mock data) and headless Chromium.

Run with `pytest -m ui`. The server starts once per run on a free port and stops after.
Screenshots of every screen go to tests/ui/_screenshots/ (gitignored) for a human look.
"""

import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

import pytest

APP_DIR = Path(__file__).resolve().parents[2] / "app"

try:
    from playwright.sync_api import sync_playwright
except ImportError:  # browser tests need tests/requirements.txt; the rest of the suite doesn't
    collect_ignore = ["test_browser.py"]


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture(scope="session")
def app_url():
    port = _free_port()
    server = subprocess.Popen(
        [sys.executable, "-m", "streamlit", "run", "streamlit_app.py", "--server.headless", "true",
         "--server.port", str(port), "--browser.gatherUsageStats", "false"],
        cwd=APP_DIR, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    url = f"http://localhost:{port}"
    try:
        for _ in range(60):
            try:
                if urllib.request.urlopen(f"{url}/_stcore/health", timeout=1).status == 200:
                    break
            except OSError:
                time.sleep(0.5)
        else:
            pytest.fail("Streamlit server did not start within 30 s")
        yield url
    finally:
        server.terminate()
        try:
            server.wait(10)
        except subprocess.TimeoutExpired:
            server.kill()


@pytest.fixture(scope="session")
def browser():
    with sync_playwright() as p:
        try:
            chromium = p.chromium.launch()
        except Exception as exc:
            pytest.skip(f"Chromium unavailable ({str(exc).splitlines()[0]}); run: python -m playwright install chromium")
        yield chromium
        chromium.close()


@pytest.fixture
def open_app(browser, app_url):
    """open_app(theme, width) → an App on the problem screen in that theme."""
    contexts = []

    from app_driver import App

    def _open(theme: str, width: int = 1366) -> App:
        contexts.append(browser.new_context(viewport={"width": width, "height": 900}))
        return App(contexts[-1].new_page(), theme).open(app_url)

    yield _open
    for context in contexts:
        context.close()


@pytest.fixture(params=["light", "dark"])
def app(request, open_app):
    return open_app(request.param)
