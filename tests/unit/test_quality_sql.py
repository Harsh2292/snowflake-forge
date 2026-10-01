"""C10: offline checks on the data-quality SQL (quality/). Claude Code can't run it, so these
catch what can be caught without Snowflake: re-runnable DDL, the headers CoCo relies on, the
check catalogue against DATA_SPEC §4 and §7.2, the names and values the app already uses, and
that SP_DATA_HEALTH builds the §7.2 shape from counts only.
"""

import ast
import json
import re
from pathlib import Path

import pytest

from utils import config, forge_data, mock_data

ROOT = Path(__file__).resolve().parents[2]
QUALITY = ROOT / "quality"
SQL_FILES = sorted(QUALITY.glob("*.sql"))
SPEC = (ROOT / "docs" / "DATA_SPEC.md").read_text(encoding="utf-8")
SETUP = (QUALITY / "00_setup.sql").read_text(encoding="utf-8")
DMFS = (QUALITY / "10_custom_dmfs.sql").read_text(encoding="utf-8")
HEALTH = (QUALITY / "30_sp_data_health.sql").read_text(encoding="utf-8")
SELF_CHECKS = (QUALITY / "40_sp_dq_self_checks.sql").read_text(encoding="utf-8")
RUN = (QUALITY / "99_run.sql").read_text(encoding="utf-8")

FIELDS = ("CHECK_ID", "SORT_ORDER", "ENTITY", "CHECK_NAME", "CODE", "LAYER", "SCHEMA_NAME", "TABLE_NAME", "DMF",
          "COLUMNS", "REF_TABLE", "REF_COLUMN", "EXPECT", "TARGET_RATE", "THRESHOLD_RATE", "HANDLED_BY")


def code_only(text: str) -> str:
    """SQL without -- comments."""
    return "\n".join(line.split("--")[0] for line in text.splitlines())


def catalogue() -> list[dict]:
    block = code_only(SETUP).split("INSERT INTO SUPPLY_CHAIN_FORGE.OPS.DQ_CHECKS", 1)[1].split(";", 1)[0]
    rows = []
    for line in block.splitlines():
        line = line.strip().rstrip(",")
        if line.startswith("('"):
            # SQL NULL → None, but not inside names such as SNOWFLAKE.CORE.NULL_COUNT.
            rows.append(dict(zip(FIELDS, ast.literal_eval(re.sub(r"(?<![\w.'])NULL(?![\w'])", "None", line)))))
    return rows


CAT = catalogue()
CHECKS = [r for r in CAT if r["EXPECT"] in ("ZERO", "MAX_RATE", "INFO")]


def spec_health_example() -> dict:
    section = SPEC.split("### 7.2", 1)[1]
    return json.loads(section.split("```json", 1)[1].split("```", 1)[0])


def sp_body(text: str) -> str:
    return code_only(text.split("AS\n$$", 1)[1].split("$$;", 1)[0])


# ── Files and headers ────────────────────────────────────────────────────────────

def test_the_six_files_exist():
    assert [p.name for p in SQL_FILES] == ["00_setup.sql", "10_custom_dmfs.sql", "20_sp_attach_dmfs.sql",
                                           "30_sp_data_health.sql", "40_sp_dq_self_checks.sql", "99_run.sql"]
    assert (QUALITY / "README.md").is_file()


@pytest.mark.parametrize("path", SQL_FILES, ids=lambda p: p.name)
def test_header_names_card_role_warehouse_and_run_order(path):
    head = path.read_text(encoding="utf-8")[:2500]
    for field in ("Card:", "Role:", "Warehouse:", "Run order:", "Expected:"):
        assert field in head, f"{path.name} header lacks {field}"


@pytest.mark.parametrize("path", SQL_FILES, ids=lambda p: p.name)
def test_ddl_is_rerunnable(path):
    sql = code_only(path.read_text(encoding="utf-8")).upper()
    for create in re.findall(r"\bCREATE\b[^;(]*", sql):
        ok = create.startswith(("CREATE OR REPLACE", "CREATE OR ALTER")) or "IF NOT EXISTS" in create
        assert ok, f"{path.name}: not re-runnable: {create.strip()[:80]}"


