"""C14: the Ask router. Instant answers for known metric questions, multi-part questions
split and answered in parallel, and "Ask is paused" when the Cortex budget switches the agent
off.

The safety claims, each tested here:
- the shortcut fires only where the agent itself used the same contract metric and
  dimension (all 30 art 08 questions), and runs the verified queries' own SQL (semantic/01)
- it never fires for refusals, clarifications, lookups, periods, filters or free text
- agent parts run at once: a question takes as long as its slowest part
"""

import re
import time
from pathlib import Path

import pytest
import streamlit as st
from streamlit.testing.v1 import AppTest

from utils import ask_guard, config, forge_data, router
from ui import payloads

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app" / "streamlit_app.py"
I = router.Intent


def _squash(sql: str) -> str:
    sql = re.sub(r"\s+", " ", sql).strip()
    return re.sub(r"\(\s+", "(", re.sub(r"\s+\)", ")", sql))


# ── The matcher ──────────────────────────────────────────────────────────────

CANONICAL = {
    config.CANONICAL_QUESTIONS[0]: I("on_time_delivery_rate"),
    config.CANONICAL_QUESTIONS[1]: I("on_time_delivery_rate", "plants.plant_region"),
    config.CANONICAL_QUESTIONS[2]: I("on_time_delivery_rate", "orders.order_year_quarter"),
    config.CANONICAL_QUESTIONS[3]: I("fill_rate"),
    config.CANONICAL_QUESTIONS[4]: I("fill_rate", "parts.category"),
    config.CANONICAL_QUESTIONS[5]: I("days_of_inventory", "plants.plant_name"),
    config.CANONICAL_QUESTIONS[6]: I("avg_landed_cost", "plants.plant_region"),
    config.CANONICAL_QUESTIONS[7]: I("on_time_delivery_rate", "plants.plant_name", router.ASC, "worst"),
}


@pytest.mark.parametrize("question", config.CANONICAL_QUESTIONS)
def test_every_suggested_question_takes_the_shortcut(question):
    assert router.match(question) == CANONICAL[question]


def _verified_queries() -> dict:
    text = (ROOT / "semantic" / "01_semantic_view.sql").read_text(encoding="utf-8")
    return dict(re.findall(r"QUESTION '([^']+)'.*?SQL '([^']+)'", text, re.S))


@pytest.mark.parametrize("question", config.CANONICAL_QUESTIONS)
def test_the_shortcut_runs_the_verified_querys_own_sql(question):
    """Same SQL as the agent's verified query, so the same number. The worst-plants query
    ranks with ORDER BY … LIMIT 3; the shortcut ranks the same rows in Python."""
    verified = _squash(_verified_queries()[question])
    intent = router.match(question)
    ours = _squash(forge_data.build_metric_sql(intent.metric, intent.dimension))
    body = lambda sql: sql.split(") ORDER BY")[0]  # noqa: E731
    assert body(ours) == body(verified)
    if intent.order:
        assert verified.endswith(f"ORDER BY {config.column_name(config.METRICS[intent.metric]['id']).lower()} ASC LIMIT 3")
    else:
        assert ours == verified


