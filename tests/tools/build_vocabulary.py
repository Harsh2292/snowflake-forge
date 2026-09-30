"""Build app/utils/vocabulary.json from the semantic view's own definition (C14b).

The Ask router (app/utils/router.py) recognises metric and dimension words. Rather than a
hand-written list, it uses the words CoCo already wrote into the semantic view: every
contract metric's and dimension's name, alias and WITH SYNONYMS, and each table's synonyms.
The app can't read semantic/ once deployed (only app/ is uploaded), so they're copied here.
Never edit vocabulary.json by hand: after a change to semantic/01_semantic_view.sql, run

    .venv/Scripts/python tests/tools/build_vocabulary.py

tests/unit/test_router.py fails when the file and the semantic view disagree.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "semantic" / "01_semantic_view.sql"
OUT = ROOT / "app" / "utils" / "vocabulary.json"
sys.path.insert(0, str(ROOT / "app"))

from utils import config  # noqa: E402  (the contract's metrics and dimensions)


def _block(sql: str, name: str, following: str) -> str:
    found = re.search(rf"^  {name} \(\n(.*?)^  {following}\b", sql, re.S | re.M)
    if not found:
        raise ValueError(f"semantic view: no {name} block")
    return found.group(1)


def _entries(block: str, head: str) -> dict:
    """{name: entry text} for each entry of a block (entries start at 4 spaces)."""
    pattern = rf"^ {{4}}({head})\s+(?:AS|LABELS)\b(.*?)(?=^ {{4}}{head}\s+(?:AS|LABELS)\b|\Z)"
    return {m[1]: m[2] for m in re.finditer(pattern, block, re.S | re.M)}


def _synonyms(entry: str) -> list[str]:
    found = re.search(r"WITH SYNONYMS \(([^)]*)\)", entry)
    return re.findall(r"'([^']*)'", found.group(1)) if found else []


def _alias(entry: str):
    """`plants.plant_region AS region` → "region"; an expression has no alias."""
    found = re.match(r"\s*([A-Za-z_]\w*)\s*(?:$|\n|WITH|COMMENT)", entry)
    return found.group(1).lower() if found else None


def build() -> dict:
    sql = SOURCE.read_text(encoding="utf-8")
    tables = _entries(_block(sql, "TABLES", "RELATIONSHIPS"), r"\w+")
    dimensions = _entries(_block(sql, "DIMENSIONS", "METRICS"), r"\w+\.\w+")
    metrics = _entries(_block(sql, "METRICS", "COMMENT"), r"\w+\.\w+")

    out = {"source": "semantic/01_semantic_view.sql", "tables": {}, "metrics": {}, "dimensions": {}}
    for name, entry in tables.items():
        out["tables"][name] = _synonyms(entry)
    for key, metric in config.METRICS.items():
        if metric["id"] not in metrics:
            raise ValueError(f"contract metric {metric['id']} is not in the semantic view")
        out["metrics"][key] = {"id": metric["id"], "synonyms": _synonyms(metrics[metric["id"]])}
    for dimension in (d for dims in config.DIMENSIONS.values() for d in dims):
        if dimension not in dimensions:
            raise ValueError(f"contract dimension {dimension} is not in the semantic view")
        entry = dimensions[dimension]
        out["dimensions"][dimension] = {"alias": _alias(entry), "synonyms": _synonyms(entry)}
    return out


def render(vocabulary: dict) -> str:
    return json.dumps(vocabulary, indent=2, ensure_ascii=False) + "\n"


if __name__ == "__main__":
    OUT.write_text(render(build()), encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}")