@pytest.mark.parametrize("path", SQL_FILES, ids=lambda p: p.name)
def test_dollar_quotes_balance_and_no_session_state(path):
    sql = code_only(path.read_text(encoding="utf-8"))
    assert sql.count("$$") % 2 == 0, f"{path.name}: unbalanced $$"
    assert not re.search(r"\bUSE\s+(ROLE|WAREHOUSE)\b", sql, re.I), f"{path.name}: USE ROLE/WAREHOUSE doesn't carry over"
    assert not re.search(r"^\s*SET\s+\w+\s*=", sql, re.I | re.M), f"{path.name}: session variables don't survive"


def test_custom_dmfs_are_deterministic_and_return_number():
    sql = code_only(DMFS).upper()
    for banned in ("RANDOM(", "UNIFORM(", "CURRENT_DATE", "CURRENT_TIMESTAMP", "SYSDATE", "GETDATE"):
        assert banned not in sql
    functions = re.findall(r"CREATE OR ALTER DATA METRIC FUNCTION SUPPLY_CHAIN_FORGE\.OPS\.(\w+)", sql)
    assert len(functions) == sql.count("RETURNS NUMBER") == 7


# ── The catalogue ───────────────────────────────────────────────────────────────

def test_catalogue_counts_match_the_header():
    assert len(CAT) == 77 and len(CHECKS) == 46
    assert sum(r["EXPECT"] == "VOLUME" for r in CAT) == 21
    assert sum(r["EXPECT"] == "FRESHNESS" for r in CAT) == 10
    assert "77 rows (46 checks, 21 ROW_COUNT" in SETUP


def test_catalogue_keys_are_unique():
    assert len({r["CHECK_ID"] for r in CAT}) == len(CAT)
    # SP_DATA_HEALTH output is matched back to the catalogue on (table, check name).
    assert len({(r["SCHEMA_NAME"], r["TABLE_NAME"], r["CHECK_NAME"]) for r in CHECKS}) == len(CHECKS)


def test_every_check_belongs_to_a_health_entity():
    assert {r["ENTITY"] for r in CHECKS} == set(forge_data.HEALTH_ENTITIES)


def test_each_layer_is_judged_as_the_spec_says():
    for r in CHECKS:
        if r["EXPECT"] == "INFO":
            assert r["LAYER"] == "SOURCE", r  # raw-data defects: expected, always OK
        if r["EXPECT"] == "ZERO":
            assert r["LAYER"] == "CONFORMED", r  # repairs and removals: must be 0
        if r["EXPECT"] == "MAX_RATE":
            assert r["CODE"].startswith("E"), r
            assert r["THRESHOLD_RATE"] == pytest.approx(2 * r["TARGET_RATE"]), r
        if r["CODE"].startswith("M"):
            assert r["EXPECT"] in ("INFO", "ZERO"), r
        assert r["SCHEMA_NAME"].endswith("_SOURCE") == (r["LAYER"] == "SOURCE"), r


def test_edge_case_rates_equal_the_spec():
    for r in (r for r in CHECKS if r["EXPECT"] == "MAX_RATE"):
        row = next(line for line in SPEC.splitlines() if line.startswith(f"| **{r['CODE']}**"))
        assert f"{r['TARGET_RATE'] * 100:g}%" in row, (r["CHECK_ID"], row)


def test_raw_defect_rates_equal_the_spec():
    m01 = next(line for line in SPEC.splitlines() if line.startswith("| **M01**"))
    for r in (r for r in CHECKS if r["CHECK_NAME"] == "duplicate_keys" and r["LAYER"] == "SOURCE"):
        assert f"{r['TABLE_NAME']} {r['TARGET_RATE'] * 100:g}%" in m01, r["CHECK_ID"]
    code_map = SPEC.split("### 4.3", 1)[1].split("###", 1)[0]
    for r in (r for r in CHECKS if r["CODE"] == "M03" and r["LAYER"] == "SOURCE" and r["TARGET_RATE"]):
        row = next(line for line in code_map.splitlines() if f"{r['TABLE_NAME']}.{r['COLUMNS']}" in line)
        assert f"[{r['TARGET_RATE'] * 100:g}%" in row, (r["CHECK_ID"], row)


