"""The Ask router (C14, C14b): instant answers for known metric questions, and multi-part
questions split into parts that run in parallel. Pure Python, no Streamlit.

Why: the agent takes ~12 s even for its verified queries, and the time is the orchestrator
LLM, not Snowflake (art 08). A question that names one contract metric, and at most one
valid dimension or one dimension value, and nothing else, is a fixed query. It's answered
straight from the governed semantic view with forge_data.get_metric, which builds the
verified queries' own SQL (semantic/01). Anything else goes to the agent.

How a question is read (C14b): its words are looked up in a vocabulary built from the
semantic view's own names and synonyms (utils/vocabulary.json, generated from
semantic/01 by tests/tools/build_vocabulary.py), plus the contract's dimension values and
the names the semantic view returns (plants, carriers, …). Every word must be understood,
or be a harmless filler word; one unknown word sends the question to the agent.

The router never computes a number. It only chooses between two governed paths over the
same semantic view, and the answer card says which one answered.
"""

import difflib
import json
import re
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

import pandas as pd

from . import config, forge_data

VOCABULARY = json.loads(Path(__file__).with_name("vocabulary.json").read_text(encoding="utf-8"))

# ── Words ────────────────────────────────────────────────────────────────────

ASC, DESC = "asc", "desc"
# Ranking words. "worst" and "best" depend on the metric: a high landed cost is bad, and
# days of inventory has no "best" (too low risks stock-outs, too high ties up cash).
LITERAL_RANKING = {"lowest": ASC, "bottom": ASC, "highest": DESC, "top": DESC}
RANK_WORDS = {*LITERAL_RANKING, "worst", "best"}
HIGHER_IS_BETTER = {"on_time_delivery_rate": True, "fill_rate": True, "avg_landed_cost": False,
                    "days_of_inventory": None}
# Words that introduce a breakdown ("by region") or a value ("in APAC").
INTRO_PHRASES = ["by", "per", "for each", "for every", "across", "across all", "in each",
                 "broken down by", "split by", "grouped by"]
VALUE_PREPOSITIONS = {"in", "for", "at", "from"}
# Words that may surround a metric question without changing it. Anything else (a period,
# a number, "why", another language) sends the question to the agent.
FILLER_WORDS = {"what", "what's", "whats", "is", "are", "was", "were", "our", "the", "overall", "current",
                "currently", "show", "me", "give", "tell", "us", "please", "rate", "rates", "of", "a", "an",
                "for", "have", "has", "with", "average", "avg", "how", "does", "do", "look", "looks", "like",
                "can", "could", "would", "you", "i", "want", "to", "see", "know", "all", "each", "every",
                "by"}  # "by" left dangling by "top plants by landed cost"
TYPO_CUTOFF = 0.85  # difflib ratio; "fil" → "fill" is 0.86, "worse" → "worst" only 0.80
TIME_WORDS = ("date", "month", "quarter", "year")  # a time value is a period: the agent's job


def _singular(word: str) -> str:
    if "'" in word or len(word) <= 3 or word.endswith(("ss", "us", "is")):
        return word
    if word.endswith("ies"):
        return word[:-3] + "y"
    return word[:-1] if word.endswith("s") else word


def tokens(text: str) -> list[str]:
    """Lower-case words, singular, with - _ / as spaces: "On-time deliveries" → on time delivery."""
    text = str(text or "").replace("’", "'").lower()
    text = re.sub(r"[-_/]", " ", text)
    return [_singular(t) for t in re.findall(r"[^\s?!.,;:()\"]+", text)]


FILLER = {_singular(w) for w in FILLER_WORDS}


def _words(identifier: str) -> str:
    return identifier.split(".")[-1].replace("_", " ")


def _entity(dimension: str) -> str:
    return dimension.split(".")[0]


def _entity_singular(table: str) -> str:
    return " ".join(tokens(table))


def _remainder(dimension: str) -> str:
    """The dimension's name without its table's name: plants.plant_region → "region"."""
    name, prefix = dimension.split(".")[-1], _entity_singular(_entity(dimension)).replace(" ", "_") + "_"
    return (name[len(prefix):] if name.startswith(prefix) else name).replace("_", " ")


def is_time(dimension: str) -> bool:
    return any(word in dimension.split(".")[-1] for word in TIME_WORDS)


