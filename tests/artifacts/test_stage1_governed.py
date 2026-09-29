"""C6a: the governed layer as Snowflake really built it (CoCo's B07 / B07b artifacts)
matches the contract, and the app shows it correctly.

  03_governed_columns.json   INFORMATION_SCHEMA columns and masking policies of GOVERNED.*
  04_persona_outputs.json    what SP_SAMPLE_AS_* returned, and its result columns

The §6 masking checks on artifact 04 run in tests/governance/test_masking.py as [replay].
Any mismatch here is a Change Request (CONTRACT.md §11), never a silent edit to config.py.
"""

import pandas as pd
import pytest
import streamlit as st

from ui import payloads
from utils import config, forge_data, mock_data

PERSONAS = list(config.PERSONA_ROLES)
NUMBER_COLUMNS = {"UNIT_COST", "CREDIT_LIMIT", "CONTRACT_PRICE"}  # §5.4 "Type" column


@pytest.fixture
def governed(artifact):
    return artifact("03_governed_columns.json")["payload"]


@pytest.fixture
def samples(artifact):
    return artifact("04_persona_outputs.json")["payload"]


# ── Artifact 03: governed views ──────────────────────────────────────────────

def test_governed_views_have_the_contract_columns_in_order(governed):
    by_view = {}
    for col in sorted(governed["columns"], key=lambda c: (c["view"], c["ordinal_position"])):
        by_view.setdefault(col["view"], []).append(col["column_name"].lower())
    assert by_view == config.GOVERNED_COLUMNS
    assert governed["view_count"] == len(config.GOVERNED_COLUMNS)
    assert governed["column_count"] == sum(map(len, config.GOVERNED_COLUMNS.values()))


def test_masking_policies_sit_on_exactly_the_section_6_columns(governed):
    policed = {f"{p['view']}.{p['column_name'].lower()}" for p in governed["masking_policies"]}
    assert policed == set(config.MASKING_MATRIX)
    assert {p["policy_kind"] for p in governed["masking_policies"]} == {"MASKING_POLICY"}


def test_only_the_shipment_view_has_a_promised_date(governed):
    """The ERP promised date (ERDAT) never reaches the governed layer; TMS is authoritative."""
    views = {c["view"] for c in governed["columns"] if "PROMISED" in c["column_name"]}
    assert views == {"V_SHIPMENT"}


# ── Artifact 04: persona sample procedures ───────────────────────────────────

@pytest.mark.parametrize("persona", PERSONAS)
def test_each_procedure_is_owned_by_its_persona_role(samples, persona):
    output = samples[persona.upper()]
    assert output["owner"] == config.PERSONA_ROLES[persona]
    assert output["procedure"] == f"{config.PERSONA_SAMPLE_PROCS[persona]}()"


@pytest.mark.parametrize("persona", PERSONAS)
def test_result_columns_and_types_match_section_5_4(samples, persona):
    columns = samples[persona.upper()]["result_columns"]
    assert [c["name"] for c in columns] == config.SAMPLE_COLUMNS
    for c in columns:
        assert c["type"].startswith("NUMBER" if c["name"] in NUMBER_COLUMNS else "VARCHAR"), c


def test_all_three_personas_see_the_same_rows(samples):
    """Only the masked values differ, so the comparison is like for like."""
    ids = {p: [(r["SAMPLE_PART_ID"], r["SAMPLE_SUPPLIER_ID"], r["SAMPLE_CUSTOMER_ID"])
               for r in samples[p.upper()]["rows"]] for p in PERSONAS}
    assert ids["Planner"] == ids["Buyer"] == ids["Logistics"]
    assert len(ids["Planner"]) > 0


def test_captured_as_the_app_owner_without_secondary_roles(artifact):
    """Masking came from the procedures' owner roles, not from roles the caller holds."""
    capture = artifact("04_persona_outputs.json")
    assert capture["caller_role"] == "FORGE_ADMIN"
    assert capture["caller_secondary_roles"] == ""


# ── The app on the captured rows ─────────────────────────────────────────────

@pytest.mark.parametrize("forge", ["replay"], indirect=True)
@pytest.mark.parametrize("persona", PERSONAS)
def test_offline_demo_shows_exactly_what_snowflake_returned(forge, persona):
    """mock_data's sample rows equal artifact 04 as read through the live code path."""
    live = forge.get_masking_divergence(persona)
    assert live.attrs["source"] == "live"
    pd.testing.assert_frame_equal(live, mock_data.masking_sample(persona))


CHIPS = {"Customer names": "V_CUSTOMER.customer_name", "Unit cost": "V_PART.unit_cost",
         "Payment terms": "V_SUPPLIER.payment_terms", "Credit limit": "V_CUSTOMER.credit_limit"}
FIELDS = {"Unit cost": "V_PART.unit_cost", "Contract price": "V_SOURCING.contract_price",
          "Payment terms": "V_SUPPLIER.payment_terms", "Customer name": "V_CUSTOMER.customer_name",
          "Customer email": "V_CUSTOMER.email", "Credit limit": "V_CUSTOMER.credit_limit"}


@pytest.fixture
def same_screen(forge):
    st.cache_data.clear()
    data = payloads.same("replay")
    forge_data.pop_notices()  # the metric grid falls back until SP_METRICS_AS_* exist (B08)
    return data


@pytest.mark.parametrize("forge", ["replay"], indirect=True)
def test_same_screen_chips_follow_the_real_rows(same_screen):
    for persona, card in zip(PERSONAS, same_screen["personas"]):
        seen = {c["label"]: c["visible"] for c in card["visibility"]}
        assert seen == {label: config.MASKING_MATRIX[row][persona] == "visible" for label, row in CHIPS.items()}


@pytest.mark.parametrize("forge", ["replay"], indirect=True)
def test_rows_drawer_shows_each_real_record_masked_per_team(same_screen):
    records = same_screen["records"]
    assert [r["ids"][0]["cells"][0]["text"] for r in records] == ["MAT000001", "MAT000002", "MAT000003"]
    for record in records:
        for ids in record["ids"]:  # same record for all three teams
            assert len({c["text"] for c in ids["cells"]}) == 1
        assert [f["label"] for f in record["fields"]] == list(FIELDS)
        for field in record["fields"]:
            masked = [c["masked"] for c in field["cells"]]
            assert masked == [config.MASKING_MATRIX[FIELDS[field["label"]]][p] != "visible" for p in PERSONAS]
    buyer = {f["label"]: f["cells"][1]["text"] for f in records[0]["fields"]}
    assert buyer["Unit cost"] == "42.01" and buyer["Payment terms"] == "2/10 NET30"
    assert buyer["Customer name"] == "masked"