def test_catalogue_covers_the_spec_minimum_set():
    """DATA_SPEC §7.2 'Minimum set', on both layers."""
    have = {(r["LAYER"], r["TABLE_NAME"], r["DMF"].split(".")[-1], r["COLUMNS"]) for r in CAT}
    want = set()
    for t, c in [("VBAK", "VBELN"), ("VBAP", "LINE_ID"), ("VTTK", "TKNUM"), ("MARD", "INV_KEY"), ("KNA1", "KUNNR")]:
        want.add(("SOURCE", t, "DUPLICATE_COUNT", c))
    for t, c in [("SALES_ORDER", "order_id"), ("ORDER_LINE", "line_id"), ("SHIPMENT", "shipment_id"),
                 ("INVENTORY", "inventory_key"), ("CUSTOMER", "customer_id")]:
        want.add(("CONFORMED", t, "DUPLICATE_COUNT", c))
    for t, c in [("LFA1", "REGIO"), ("KNA1", "REGIO"), ("T001W", "REGION_CD"), ("VBAK", "GBSTK"), ("VBAK", "PRIO"),
                 ("VTTK", "SHP_STATUS"), ("VTTK", "CARRIER_CD"), ("MARA", "MATKL"), ("KNA1", "KTOKD")]:
        want.add(("SOURCE", t, "DMF_NONCONTRACT_CODE_COUNT", c))
    for t, c in [("SUPPLIER", "region"), ("CUSTOMER", "region"), ("PLANT", "region"), ("SALES_ORDER", "order_status"),
                 ("SALES_ORDER", "order_priority"), ("SHIPMENT", "shipment_status"), ("SHIPMENT", "carrier"),
                 ("PART", "category"), ("CUSTOMER", "customer_segment")]:
        want.add(("CONFORMED", t, "DMF_NONCONTRACT_CODE_COUNT", c))
    for layer, rows in [("SOURCE", [("KNA1", "KUNNR, NAME1"), ("LFA1", "LIFNR, NAME1"), ("MARA", "MATNR, MAKTX")]),
                        ("CONFORMED", [("CUSTOMER", "customer_id, customer_name"),
                                       ("SUPPLIER", "supplier_id, supplier_name"), ("PART", "part_id, part_name")])]:
        want |= {(layer, t, "DMF_TEST_RECORD_COUNT", c) for t, c in rows}
    want |= {("SOURCE", "VTTK", "NULL_COUNT", "PROM_DLV_DT"),
             ("CONFORMED", "SHIPMENT", "NULL_COUNT", "promised_delivery_date"),
             ("SOURCE", "VBAP", "DMF_OVERSHIP_COUNT", "KWMENG, QTY_SHIPPED"),
             ("CONFORMED", "ORDER_LINE", "DMF_OVERSHIP_COUNT", "quantity_ordered, quantity_shipped"),
             ("SOURCE", "MARD", "DMF_NEGATIVE_ON_HAND_COUNT", "LABST"),
             ("CONFORMED", "INVENTORY", "DMF_NEGATIVE_ON_HAND_COUNT", "quantity_on_hand"),
             ("CONFORMED", "SHIPMENT", "DMF_COST_OUTLIER_COUNT", "dq_flags"),
             ("SOURCE", "VBAP", "DMF_ORPHAN_ORDER_LINES", "VBELN"), ("SOURCE", "VTTK", "DMF_ORPHAN_SHIPMENTS", "VBELN"),
             ("CONFORMED", "ORDER_LINE", "DMF_ORPHAN_ORDER_LINES", "order_id"),
             ("CONFORMED", "SHIPMENT", "DMF_ORPHAN_SHIPMENTS", "order_id")}
    # FRESHNESS takes no column (ON ()): SNOWFLAKE.CORE.FRESHNESS has no TIMESTAMP_NTZ form,
    # and every LOAD_TS is NTZ (B12 run fix, runs/C10_run.md), so it measures the table's
    # last change instead.
    for t in ("VBAK", "VBAP", "VTTK", "MARD", "TCURR"):
        want.add(("SOURCE", t, "FRESHNESS", None))
    for t in ("SALES_ORDER", "ORDER_LINE", "SHIPMENT", "INVENTORY", "FX_RATE"):
        want.add(("CONFORMED", t, "FRESHNESS", None))
    for t in ("T001W", "LFA1", "MARA", "SOURCING", "MARD", "KNA1", "VBAK", "VBAP", "TCURR", "VTTK"):
        want.add(("SOURCE", t, "ROW_COUNT", None))
    for t in ("SUPPLIER", "PART", "SOURCING", "PLANT", "INVENTORY", "CUSTOMER", "SALES_ORDER", "ORDER_LINE",
              "SHIPMENT", "FX_RATE", "CODE_MAP"):
        want.add(("CONFORMED", t, "ROW_COUNT", None))
    assert want - have == set()