def default_dimension(table: str):
    """"By plant" means plants.plant_name: a table's `<name>_name` dimension, if the contract has one."""
    candidate = f"{table}.{_entity_singular(table).replace(' ', '_')}_name"
    return candidate if candidate in _CONTRACT_DIMENSIONS else None


_CONTRACT_DIMENSIONS = [d for dims in config.DIMENSIONS.values() for d in dims]


def _metric_phrases(key: str) -> list[str]:
    name = _words(key)
    phrases = [name, config.METRICS[key]["label"], *VOCABULARY["metrics"][key]["synonyms"],
               *config.EXTRA_METRIC_PHRASES.get(key, [])]
    words = name.split()
    if words[-1] == "rate" and len(words) > 2:  # "on time delivery rate" → "on time delivery"
        phrases.append(" ".join(words[:-1]))
    if words[0] == "avg":  # "avg landed cost" → "landed cost", "average landed cost"
        phrases += [" ".join(words[1:]), " ".join(["average", *words[1:]])]
    return phrases


def _dimension_phrases(dimension: str) -> list[str]:
    entry = VOCABULARY["dimensions"][dimension]
    table = _entity(dimension)
    remainder = _remainder(dimension)
    prefixes = [_entity_singular(table), *VOCABULARY["tables"].get(table, [])]
    phrases = [_words(dimension), remainder, *entry["synonyms"], *(f"{p} {remainder}" for p in prefixes)]
    if entry["alias"]:
        phrases.append(entry["alias"].replace("_", " "))
    return phrases


@dataclass(frozen=True)
class Word:
    """One recognised phrase: kind is metric / dimension / table / value / intro."""
    kind: str
    key: tuple  # metric: (key,); dimension: candidate dimensions; table: (table,); value: ((dim, value), …)
    text: str


def _index(values: dict | None = None) -> dict:
    """Token tuple → Word. Values win over table synonyms ("DC" is a plant type and a plant
    synonym), and a phrase naming several dimensions keeps them all as candidates."""
    found: dict[tuple, dict] = {}

    def add(phrase, kind, item):
        key = tuple(tokens(phrase))
        if key:
            found.setdefault(key, {}).setdefault(kind, []).append(item)

    for key in config.METRICS:
        for phrase in _metric_phrases(key):
            add(phrase, "metric", key)
    for dimension in _CONTRACT_DIMENSIONS:
        for phrase in _dimension_phrases(dimension):
            add(phrase, "dimension", dimension)
    for table, synonyms in VOCABULARY["tables"].items():
        for phrase in [table, *synonyms]:
            add(phrase, "table", table)
    for phrase in INTRO_PHRASES:
        add(phrase, "intro", phrase)
    all_values = {d: list(v) for d, v in config.DIMENSION_VALUES.items()}
    for dimension, names in (values or {}).items():
        all_values.setdefault(dimension, []).extend(names)
        # a name's first word, when it's distinctive: "FedEx" for "FedEx Freight"
        firsts = [tokens(n)[0] for n in names if tokens(n)]
        for name in names:
            first = tokens(name)[:1]
            if len(tokens(name)) > 1 and firsts.count(first[0]) == 1 and len(first[0]) >= 3:
                add(first[0], "value", (dimension, name))
    for dimension, names in all_values.items():
        if dimension in _CONTRACT_DIMENSIONS and not is_time(dimension):
            for name in names:
                if not str(name).isdigit():  # "3" is a number to the reader, not supplier tier 3
                    add(str(name), "value", (dimension, str(name)))

    index = {}
    for key, kinds in found.items():
        if tuple(key) in {(w,) for w in FILLER} and not {"value", "metric", "intro"} & set(kinds):
            continue  # "all", "each": never a table or dimension on their own
        for kind in ("metric", "value", "dimension", "intro", "table"):  # the order decides a clash
            if kind in kinds:
                items = list(dict.fromkeys(kinds[kind]))
                index[key] = Word(kind, tuple(items), " ".join(key))
                break
    return index


_BASE_INDEX = _index()
_indexes = {}  # values' identity → index (learned values change at most every 12 h)


def _index_for(values):
    if not values:
        return _BASE_INDEX
    key = json.dumps(values, sort_keys=True, default=str)
    if key not in _indexes:
        _indexes.clear()
        _indexes[key] = _index(values)
    return _indexes[key]


