"""Keep the public Community Cloud app awake and its caches warm (C15).

Opens the public URL in headless Chromium, wakes the app if it's asleep, then clicks
through every screen, so each screen's queries are cached for the next visitor. Exits 1 if
the app doesn't load, a screen never finishes running, shows a Streamlit error, or shows
the "live connection paused" banner, so GitHub emails the repo owner.

    python .github/scripts/keep_awake.py https://<app>.streamlit.app
"""

import re
import sys
import time

from playwright.sync_api import sync_playwright

SCREENS = ["The fix", "Same for everyone", "Ask", "Explore metrics", "Data health", "The problem"]
WAKE = re.compile(r"get this app back up", re.I)
FALLBACK = 'data-source="mock_fallback"'


def find(page, name, timeout: float):
    """The first button with this accessible name in any frame (the app sits in an iframe)."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        for frame in page.frames:
            button = frame.get_by_role("button", name=name)
            if button.count():
                return button.first
        page.wait_for_timeout(1000)
    return None


def settle(page, timeout: float = 120) -> bool:
    """Wait until Streamlit has finished running (its status widget is gone). False if it
    is still running after `timeout` seconds (review #19: a hang used to pass silently)."""
    page.wait_for_timeout(2000)
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not any(f.locator('[data-testid="stStatusWidget"]').count() for f in page.frames):
            return True
        page.wait_for_timeout(1000)
    return False


def crashed(page) -> bool:
    """A Streamlit exception box on the page (an uncaught error in a screen)."""
    return any(f.locator('[data-testid="stException"]').count() for f in page.frames)


def problem(page, settled: bool) -> str | None:
    if not settled:
        return "still running after 2 minutes"
    if crashed(page):
        return "Streamlit error"
    if fell_back(page):
        return "live connection paused"
    return None


def fell_back(page) -> bool:
    return any(FALLBACK in frame.content() for frame in page.frames)


def main(url: str) -> int:
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1440, "height": 900})
        page.goto(url, wait_until="domcontentloaded", timeout=120_000)
        wake = find(page, WAKE, 15)
        if wake:
            print("The app was asleep: waking it")
            wake.click()
        if find(page, re.compile("The problem"), 300) is None:
            print("FAIL: the app didn't load within 5 minutes")
            return 1
        first = problem(page, settle(page))
        failed = [f"The problem (first load): {first}"] if first else []
        for label in SCREENS:
            button = find(page, re.compile(re.escape(label)), 60)
            if button is None:
                print(f"FAIL: no '{label}' button")
                return 1
            button.click()
            issue = problem(page, settle(page))
            if issue:
                failed.append(f"{label}: {issue}")
            print(f"  {label}: {issue or 'ok'}")
        browser.close()
    if failed:
        print(f"FAIL: {'; '.join(failed)}")
        return 1
    print("OK: awake, every screen live, caches warm")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2 or not sys.argv[1].startswith(("https://", "http://localhost")):
        sys.exit("usage: keep_awake.py https://<app>.streamlit.app")
    sys.exit(main(sys.argv[1]))