@pytest.mark.parametrize("question, intent", [
    ("what's our OTD?", I("on_time_delivery_rate")),
    ("On time delivery rate", I("on_time_delivery_rate")),
    ("Show me delivery performance by plant", I("on_time_delivery_rate", "plants.plant_name")),
    ("OTD per carrier", I("on_time_delivery_rate", "shipments.carrier")),
    ("on-time delivery for each customer segment", I("on_time_delivery_rate", "customers.customer_segment")),
    ("What is on-time delivery by customer region?", I("on_time_delivery_rate", "customers.customer_region")),
    ("Which regions have the best on-time delivery?", I("on_time_delivery_rate", "plants.plant_region", router.DESC, "best")),
    ("fill rate across all plants", I("fill_rate", "plants.plant_name")),
    ("Fill rate by part category", I("fill_rate", "parts.category")),
    ("fill rate by order priority", I("fill_rate", "orders.order_priority")),
    ("What is the fill rate broken down by quarter?", I("fill_rate", "orders.order_year_quarter")),
    ("Which product categories have the lowest fill rate?", I("fill_rate", "parts.category", router.ASC, "lowest")),
    ("Can you show me our fill rate?", I("fill_rate")),
    ("DOI by plant", I("days_of_inventory", "plants.plant_name")),
    ("What is our inventory cover by region?", I("days_of_inventory", "plants.plant_region")),
    ("Days of inventory for each product category", I("days_of_inventory", "parts.category")),
    ("Which plants have the highest days of inventory?", I("days_of_inventory", "plants.plant_name", router.DESC, "highest")),
    ("What is our average landed cost?", I("avg_landed_cost")),
    ("landed cost per shipment", I("avg_landed_cost")),
    ("What is average landed cost by carrier?", I("avg_landed_cost", "shipments.carrier")),
    ("Which carriers have the worst landed cost?", I("avg_landed_cost", "shipments.carrier", router.DESC, "worst")),
    ("Top plants by landed cost", I("avg_landed_cost", "plants.plant_name", router.DESC, "top")),
    ("How does fill rate look by plant type?", I("fill_rate", "plants.plant_type")),
])
def test_variants_that_take_the_shortcut(question, intent):
    assert router.match(question) == intent


@pytest.mark.parametrize("question", [
    "What is on-time delivery rate by part category?",       # not a §4 pairing (art 08 Q30)
    "What are days of inventory by carrier?",                 # not a §4 pairing
    "What is fill rate by supplier region?",                  # suppliers.* pairs with no metric
    "What was on-time delivery rate last quarter?",           # a period
    "What is our fill rate in 2025?",
    "What is fill rate over the last 12 months?",
    "fill rate by region and plant",                          # two dimensions
    "What is fill rate by region by quarter?",
    "What are the best days of inventory by plant?",          # "best" needs a judgement
    "What is our best fill rate?",                            # a ranking with nothing to rank
    "Why did on-time delivery drop?",                         # a why
    "Is on-time delivery getting worse?",
    "Compare fill rate and on-time delivery by region",       # two metrics
    "What is our average freight cost per shipment?",         # not a contract metric
    "How are we doing?",
    "हमारी कुल समय पर डिलीवरी दर क्या है?",                   # another language: the agent
    "Are we delivering on time for enterprise customers?",
    "Top 3 plants by fill rate",                              # a number: the agent
    "",
])
def test_everything_else_goes_to_the_agent(question):
    assert router.match(question) is None


def _art08() -> list[dict]:
    path = ROOT / "docs" / "artifacts" / "08_agent_answers.md"
    if not path.exists():
        pytest.skip("art 08 not captured yet")
    out = []
    for block in re.split(r"^### ", path.read_text(encoding="utf-8"), flags=re.M)[1:]:
        head = re.match(r"(Q\d\d) · (\w+)", block)
        question = re.search(r"^\*\*Question\*\*: (.*)$", block, re.M)
        if head and question:
            sql = re.search(r"\*\*Agent SQL\*\*[^\n]*\n\s*````sql\n(.*?)\n````", block, re.S)
            out.append({"id": head[1], "category": head[2], "question": question[1],
                        "sql": sql[1] if sql else ""})
    return out


def _used(sql: str) -> set:
    """(metric key, dimension) pairs in the agent's queries: its SEMANTIC_VIEW queries, and
    Analyst's own SQL for an overall metric (Q23 computes `AS avg_landed_cost` by hand)."""
    by_id = {m["id"].lower(): k for k, m in config.METRICS.items()}
    pairs = set()
    for dims, metrics in re.findall(r"SEMANTIC_VIEW\(\S+\s+(?:DIMENSIONS\s+(\S+)\s+)?METRICS\s+(\S+)", sql, re.I):
        pairs.add((by_id.get(metrics.lower()), dims.lower() or None))
    if "GROUP BY" not in sql.upper():
        pairs |= {(key, None) for key in config.METRICS if re.search(rf"\bAS {key}\b", sql, re.I)}
    return pairs