def _known_tokens(index) -> list[str]:
    known = {t for key in index for t in key} | FILLER | RANK_WORDS | VALUE_PREPOSITIONS | {"which"}
    return sorted(known)


def _correct(words: list[str], index) -> list[str]:
    """Small typos: an unknown word one close spelling from exactly one known word."""
    known = None
    out = []
    for word in words:
        if len(word) >= 3 and not any(c.isdigit() for c in word) and word not in FILLER \
                and word not in RANK_WORDS and word not in VALUE_PREPOSITIONS and word != "which" \
                and not any(word in key for key in index):
            known = known or _known_tokens(index)
            close = difflib.get_close_matches(word, known, n=2, cutoff=TYPO_CUTOFF)
            if len(close) == 1:
                word = close[0]
        out.append(word)
    return out


def _read(question: str, index) -> list | None:
    """The question as a list of Words and single tokens, longest phrase first; None if
    any word is unknown."""
    words = _correct(tokens(question), index)
    longest = max(map(len, index), default=1)
    items, i = [], 0
    while i < len(words):
        for size in range(min(longest, len(words) - i), 0, -1):
            word = index.get(tuple(words[i:i + size]))
            if word is not None:
                items.append(word)
                i += size
                break
        else:
            token = words[i]
            if token in RANK_WORDS:
                items.append(Word("rank", (token,), token))
            elif token in VALUE_PREPOSITIONS:
                items.append(Word("preposition", (token,), token))
            elif token == "which" or token in FILLER:
                items.append(Word("filler", (token,), token))
            else:
                return None
            i += 1
    return items


# ── Matching ─────────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class Intent:
    """A question the semantic view answers directly: one metric, and at most one dimension,
    optionally ranked (`order` sorts by value, `rank_word` is the question's own word) or
    narrowed to one of its values (`value`: that row of the breakdown)."""
    metric: str
    dimension: str | None = None
    order: str | None = None
    rank_word: str = ""
    value: str | None = None


@dataclass(frozen=True)
class Part:
    """One part of a question. `intent` is None when the agent answers it."""
    text: str
    intent: Intent | None = None


def _pick(candidates, metric: str, phrase: str):
    """One dimension from a phrase's candidates: the ones that pair with the metric (§4);
    if several, the contract's tie-break for that word ("region" → plant region)."""
    valid = [d for d in dict.fromkeys(candidates) if d in config.VALID_PAIRINGS[metric]]
    if len(valid) == 1:
        return valid[0]
    choice = config.DIMENSION_TIEBREAK.get(phrase)
    return choice if choice in valid else None


def _own_tables(metric: str) -> set:
    """Tables a question may name without changing the metric ("fill rate of our orders")."""
    tables = {config.METRICS[metric]["id"].split(".")[0]}
    if metric in config.WINDOW_DATE:
        tables.add(config.WINDOW_DATE[metric].split(".")[0])
    return tables