def test_catalogue_columns_are_the_governed_names_in_conformed():
    """CONFORMED columns are the contract §7 names (DATA_SPEC §5.1), plus dq_flags / load_ts."""
    contract = (ROOT / "docs" / "CONTRACT.md").read_text(encoding="utf-8")
    section7 = contract.split("## 7. Governed View Column Names", 1)[1].split("\n## ", 1)[0]
    governed = set(re.findall(r"`([a-z_]+)`", section7)) | {"dq_flags", "load_ts"}
    for r in (r for r in CAT if r["LAYER"] == "CONFORMED" and r["COLUMNS"]):
        for column in r["COLUMNS"].split(", "):
            assert column in governed, (r["CHECK_ID"], column)


def test_two_table_dmfs_name_their_reference_table():
    for r in CAT:
        two_table = r["DMF"].split(".")[-1] in ("DMF_NONCONTRACT_CODE_COUNT", "DMF_ORPHAN_ORDER_LINES",
                                                "DMF_ORPHAN_SHIPMENTS")
        assert (r["REF_TABLE"] is not None) == two_table == (r["REF_COLUMN"] is not None), r["CHECK_ID"]
        if r["REF_TABLE"] and r["REF_TABLE"].startswith("OPS.DQ_VALID_"):
            assert f"CREATE TABLE IF NOT EXISTS SUPPLY_CHAIN_FORGE.{r['REF_TABLE']} (CODE VARCHAR NOT NULL)" in SETUP


# ── Names and values the app already uses ────────────────────────────────────────

def test_custom_dmf_names_match_the_catalogue_and_the_app():
    from ui import payloads

    created = set(re.findall(r"DATA METRIC FUNCTION SUPPLY_CHAIN_FORGE\.OPS\.(\w+)", DMFS))
    used = {r["DMF"].split(".")[-1] for r in CAT if r["DMF"].startswith("OPS.")}
    assert created == used
    assert created <= set(payloads.PLAIN_CHECKS)
    assert {r["DMF"].split(".")[-1] for r in CAT} <= set(payloads.PLAIN_CHECKS)


def test_app_expects_zero_exactly_where_the_catalogue_does():
    """The app's Data health screen and SP_DATA_HEALTH judge a CONFORMED result the same way."""
    zero = {r["DMF"].split(".")[-1] for r in CAT if r["EXPECT"] == "ZERO"}
    not_zero = {r["DMF"].split(".")[-1] for r in CAT if r["LAYER"] == "CONFORMED" and r["EXPECT"] != "ZERO"}
    assert forge_data._QUALITY_EXPECT_ZERO == zero
    assert not (forge_data._QUALITY_EXPECT_ZERO & not_zero)


def valid_codes(table: str) -> list[str]:
    block = SETUP.split(f"INSERT INTO SUPPLY_CHAIN_FORGE.OPS.{table} (CODE)", 1)[1].split(";", 1)[0]
    return re.findall(r"\('([A-Z_]+)'\)", block)