def test_no_false_shortcut_on_the_30_evaluation_questions(monkeypatch):
    """Every art 08 question: the shortcut fires only where the agent answered with the same
    contract metric and dimension, and never for refusals, clarifications or lookups. With
    every learned name loaded too (C14b), so plant and carrier names can't trigger it."""
    monkeypatch.setattr(config, "USE_MOCK_DATA", True)
    learned = router.learn_values()
    rows = _art08()
    assert len(rows) == 30
    fired = {}
    for row in rows:
        for part in router.route(row["question"], values=learned):
            if part.intent is None:
                continue
            fired.setdefault(row["id"], []).append(part.intent)
            assert row["category"] in {"CANONICAL", "COST", "MULTI_PART"}, row
            assert (part.intent.metric, part.intent.dimension) in _used(row["sql"]), row
    assert set(fired) == {f"Q{i:02d}" for i in range(1, 9)} | {"Q19", "Q22", "Q23"}
    assert len(fired["Q22"]) == 2 and len(fired["Q23"]) == 1  # Q23's count part goes to the agent


# ── The splitter ─────────────────────────────────────────────────────────────

@pytest.mark.parametrize("question, parts", [
    ("1. What is our on-time delivery rate? 2. What is our fill rate?",
     ["What is our on-time delivery rate?", "What is our fill rate?"]),
    ("Two questions: 1) What is our average landed cost per shipment? 2) How many shipments did we send in the last 12 months?",
     ["What is our average landed cost per shipment?", "How many shipments did we send in the last 12 months?"]),
    ("What is our fill rate? How many suppliers do we have?", ["What is our fill rate?", "How many suppliers do we have?"]),
    ("fill rate by region; OTD by plant", ["fill rate by region", "OTD by plant"]),
    ("What is fill rate by region and also how many orders are open?",
     ["What is fill rate by region", "how many orders are open?"]),
    ("What is fill rate by region and on-time delivery by plant?",
     ["What is fill rate by region", "on-time delivery by plant"]),
    ("What is our OTD and fill rate?", ["What is our OTD", "fill rate"]),
])
def test_multi_part_questions_split_on_clear_boundaries(question, parts):
    assert router.split(question) == parts


@pytest.mark.parametrize("question", [
    "Does order priority make a difference to on-time delivery? Show the on-time delivery rate by order priority.",
    "Which carrier shipped order ORD000261581, and on what date was it delivered?",
    "Which plant has the worst OTD? What is its fill rate?",       # "its": part 2 needs part 1
    "For APAC: 1) What is fill rate? 2) What is OTD?",              # context every part needs
    "fill rate by region and plant",
    "How many orders are open and shipped?",
    "What is our fill rate?",
])
def test_everything_else_stays_one_question(question):
    assert router.split(question) == [question.strip()]


def test_with_the_shortcut_off_the_whole_question_goes_to_the_agent():
    question = "1. What is our on-time delivery rate? 2. What is our fill rate?"
    assert router.route(question, shortcut=False) == [router.Part(question)]


# ── Instant answers ──────────────────────────────────────────────────────────

@pytest.mark.parametrize("forge", ["mock", "replay"], indirect=True)
@pytest.mark.parametrize("question", config.CANONICAL_QUESTIONS)
def test_instant_answers_carry_the_governed_numbers(forge, question):
    intent = router.match(question)
    result = router.instant_answer(intent)
    assert not forge_data.pop_notices(), "fell back to saved data"
    frame = forge_data.get_metric(intent.metric, intent.dimension)
    metric_col = config.column_name(config.METRICS[intent.metric]["id"])
    expected = sorted(config.as_number(v) for v in frame[metric_col] if config.as_number(v) is not None)
    got = sorted(r[metric_col] for r in result["tables"][0] if r[metric_col] is not None)
    assert got == expected
    assert result["source"] == ("mock" if forge.mode == "mock" else "live")
    assert result["route"] == "instant" and result["metric_used"] == [intent.metric]
    assert result["sql"] == forge_data.build_metric_sql(intent.metric, intent.dimension)
    card = payloads.answer(question, result)
    assert card["instant"] and card["via"] == router.INSTANT_LABEL and card["answer"]
    assert card["definitions"][0]["id"] == config.METRICS[intent.metric]["id"]
    assert (card["chart"] is not None) == (intent.dimension is not None)


