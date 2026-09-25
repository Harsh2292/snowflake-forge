"""The app in a real browser: every screen in light and dark, and the in-view interactions
that unit tests can't see inside the HTML views (C03). Run with `pytest -m ui`."""

import pytest

from app_driver import HEADINGS, expect
from utils import config

pytestmark = pytest.mark.ui


@pytest.mark.parametrize("width", [1280, 1366, 1600])
@pytest.mark.parametrize("theme", ["light", "dark"])
def test_header_reaches_every_screen_without_overflow(open_app, theme, width):
    app = open_app(theme, width)
    for step in HEADINGS:
        view = app.go(step)
        assert not app.layout_problems(), f"{step}: {app.layout_problems()}"
        page_overflow = app.page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
        assert page_overflow <= 0, f"{step}: page scrolls sideways by {page_overflow}px"
        if step != "ask":
            view_overflow = view.locator("body").evaluate("b => b.scrollWidth - b.clientWidth")
            assert view_overflow <= 0, f"{step}: view scrolls sideways by {view_overflow}px"
            cut_off = view.locator("body").evaluate("b => b.scrollHeight - window.innerHeight")
            assert cut_off <= 0, f"{step}: {cut_off}px of the view is cut off at the bottom"
        app.screenshot(f"{theme}-{width}-{step}")
    app.assert_no_errors()


def test_next_buttons_follow_the_story(app):
    for current, following in [("problem", "fix"), ("fix", "same"), ("same", "ask")]:
        app.page.locator(f".st-key-next_{current} button").click()
        heading = app.page.locator(".sf-h1").first if following == "ask" else app.view.locator("h1")
        expect(heading).to_have_text(HEADINGS[following])
    app.assert_no_errors()


def test_problem_column_drawer_filters_and_closes(app):
    view = app.go("problem")
    view.get_by_role("button", name="See every source column").click()
    expect(view.get_by_role("dialog")).to_be_visible()
    all_rows = view.locator(".drawer tbody tr").count()
    view.locator('[data-act="filter"][data-arg="ERP"]').click()
    systems = view.locator(".drawer tbody tr td:first-child").all_inner_texts()
    assert systems and set(systems) == {"ERP"} and len(systems) < all_rows
    view.locator("#drawer-close").click()
    expect(view.get_by_role("dialog")).to_have_count(0)
    app.assert_no_errors()


def test_fix_layer_click_shows_its_detail(app):
    view = app.go("fix")
    view.locator("#layer-source").click()
    expect(view.locator("#layer-source")).to_have_attribute("aria-pressed", "true")
    expect(view.get_by_text("Source layer", exact=True)).to_be_visible()
    app.assert_no_errors()


def test_same_metric_tile_updates_all_three_persona_cards(app):
    view = app.go("same")
    view.locator("#tile-fill_rate").click()
    expected = f"{config.MOCK_METRICS['fill_rate']:.6f}"
    numbers = view.locator("section.g3 .num")
    expect(numbers).to_have_text([expected] * 3)
    expect(view.locator(".banner")).to_contain_text("fill rate")
    view.get_by_role("button", name="See the rows each team gets").click()
    drawer = view.get_by_role("dialog")
    expect(drawer.locator(".h3")).to_have_text([config.PERSONA_LABELS[p] for p in config.PERSONA_ROLES])
    expect(drawer).to_contain_text("*** MASKED ***")
    app.assert_no_errors()


def test_explore_disables_impossible_breakdowns_focuses_bars_and_shows_a_table(app):
    view = app.go("explore")
    view.locator("#t-days_of_inventory").click()
    disabled = view.locator(".pill[disabled]")
    expect(disabled.first).to_be_visible()
    assert "Not available" in disabled.first.get_attribute("title")

    view.locator("#t-on_time_delivery_rate").click()
    bar = view.locator(".barrow").nth(1)
    name = bar.locator(".name").inner_text()
    bar.click()
    expect(view.locator(".barrow").nth(1)).to_have_attribute("aria-pressed", "true")
    expect(view.locator("aside")).to_contain_text(name)

    bars = view.locator(".barrow").count()
    view.locator("#table-switch").click()
    expect(view.locator("table.tbl tbody tr")).to_have_count(bars)
    app.assert_no_errors()


def test_ask_question_card_gives_an_answer_card_with_sql_and_definition(app):
    app.go("ask")
    question = config.CANONICAL_QUESTIONS[1]  # by region: has a chart
    app.page.locator(".st-key-qcard_1 button").click()
    card = app.view
    expect(card.get_by_text(question)).to_be_visible(timeout=15_000)
    expect(card.locator('[role="img"]')).to_have_count(1)
    card.locator("#tab-sql").click()
    expect(card.locator("pre")).to_contain_text(config.SEMANTIC_VIEW)
    card.locator("#tab-definition").click()
    expect(card.get_by_role("tabpanel")).to_contain_text("On-Time Delivery")
    app.assert_no_errors()