@pytest.mark.parametrize("table, dimension", [
    ("DQ_VALID_REGION", "plants.plant_region"), ("DQ_VALID_ORDER_STATUS", "orders.order_status"),
    ("DQ_VALID_PRIORITY", "orders.order_priority"), ("DQ_VALID_SHIPMENT_STATUS", "shipments.shipment_status"),
    ("DQ_VALID_CATEGORY", "parts.category"), ("DQ_VALID_SEGMENT", "customers.customer_segment")])
def test_valid_codes_are_the_contract_values(table, dimension):
    assert valid_codes(table) == config.DIMENSION_VALUES[dimension]


def test_valid_carriers_are_the_spec_carriers():
    carriers = SPEC.split("### 3.4", 1)[1].split("###", 1)[0]
    listed = [c for c in re.findall(r"^\| `([A-Z_]+)` \|", carriers, re.M) if c != "CARRIER_CD"]  # not the header
    assert valid_codes("DQ_VALID_CARRIER") == listed


# ── SP_DATA_HEALTH ───────────────────────────────────────────────────────────────

def test_data_health_signature():
    assert f"CREATE OR REPLACE PROCEDURE {config.DATA_HEALTH_PROC}(ENTITY VARCHAR)" in HEALTH
    assert re.search(r"RETURNS VARIANT\s+LANGUAGE SQL[\s\S]*?EXECUTE AS OWNER\s+AS\s*\n\$\$", HEALTH)
    for role in config.PERSONA_ROLES.values() if isinstance(config.PERSONA_ROLES, dict) else config.PERSONA_ROLES:
        assert f"SP_DATA_HEALTH(VARCHAR) TO ROLE {role};" in HEALTH


def test_data_health_entities_in_spec_order():
    body = sp_body(HEALTH)
    listed = re.findall(r"\('(\w+)', '[A-Z_]+', '[^']+', \d, '(?:DAILY|REFERENCE)'\)", body)
    assert listed == forge_data.HEALTH_ENTITIES
    accepted = re.search(r"ARRAY_CONSTRUCT\('all', ([^)]*)\)", body).group(1)
    assert re.findall(r"'(\w+)'", accepted) == forge_data.HEALTH_ENTITIES


def test_data_health_builds_every_spec_key():
    example = spec_health_example()
    keys = set(example) | set(example["entities"][0]) | set(example["entities"][0]["checks"][0])
    body = sp_body(HEALTH)
    for key in keys:
        assert f"'{key}'," in body, key
    # Keys stay present with null values: OBJECT_CONSTRUCT would drop them.
    assert "OBJECT_CONSTRUCT(" not in body.replace("OBJECT_CONSTRUCT_KEEP_NULL(", "")


def test_data_health_reads_counts_only():
    body = sp_body(HEALTH).upper()
    reads = re.findall(r"\b(?:FROM|JOIN)\s+([A-Z_.]+)", body)
    tables = {t for t in reads if "." in t}
    assert tables == {"SUPPLY_CHAIN_FORGE.OPS.V_CONFORMED_FACTS", "SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS",
                      "SUPPLY_CHAIN_FORGE.OPS.DQ_CHECKS"}
    assert "EXECUTE IMMEDIATE" not in body  # static SQL only
    for masked in ("PAYMENT_TERMS", "EMAIL", "CUSTOMER_NAME", "UNIT_COST", "CONTRACT_PRICE", "CREDIT_LIMIT"):
        assert masked not in body


def test_facts_view_is_aggregate_only():
    view = code_only(SETUP.split("CREATE OR REPLACE VIEW SUPPLY_CHAIN_FORGE.OPS.V_CONFORMED_FACTS", 1)[1].split(";", 1)[0])
    for select in re.split(r"\bUNION ALL\b", view):
        items = select.split("SELECT", 1)[1].split(" FROM ", 1)[0]
        for item in (i.strip() for i in items.split(",")):
            assert re.match(r"^('[\w]+'|COUNT\(\*\)|MAX\(\w+\)|NULL::DATE)", item), item
    assert view.count("FROM SUPPLY_CHAIN_FORGE.CONFORMED.") == 9


REFERENCE_ENTITIES = {"suppliers", "parts", "sourcing", "plants", "customers"}  # DATA_SPEC §7.2 (fix 1)