@pytest.mark.parametrize("forge", ["replay"], indirect=True)
def test_the_worst_plants_are_ranked_worst_first_and_named(forge):
    result = router.instant_answer(router.match(config.CANONICAL_QUESTIONS[7]))
    rows = result["tables"][0]
    values = [r["ON_TIME_DELIVERY_RATE"] for r in rows if r["ON_TIME_DELIVERY_RATE"] is not None]
    assert values == sorted(values)
    worst = rows[0]
    assert result["answer"].startswith("The plants with the worst on-time delivery rate")
    assert f"**{worst['PLANT_NAME']}** ({config.format_value('on_time_delivery_rate', worst['ON_TIME_DELIVERY_RATE'])})" in result["answer"]
    assert result["table_titles"] == ["On-Time Delivery by Plant, worst first"]


def test_instant_sentences_state_the_value_and_window(monkeypatch):
    monkeypatch.setattr(config, "USE_MOCK_DATA", True)
    overall = router.instant_answer(router.match("What is our fill rate?"))
    value = config.format_value("fill_rate", overall["tables"][0][0]["FILL_RATE"])
    assert overall["answer"] == f"Fill rate: **{value}** over the last 12 months, by order date."
    by_region = router.instant_answer(router.match("What is on-time delivery rate by region?"))
    assert by_region["answer"].startswith("On-time delivery rate by region over the last 12 months, by ship date: highest **")
    doi = router.instant_answer(router.match("What are days of inventory by plant?"))
    assert "at the latest inventory snapshot" in doi["answer"]


# ── Parallel agent parts ─────────────────────────────────────────────────────

def test_parallel_parts_take_as_long_as_the_slowest():
    def slow(seconds, value):
        def job():
            time.sleep(seconds)
            return value
        return job

    start = time.perf_counter()
    results = router.run_parallel([slow(0.6, "a"), slow(0.3, "b"), slow(0.5, "c")], max_workers=3)
    total = time.perf_counter() - start
    assert [value for value, _ in results] == ["a", "b", "c"]  # in the question's order
    assert 0.6 <= total < 1.0, f"took {total:.2f} s: not in parallel (sum 1.4 s)"
    assert results[0][1] >= 0.6


def test_a_workers_fallback_notice_reaches_the_ui_thread():
    def job():
        forge_data._notices().append(forge_data.Notice("ask_agent", "offline"))
        return "x"

    forge_data.pop_notices()
    router.run_parallel([job], max_workers=1)
    assert [n.label for n in forge_data.pop_notices()] == ["ask_agent"]


# ── Ask is paused (CoCo's ask: the Cortex budget revokes USAGE on the agent) ─

class _Refused:
    def sql(self, sql, params=None):
        raise RuntimeError("SQL compilation error: Agent 'SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT' "
                           "does not exist or not authorized.")


def test_a_revoked_agent_is_paused_not_a_fallback(monkeypatch):
    monkeypatch.setattr(config, "USE_MOCK_DATA", False)
    monkeypatch.setattr(forge_data, "_session", _Refused())
    forge_data.pop_notices()
    result = forge_data.ask_agent("How many suppliers do we have?")
    assert result["status"] == "paused" and result["source"] == "live"
    assert forge_data.pop_notices() == []  # no "Live connection paused" banner
    cache = ask_guard.AnswerCache()
    cache.put("q", result)
    assert cache.get("q") is None


def test_a_paused_limiter_refuses_until_the_pause_ends():
    clock = type("Clock", (), {"now": 1_000.0, "__call__": lambda self: self.now})()
    limiter = ask_guard.AskLimiter(config.ASK_LIMITS, clock=clock)
    limiter.pause(config.ASK_PAUSE_SECONDS)
    assert limiter.try_acquire() == "paused"
    clock.now += config.ASK_PAUSE_SECONDS
    assert limiter.try_acquire() is None


# ── The Ask screen ───────────────────────────────────────────────────────────