def match(question: str, values: dict | None = None) -> Intent | None:
    """The question's Intent, only when certain; else None (the agent answers). `values`
    adds dimension values learned from the semantic view ({dimension: [names]})."""
    if not question or len(question) > 200:
        return None
    items = _read(question, _index_for(values))
    if not items:
        return None
    metrics = {w.key[0] for w in items if w.kind == "metric"}
    if len(metrics) != 1:  # none, or several ("A and B" is the splitter's job)
        return None
    metric = metrics.pop()

    dimensions, filters, ranks = [], [], []
    i = 0
    while i < len(items):
        word = items[i]
        after = items[i + 1] if i + 1 < len(items) else None
        if i == 0 and word.text in ("which", "what") and after and after.kind in ("dimension", "table"):
            word = Word("intro", (word.text,), word.text)  # "which plants …"
        elif word.kind in ("metric", "filler"):
            i += 1
            continue
        if word.kind in ("intro", "rank"):
            if word.kind == "rank":
                ranks.append(word.text)
            if after is not None and after.kind == "dimension":
                dimensions.append((after.key, after.text))
                i += 2
                continue
            if after is not None and after.kind == "table":
                default = default_dimension(after.key[0])
                if default:
                    dimensions.append(((default,), after.text))
                elif after.key[0] not in _own_tables(metric):
                    return None  # "by customer": which customer dimension? Ask the agent
                i += 2
                continue
            if word.kind == "intro" and word.text not in ("by", "per"):
                return None
            i += 1  # "top plants by landed cost": the "by" before the metric
            continue
        if word.kind == "preposition":
            after = next((w for w in items[i + 1:] if w.text not in ("the", "our")), None)
            if after is None or after.kind != "value":
                if word.text != "for":
                    return None  # "in 2025", "at night": not something the shortcut knows
                i += 1
                continue
            i += 1
            continue  # the value is read next
        if word.kind == "value":
            before = next((w for w in reversed(items[:i]) if w.text not in ("the", "our")), None)
            candidates = [d for d, _ in word.key]
            used = 1
            # "enterprise customers", "high priority orders": a following dimension or table narrows it
            for follow in items[i + 1:i + 3]:
                if follow.kind == "dimension" and set(follow.key) & set(candidates):
                    candidates = [d for d in candidates if d in follow.key]
                elif follow.kind == "table" and any(_entity(d) == follow.key[0] for d in candidates):
                    candidates = [d for d in candidates if _entity(d) == follow.key[0]]
                else:
                    break
                used += 1
            if used == 1 and (before is None or before.kind != "preposition"):
                return None  # "Is fill rate high?": a bare value word without "in / for …"
            remainders = {_remainder(d) for d in candidates}
            dimension = _pick(candidates, metric, remainders.pop() if len(remainders) == 1 else "")
            if dimension is None:
                return None
            filters.append((dimension, dict(word.key)[dimension]))
            i += used
            continue
        if word.kind == "table" and word.key[0] in _own_tables(metric):
            i += 1  # "fill rate of our orders"
            continue
        return None  # a dimension or table standing alone: ambiguous

    if len(dimensions) + len(filters) > 1 or len(ranks) > 1:
        return None
    dimension = value = None
    if dimensions:
        candidates, phrase = dimensions[0]
        dimension = _pick(candidates, metric, phrase)
        if dimension is None:
            return None  # e.g. on-time delivery by part category: the agent explains why not
    if filters:
        dimension, value = filters[0]
    order, rank_word = None, ""
    if ranks:
        if dimension is None or value is not None:
            return None
        rank_word = ranks[0]
        if rank_word in LITERAL_RANKING:
            order = LITERAL_RANKING[rank_word]
        else:
            higher_better = HIGHER_IS_BETTER[metric]
            if higher_better is None:
                return None  # "best days of inventory" needs a judgement: ask the agent
            order = DESC if (rank_word == "best") == higher_better else ASC
    return Intent(metric, dimension, order, rank_word, value)


LEARN_MAX_ROWS = 100  # a dimension with more members than this isn't learned (part names)


def learnable_dimensions() -> list[tuple[str, str]]:
    """(dimension, a metric it pairs with) for the dimensions whose members the semantic
    view itself lists: no contract value list, not a period, and some metric pairs with it."""
    out = []
    for dimension in _CONTRACT_DIMENSIONS:
        if dimension in config.DIMENSION_VALUES or is_time(dimension):
            continue
        metric = next((m for m in config.METRICS if dimension in config.VALID_PAIRINGS[m]), None)
        if metric:
            out.append((dimension, metric))
    return out


def learn_values() -> dict:
    """{dimension: [member names]} from the semantic view's own breakdowns (the queries the
    Explore screen runs), so new plants and carriers are understood without a code change."""
    values = {}
    for dimension, metric in learnable_dimensions():
        frame = forge_data.get_metric(metric, dimension)
        column = config.column_name(dimension)
        names = [n for n in frame[column].tolist() if isinstance(n, str) and n.strip()]
        if 0 < len(names) <= LEARN_MAX_ROWS:
            values[dimension] = sorted(set(names))
    return values


# ── Splitting ────────────────────────────────────────────────────────────────

MAX_PARTS = 4
# A part that points back at another part can't be answered on its own.
BACK_REFERENCES = {"it", "its", "that", "those", "these", "them", "they", "their", "same", "above",
                   "previous"}
_ENUMERATED = re.compile(r"(?:^|\s)\(?([1-9])[.)]\s+")
_PREAMBLE = re.compile(r"(?:(?:two|three|four|\d|a few|some|several|multiple|a couple of)\s+)?questions?\s*:?")


