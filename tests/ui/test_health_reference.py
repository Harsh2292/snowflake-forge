"""C16: the Data health view shows reference data (freshness_status REFERENCE, DATA_SPEC §7.2
"freshness fix 1") in a neutral tone with a one-line explanation, never in red. The view is
rendered straight from ui/view.build(), so this doesn't need CoCo's re-captured art 10."""

from pathlib import Path

import pytest

from ui import payloads, theme, view

pytestmark = pytest.mark.ui
SCREENSHOTS = Path(__file__).parent / "_screenshots"


def _data() -> dict:
    data = payloads.health("mock")
    tables = []
    for t in data["tables"]:  # what SP_DATA_HEALTH returns after fix 1
        ref = t["name"] in ("Suppliers", "Parts", "Sourcing", "Plants", "Customers")
        tables.append({**t, "freshness": "REFERENCE" if ref else "OK", "status": "OK"})
    return {**data, "tables": tables, "overall": "OK"}


@pytest.mark.parametrize("dark", [False, True], ids=["light", "dark"])
def test_reference_freshness_is_neutral_and_explained(browser, dark):
    tokens = theme.tokens(dark)
    page = browser.new_page(viewport={"width": 1366, "height": payloads.health_height(_data())})
    page.set_content(view.build("health", _data(), tokens))
    table = page.locator("table.tbl")
    reference = table.locator("td", has_text="Reference")
    assert reference.count() == 5
    colours = set(reference.evaluate_all("cells => cells.map((c) => getComputedStyle(c).color)"))
    critical = page.evaluate("(c) => { const s = document.createElement('span'); s.style.color = c;"
                             " document.body.append(s); return getComputedStyle(s).color; }", tokens["critical"])
    assert critical not in colours
    assert page.get_by_text("isn’t judged on age").count() == 1
    assert "REFERENCE" not in table.inner_text()  # shown as a word, not the status code
    SCREENSHOTS.mkdir(exist_ok=True)
    page.screenshot(path=SCREENSHOTS / f"{'dark' if dark else 'light'}-health-reference.png", full_page=True)
    page.close()