def _app(secrets=None, **state) -> AppTest:
    st.cache_data.clear()
    st.cache_resource.clear()
    at = AppTest.from_file(str(APP), default_timeout=30)
    for name, value in (secrets or {}).items():
        at.secrets[name] = value
    at.session_state["step"] = "ask"
    for name, value in state.items():
        at.session_state[name] = value
    return at.run()


def _markdown(at) -> str:
    return "\n".join(m.value for m in at.markdown)


@pytest.fixture
def fake_agent(forge, monkeypatch):
    """Replay data (live, no fallback) with a fake agent that takes 0.4 s and counts calls."""
    calls = []

    def ask_agent(question, role=None):
        calls.append(question)
        time.sleep(0.4)
        return {"answer": f"Answer to {question}", "sql": "", "metric_used": [], "verified_query_used": False,
                "tools_used": [], "tables": [], "row_counts": [], "warnings": [], "suggestions": [],
                "status": "completed", "raw": {}, "source": "live"}

    monkeypatch.setattr(forge_data, "ask_agent", ask_agent)
    return calls


@pytest.mark.parametrize("forge", ["replay"], indirect=True)
def test_a_suggested_question_answers_instantly_with_no_agent_call(fake_agent):
    at = _app()
    at.button(key="qcard_1").click().run()
    assert not at.exception
    turn = at.session_state["chat"][0]
    result = turn["parts"][0]["result"]
    assert fake_agent == [] and "ask_calls" not in at.session_state  # no limit counted it
    assert result["route"] == "instant" and result["source"] == "live" and result["elapsed"] < 5
    assert 'data-source="mock_fallback"' not in _markdown(at)


@pytest.mark.parametrize("forge", ["replay"], indirect=True)
def test_a_two_part_question_answers_both_parts_in_parallel(fake_agent):
    question = "1) How many suppliers do we have? 2) How many orders are open right now?"
    at = _app()
    at.chat_input[0].set_value(question).run()
    assert not at.exception
    turn = at.session_state["chat"][0]
    assert turn["question"] == question
    assert [p["question"] for p in turn["parts"]] == ["How many suppliers do we have?",
                                                      "How many orders are open right now?"]
    assert sorted(fake_agent) == sorted(p["question"] for p in turn["parts"])
    assert all(p["result"]["elapsed"] < 0.8 for p in turn["parts"])
    assert at.session_state["ask_calls"] == 2  # each agent part counts


@pytest.mark.parametrize("forge", ["replay"], indirect=True)
def test_a_mixed_question_uses_both_paths(fake_agent):
    question = "Two questions: 1) What is our average landed cost per shipment? 2) How many shipments did we send in the last 12 months?"
    at = _app()
    at.chat_input[0].set_value(question).run()
    parts = at.session_state["chat"][0]["parts"]
    assert [p["result"].get("route", "agent") for p in parts] == ["instant", "agent"]
    assert fake_agent == ["How many shipments did we send in the last 12 months?"]


@pytest.mark.parametrize("forge", ["replay"], indirect=True)
def test_the_secrets_switch_turns_the_shortcut_off(fake_agent):
    at = _app({"forge": {"shortcut": False}})
    at.button(key="qcard_1").click().run()
    assert fake_agent == [config.CANONICAL_QUESTIONS[1]]


@pytest.mark.parametrize("forge", ["replay"], indirect=True)
def test_ask_is_paused_with_a_plain_message_and_instant_answers_keep_working(forge, monkeypatch):
    session = forge_data.get_session()
    real_sql = session.sql

    def sql(statement, params=None):
        if statement == forge_data.build_agent_sql():
            return _Refused().sql(statement)
        return real_sql(statement, params)

    monkeypatch.setattr(session, "sql", sql)
    at = _app()
    at.chat_input[0].set_value("How many suppliers do we have?").run()
    page = _markdown(at)
    assert at.session_state["chat"] == []
    assert "Ask is paused" in page and "still answer instantly" in page
    assert 'data-source="mock_fallback"' not in page  # not the fallback banner
    at.chat_input[0].set_value(config.CANONICAL_QUESTIONS[0]).run()  # still answers
    assert at.session_state["chat"][0]["parts"][0]["result"]["route"] == "instant"


# ── C14b: the vocabulary comes from the semantic view ───────────────────────