def _enumerated(text: str):
    """The numbered parts; [] if not numbered; None if numbered but not safe to split."""
    pieces = _ENUMERATED.split(text)
    preamble, numbers, parts = pieces[0].strip(), pieces[1::2], pieces[2::2]
    if len(parts) < 2 or numbers != [str(i) for i in range(1, len(parts) + 1)]:
        return []
    if preamble and not _PREAMBLE.fullmatch(preamble.lower()):
        return None  # "For APAC: 1) … 2) …" carries context every part needs
    return parts


def _questions(text: str) -> list[str]:
    pieces = re.split(r"(?<=\?)\s+", text)
    return pieces if all(p.rstrip().endswith("?") for p in pieces) else []


def _conjoined(text: str) -> list[str]:
    """ "A and B" (or "A, B and C") only when every side is a question the shortcut knows."""
    pieces = re.split(r"\s*,\s*(?:and\s+)?|\s+and\s+", text.strip().rstrip("?.! "))
    return pieces if all(match(p) for p in pieces) else []


def split(question: str) -> list[str]:
    """The parts of a multi-part question, on clear boundaries only; else [question]."""
    text = (question or "").strip()
    if _enumerated(text) is None:
        return [text]
    for splitter in (_enumerated, lambda t: t.split(";"), _questions,
                     lambda t: re.split(r"\s+and also\s+", t), _conjoined):
        parts = [p.strip() for p in splitter(text) if p.strip()]
        if len(parts) > 1:
            break
    else:
        return [text]
    if len(parts) > MAX_PARTS:
        return [text]
    if any(set(re.findall(r"[a-z']+", p.lower())) & BACK_REFERENCES for p in parts[1:]):
        return [text]
    return parts


def route(question: str, shortcut: bool = True, values=None) -> list[Part]:
    """The question's parts, each marked with its Intent where the shortcut answers it.
    `values` (a dict, or a function returning one) adds the names the semantic view lists;
    it's only called when a part isn't understood without them, so the suggested questions
    never wait for it. With the shortcut off, the whole question goes to the agent."""
    if not shortcut:
        return [Part(question)]
    parts = []
    for text in split(question):
        intent = match(text)
        if intent is None and values is not None:
            if callable(values):
                values = values()
            intent = match(text, values)
        parts.append(Part(text, intent))
    return parts


# ── Instant answers ──────────────────────────────────────────────────────────

SENTENCE_NAME = {"on_time_delivery_rate": "on-time delivery rate", "fill_rate": "fill rate",
                 "days_of_inventory": "days of inventory", "avg_landed_cost": "average landed cost"}
WINDOW_PHRASE = {"on_time_delivery_rate": "over the last 12 months, by ship date",
                 "fill_rate": "over the last 12 months, by order date",
                 "days_of_inventory": "at the latest inventory snapshot",
                 "avg_landed_cost": "over the last 12 months, by ship date"}
DIMENSION_WORDING = {"parts.category": "product category"}  # the rest is derived
RANKED_SHOWN = 3  # the sentence names this many; the chart and table show every row
INSTANT_LABEL = "Instant answer · governed semantic view"


def _wording(dimension: str) -> tuple[str, str]:
    """(singular, plural) for sentences: plants.plant_region → region; plants.plant_name →
    plant; customers.customer_region → customer region (plain "region" means the plant's)."""
    words = DIMENSION_WORDING.get(dimension) or _remainder(dimension)
    if words == "name":
        words = _entity_singular(_entity(dimension))
    shared = sum(_remainder(d) == words for d in _CONTRACT_DIMENSIONS) > 1
    if shared and config.DIMENSION_TIEBREAK.get(words) != dimension:
        words = _words(dimension)
    plural = words[:-1] + "ies" if words.endswith("y") else words + "s"
    return words, plural


def _label(value) -> str:
    if value is None or (isinstance(value, float) and value != value):
        return config.MISSING
    if isinstance(value, pd.Timestamp):
        return f"{value:%Y-%m-%d}"
    return str(value)


