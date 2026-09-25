"""Drives the app in a browser: navigation, the current HTML view, screenshots, JS errors."""

from pathlib import Path

from playwright.sync_api import expect

SCREENSHOTS = Path(__file__).parent / "_screenshots"

HEADINGS = {
    "problem": "Four systems, four versions of the truth",
    "fix": "One governed layer every team reads from",
    "same": "Does every team see the same number?",
    "ask": "Ask a question in plain English",
    "explore": "Explore the numbers",
    "health": "Is the data healthy?",
}
PAGE_BACKGROUND = {"light": "rgb(237, 241, 246)", "dark": "rgb(18, 24, 33)"}  # C03 tokens


class App:
    """One browser session on the app: navigation, the current HTML view, and JS errors."""

    def __init__(self, page, theme: str):
        self.page = page
        self.theme = theme
        self.errors = []
        page.on("pageerror", lambda exc: self.errors.append(f"pageerror: {exc}"))
        page.on("console", self._console)

    def _console(self, msg):
        # Streamlit's own bundle logs a harmless "Recording error: Container not found"
        # (st.chat_input's audio widget) when leaving Ask. Only our code's errors count.
        if msg.type == "error" and "/static/js/" not in msg.location.get("url", ""):
            self.errors.append(f"console: {msg.text} ({msg.location.get('url')})")

    def open(self, url: str):
        self.page.goto(url)
        expect(self.view.locator("h1")).to_have_text(HEADINGS["problem"], timeout=30_000)
        if self.theme == "dark":
            self.page.locator(".st-key-dark label").click()
        expect(self.page.locator(".stApp")).to_have_css("background-color", PAGE_BACKGROUND[self.theme])
        return self

    @property
    def view(self):
        """The first embedded HTML view (the screen, or the first answer card on Ask)."""
        return self.page.frame_locator('iframe[data-testid="stIFrame"]').first

    def go(self, step: str):
        self.page.locator(f".st-key-nav_{step} button").click()
        heading = (self.page.locator(".sf-h1, .sf-h2").first if step == "ask" else self.view.locator("h1"))
        expect(heading).to_have_text(HEADINGS[step])
        return self.view

    def screenshot(self, name: str):
        """The whole screen. Streamlit scrolls inside .stMain, not the page, so the window is
        stretched to the content height for the shot and then restored."""
        SCREENSHOTS.mkdir(exist_ok=True)
        size = self.page.viewport_size
        height = self.page.evaluate("(document.querySelector('.stMain') || document.documentElement).scrollHeight")
        self.page.set_viewport_size({"width": size["width"], "height": max(size["height"], height)})
        self.page.wait_for_timeout(300)  # let the layout settle at the new height
        self.page.screenshot(path=SCREENSHOTS / f"{name}.png")
        self.page.set_viewport_size(size)

    def layout_problems(self) -> list[str]:
        """Header and "next" buttons: one row, no label spilling out, no overlaps, no wrapping."""
        return self.page.evaluate("""() => {
          const out = [];
          const items = [...document.querySelectorAll('[class*="st-key-nav_"] button, .st-key-dark label')]
            .map((el) => ({ el, r: el.getBoundingClientRect(), key: el.closest('[class*="st-key-"]').className.match(/st-key-\\w+/)[0] }));
          items.forEach(({ el, r, key }, i) => {
            if (el.scrollWidth > el.clientWidth + 1) out.push(`${key}: label wider than its button`);
            if (Math.abs(r.top - items[0].r.top) > 12) out.push(`${key}: header wrapped to a second row`);
            const next = items[i + 1];
            if (next && r.right > next.r.left) out.push(`${key} overlaps ${next.key}`);
          });
          document.querySelectorAll('[class*="st-key-next_"] button').forEach((b) => {
            if (b.getBoundingClientRect().height > 52) out.push('next button label wraps');
          });
          return out;
        }""")

    def assert_no_errors(self):
        assert not self.errors, "JavaScript errors:\n" + "\n".join(self.errors)