import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location("build_vocabulary", ROOT / "tests" / "tools" / "build_vocabulary.py")
build_vocabulary = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(build_vocabulary)


def test_vocabulary_json_is_exactly_the_builder_output():
    """If this fails after a change to semantic/01: run tests/tools/build_vocabulary.py."""
    on_disk = (ROOT / "app" / "utils" / "vocabulary.json").read_text(encoding="utf-8")
    assert on_disk == build_vocabulary.render(build_vocabulary.build())


def test_the_vocabulary_follows_the_semantic_view(monkeypatch):
    """A synonym CoCo adds to the view becomes a word the shortcut knows, with no code change."""
    vocabulary = {**router.VOCABULARY, "dimensions": {**router.VOCABULARY["dimensions"]}}
    vocabulary["dimensions"]["shipments.carrier"] = {"alias": "carrier", "synonyms": ["haulier"]}
    monkeypatch.setattr(router, "VOCABULARY", vocabulary)
    monkeypatch.setattr(router, "_BASE_INDEX", router._index())
    assert router.match("OTD by haulier") == I("on_time_delivery_rate", "shipments.carrier")


@pytest.mark.parametrize("metric, dimension", [(m, d) for m, dims in config.VALID_PAIRINGS.items() for d in dims])
def test_every_contract_pairing_is_reachable_by_its_own_name(metric, dimension):
    question = f"What is {config.METRICS[metric]['label']} by {router._words(dimension)}?"
    assert router.match(question) == I(metric, dimension)


@pytest.mark.parametrize("question, intent", [
    ("OTD by facility", I("on_time_delivery_rate", "plants.plant_name")),
    ("on-time deliveries by site", I("on_time_delivery_rate", "plants.plant_name")),
    ("fill rate by client segment", I("fill_rate", "customers.customer_segment")),
    ("service level by plant type", I("fill_rate", "plants.plant_type")),
    ("landed cost by transporter", I("avg_landed_cost", "shipments.carrier")),
    ("all-in cost by consignment status", I("avg_landed_cost", "shipments.shipment_status")),
    ("days of supply by SKU category", I("days_of_inventory", "parts.category")),
    ("on time delivery by customer region", I("on_time_delivery_rate", "customers.customer_region")),
    ("fill rate by status", I("fill_rate", "orders.order_status")),  # only order status pairs
    ("fill rate by order quarter", I("fill_rate", "orders.order_quarter")),
    ("fill rate of our orders by region", I("fill_rate", "plants.plant_region")),
])
def test_words_from_the_semantic_view(question, intent):
    assert router.match(question) == intent


@pytest.mark.parametrize("question, intent", [
    ("What is fill rate in APAC?", I("fill_rate", "plants.plant_region", value="APAC")),
    ("OTD for APAC customers", I("on_time_delivery_rate", "customers.customer_region", value="APAC")),
    ("on-time delivery for enterprise customers", I("on_time_delivery_rate", "customers.customer_segment", value="ENTERPRISE")),
    ("fill rate for high priority orders", I("fill_rate", "orders.order_priority", value="HIGH")),
    ("fill rate for raw materials", I("fill_rate", "parts.category", value="RAW_MATERIAL")),
    ("landed cost for delivered shipments", I("avg_landed_cost", "shipments.shipment_status", value="DELIVERED")),
    ("days of inventory at our DC sites", I("days_of_inventory", "plants.plant_type", value="DC")),
    ("What is the fill rate for the EMEA region?", I("fill_rate", "plants.plant_region", value="EMEA")),
])
def test_one_value_questions(question, intent):
    assert router.match(question) == intent


@pytest.mark.parametrize("question", [
    "Is fill rate high?",                        # a value word without "in / for …"
    "OTD by status",                             # order or shipment status: ask
    "fill rate by name",                         # plant, part or supplier name
    "What is fill rate by category in APAC?",    # a breakdown and a filter
    "worst plants in APAC for fill rate",
    "OTD for APAC and EMEA",
    "fill rate for customers",                   # which customer dimension?
    "fill rate by customer",
    "OTD for delivered",                         # order or shipment status
    "What is fill rate in Q3?",                  # a period
    "What was fill rate in 2025?",
    "on time delivery is worse",
    "OTD for Mumbai",                            # not a name the view knows
])
def test_c14b_still_sends_these_to_the_agent(question, monkeypatch):
    monkeypatch.setattr(config, "USE_MOCK_DATA", True)
    assert router.match(question) is None
    assert router.match(question, router.learn_values()) is None