def _sentence(intent: Intent, records: list[dict], dim_col: str, metric_col: str) -> str:
    key = intent.metric
    name, window = SENTENCE_NAME[key], WINDOW_PHRASE[key]
    value = lambda r: config.format_value(key, r[metric_col])  # noqa: E731
    if intent.dimension is None:
        return f"{name.capitalize()}: **{value(records[0])}** {window}." if records else \
            f"No {name} could be measured {window}."
    singular, plural = _wording(intent.dimension)
    if intent.value is not None:
        row = _row(records, dim_col, intent.value)
        shown = value(row) if row else config.MISSING
        return f"{name.capitalize()} for {intent.value} ({singular}): **{shown}** {window}."
    measured = [r for r in records if r[metric_col] is not None]
    if not measured:
        return f"No {name} could be measured by {singular} {window}."
    if intent.order:
        shown = measured[:RANKED_SHOWN]
        names = [f"**{r[dim_col]}** ({value(r)})" for r in shown]
        listed = names[0] if len(names) == 1 else ", ".join(names[:-1]) + " and " + names[-1]
        which = plural if len(shown) > 1 else singular
        return f"The {which} with the {intent.rank_word} {name} {window}: {listed}."
    if len(measured) == 1:
        return f"{name.capitalize()} by {singular} {window}: **{measured[0][dim_col]}** at {value(measured[0])}."
    best = max(measured, key=lambda r: r[metric_col])
    worst = min(measured, key=lambda r: r[metric_col])
    return (f"{name.capitalize()} by {singular} {window}: highest **{best[dim_col]}** at {value(best)}, "
            f"lowest **{worst[dim_col]}** at {value(worst)}.")


def _row(records: list[dict], dim_col: str, value: str):
    """The breakdown row of one value, matched without regard to case."""
    return next((r for r in records if str(r[dim_col]).casefold() == str(value).casefold()), None)


def instant_answer(intent: Intent) -> dict:
    """The shortcut's answer, in the shape agent_response.parse_agent_response returns, so
    the same answer card draws it. The number is forge_data.get_metric's: the contract query
    with the §3a default window, exactly what the verified queries run. A value question
    ("fill rate in APAC") reads that value's row of the breakdown, so it's the same query
    and the same number as "fill rate by region"; the chart shows the whole breakdown."""
    frame = forge_data.get_metric(intent.metric, intent.dimension)
    metric_col = config.column_name(config.METRICS[intent.metric]["id"])
    dim_col = config.column_name(intent.dimension) if intent.dimension else None
    records = [{**({dim_col: _label(row[dim_col])} if dim_col else {}),
                metric_col: config.as_number(row[metric_col])} for _, row in frame.iterrows()]
    if intent.order:  # measured values ranked; groups with nothing to measure last
        records.sort(key=lambda r: (r[metric_col] is None,
                                    (r[metric_col] or 0) * (1 if intent.order == ASC else -1)))
    label = config.METRICS[intent.metric]["label"]
    title = None
    if intent.dimension:
        title = f"{label} by {_wording(intent.dimension)[0].title()}"
        if intent.order:
            title += f", {intent.rank_word} first"
    return {
        "answer": _sentence(intent, records, dim_col, metric_col),
        "sql": forge_data.build_metric_sql(intent.metric, intent.dimension),
        "metric_used": [intent.metric], "verified_query_used": None,
        "tools_used": [], "tools_raw": [],
        "tables": [records], "row_counts": [len(records)], "table_titles": [title],
        "suggestions": [], "data_health": None, "warnings": [], "status": "completed",
        "raw": {"route": "instant", "semantic_view": config.SEMANTIC_VIEW,
                "metric": config.METRICS[intent.metric]["id"], "dimension": intent.dimension,
                "ranked": intent.order, "value": intent.value, "rows": len(records)},
        "route": "instant",
        "source": frame.attrs.get("source", forge_data.data_mode()),
    }


# ── Parallel agent parts ─────────────────────────────────────────────────────

def run_parallel(jobs: list, max_workers: int) -> list:
    """Run the jobs (no-argument callables) at once and return their results in order. Each
    result is (value, seconds taken). forge_data's fallback notices are per thread, so a
    worker's notices are handed back to the calling thread, where the UI reads them."""
    if not jobs:
        return []

    def timed(job):
        start = time.perf_counter()
        value = job()
        return value, time.perf_counter() - start, forge_data.pop_notices()

    with ThreadPoolExecutor(max_workers=max(1, min(max_workers, len(jobs))),
                            thread_name_prefix="forge-ask") as pool:
        outcomes = list(pool.map(timed, jobs))
    for _, _, notices in outcomes:
        forge_data.add_notices(notices)
    return [(value, seconds) for value, seconds, _ in outcomes]