def test_reference_entities_are_not_judged_on_age():
    """C16 (freshness fix 1): reference data changes rarely, so it reads REFERENCE, which
    doesn't count toward the status. Daily data keeps the 36 h / 72 h rule."""
    body = sp_body(HEALTH)
    kinds = dict(re.findall(r"\('(\w+)', '[A-Z_]+', '[^']+', \d, '(DAILY|REFERENCE)'\)", body))
    assert {e for e, k in kinds.items() if k == "REFERENCE"} == REFERENCE_ENTITIES
    assert {e for e, k in kinds.items() if k == "DAILY"} == {"orders", "order_lines", "shipments", "inventory"}
    assert "WHEN w.KIND = 'REFERENCE' THEN 'REFERENCE'" in body
    # it is checked before the age rules, and it scores like OK
    assert body.index("THEN 'REFERENCE'") < body.index("<= 36 * 3600")
    assert "DECODE(FRESH_STATUS, 'OK', 0, 'REFERENCE', 0, 'UNKNOWN', 1, 'WARN', 2, 3)" in body
    assert "not judged on age" in body


def test_self_checks_prove_the_reference_rule():
    for check in ("HEALTH_REFERENCE_KINDS", "HEALTH_REFERENCE_NOT_AGED"):
        assert f"'{check}'" in SELF_CHECKS


def test_source_defects_may_measure_a_little_under_the_injected_count():
    """B12: E04 measured 19,390 of 19,589 injected; later repairs can undo a few."""
    assert "VALUE >= INJECTED * 0.95 AND VALUE <= INJECTED * 1.25 + 5" in SELF_CHECKS


def test_data_health_status_rules():
    body = sp_body(HEALTH)
    assert "36 * 3600" in body and "72 * 3600" in body  # freshness OK ≤ 36 h, WARN ≤ 72 h
    assert "DECODE(STATUS, 'OK', 0, 'UNKNOWN', 1, 'WARN', 2, 3)" in body  # OK < UNKNOWN < WARN < FAIL
    assert "> 16000" in body  # the size guard


def test_mock_health_has_the_spec_shape():
    example = spec_health_example()
    mock = mock_data.data_health("shipments")
    assert set(mock) == set(example)
    assert set(mock["entities"][0]) == set(example["entities"][0])
    assert set(mock["entities"][0]["checks"][0]) == set(example["entities"][0]["checks"][0])


def test_self_checks_use_the_spec_keys():
    example = spec_health_example()
    for keys in (set(example), set(example["entities"][0]), set(example["entities"][0]["checks"][0])):
        listed = next(set(re.findall(r"'(\w+)'", group)) for group in re.findall(r"ARRAY_CONSTRUCT\(([^)]*)\)", SELF_CHECKS)
                      if set(re.findall(r"'(\w+)'", group)) >= keys)
        assert listed == keys


# ── The driver ──────────────────────────────────────────────────────────────────

def test_driver_warms_up_then_sets_the_steady_schedule():
    calls = re.findall(r"^CALL (\S+)\((.*)\);", RUN, re.M)
    assert calls[0] == ("SUPPLY_CHAIN_FORGE.OPS.SP_ATTACH_DMFS", "'SUPPLY_CHAIN_FORGE', '5 MINUTE'")
    assert ("SUPPLY_CHAIN_FORGE.OPS.SP_DQ_SELF_CHECKS", "'SUPPLY_CHAIN_FORGE'") in calls
    assert ("SUPPLY_CHAIN_FORGE.OPS.SP_ATTACH_DMFS", "'SUPPLY_CHAIN_FORGE', 'TRIGGER_ON_CHANGES'") in calls
    assert (config.DATA_HEALTH_PROC, "'ALL'") in calls


def test_an_entity_without_checks_is_unknown_not_ok():
    """Review #11 (1 Oct): missing check configuration must not read as healthy."""
    sql = (ROOT / "quality" / "30_sp_data_health.sql").read_text(encoding="utf-8")
    assert "IFF(c.ENTITY IS NULL, 1, c.CHECK_SEV) AS CHECK_SEV" in sql
    assert "COALESCE(c.CHECK_SEV, 0)" not in sql