@pytest.mark.parametrize("question, intent", [
    ("What's our fil rate?", I("fill_rate")),
    ("days of inventroy by plant", I("days_of_inventory", "plants.plant_name")),
    ("on-time delivrey by region", I("on_time_delivery_rate", "plants.plant_region")),
    ("landed cost by carier", I("avg_landed_cost", "shipments.carrier")),
])
def test_small_typos_are_forgiven(question, intent):
    assert router.match(question) == intent


# ── C14b: names the semantic view lists ─────────────────────────────────────

@pytest.mark.parametrize("forge", ["mock", "replay"], indirect=True)
def test_names_are_learned_from_the_semantic_view(forge):
    values = router.learn_values()
    assert not forge_data.pop_notices()
    plants = forge_data.get_metric("on_time_delivery_rate", "plants.plant_name")["PLANT_NAME"].tolist()
    assert values["plants.plant_name"] == sorted(plants)
    assert "shipments.carrier" in values and "parts.part_name" not in values  # too many to learn
    plant = plants[0]
    carrier = values["shipments.carrier"][0]
    assert router.match(f"What is on-time delivery at {plant}?", values) == \
        I("on_time_delivery_rate", "plants.plant_name", value=plant)
    assert router.match(f"landed cost for {carrier.replace('_', ' ').lower()}", values) == \
        I("avg_landed_cost", "shipments.carrier", value=carrier)


def test_names_are_only_fetched_when_a_question_needs_them():
    calls = []

    def load():
        calls.append(1)
        return {"plants.plant_name": ["Singapore Logistics Gateway"]}

    assert router.route(config.CANONICAL_QUESTIONS[1], values=load)[0].intent is not None
    assert calls == []
    part = router.route("OTD at Singapore Logistics Gateway", values=load)[0]
    assert part.intent == I("on_time_delivery_rate", "plants.plant_name", value="Singapore Logistics Gateway")
    assert calls == [1]


@pytest.mark.parametrize("forge", ["mock", "replay"], indirect=True)
@pytest.mark.parametrize("intent", [
    I("fill_rate", "plants.plant_region", value="APAC"),
    I("on_time_delivery_rate", "customers.customer_segment", value="ENTERPRISE"),
    I("avg_landed_cost", "orders.order_priority", value="HIGH"),
    I("fill_rate", "orders.order_status", value="OPEN"),  # NULL by definition (CR-005): "—"
])
def test_a_value_answer_is_that_row_of_the_breakdown(forge, intent):
    result = router.instant_answer(intent)
    assert not forge_data.pop_notices()
    frame = forge_data.get_metric(intent.metric, intent.dimension)
    dim_col = config.column_name(intent.dimension)
    metric_col = config.column_name(config.METRICS[intent.metric]["id"])
    row = frame[frame[dim_col] == intent.value].iloc[0]
    expected = config.format_value(intent.metric, row[metric_col])
    assert f"for {intent.value} (" in result["answer"] and f"**{expected}**" in result["answer"]
    assert result["sql"] == forge_data.build_metric_sql(intent.metric, intent.dimension)  # no new SQL
    assert result["raw"]["value"] == intent.value


@pytest.mark.parametrize("forge", ["replay"], indirect=True)
def test_a_plant_name_question_answers_instantly_on_the_ask_screen(fake_agent):
    plant = forge_data.get_metric("days_of_inventory", "plants.plant_name")["PLANT_NAME"].iloc[0]
    at = _app()
    at.chat_input[0].set_value(f"What are days of inventory at {plant}?").run()
    assert not at.exception
    result = at.session_state["chat"][0]["parts"][0]["result"]
    assert fake_agent == [] and result["route"] == "instant" and result["source"] == "live"
    assert result["answer"].startswith(f"Days of inventory for {plant} (plant): **")
