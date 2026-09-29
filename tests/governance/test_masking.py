"""Contract §6 masking matrix, one test per row, checked per persona through the §5.4
sample procedures (SP_SAMPLE_AS_*), which run under each persona's own role. Since v1.3
(CR-004) the samples carry all six masked columns.

Each check also runs as [replay]: the rows CoCo captured from Snowflake (artifact 04)
through the app's live code path (C6a).
"""

import pytest

from utils import config

PERSONAS = list(config.PERSONA_ROLES)

with_replay = pytest.mark.parametrize(
    "forge", ["mock", pytest.param("live", marks=pytest.mark.live), "replay"], indirect=True)


def assert_masking(forge, persona, matrix_row, column):
    df = forge.get_masking_divergence(persona)
    assert len(df) > 0, "sample procedure returned no rows"
    expected = config.MASKING_MATRIX[matrix_row][persona]
    values = df[column]
    if expected == "visible":
        assert values.notna().all(), f"{persona} should see {matrix_row}, got NULL"
        assert not values.astype(str).str.startswith("***").any(), f"{persona} should see {matrix_row} unmasked"
    elif expected is None:
        assert values.isna().all(), f"{persona} should get NULL for {matrix_row}, got {values.tolist()}"
    else:
        assert (values == expected).all(), f"{persona} should get {expected!r} for {matrix_row}, got {values.tolist()}"


@with_replay
@pytest.mark.parametrize("persona", PERSONAS)
def test_part_unit_cost(forge, persona):
    assert_masking(forge, persona, "V_PART.unit_cost", "UNIT_COST")


@with_replay
@pytest.mark.parametrize("persona", PERSONAS)
def test_sourcing_contract_price(forge, persona):
    assert_masking(forge, persona, "V_SOURCING.contract_price", "CONTRACT_PRICE")


@with_replay
@pytest.mark.parametrize("persona", PERSONAS)
def test_supplier_payment_terms(forge, persona):
    assert_masking(forge, persona, "V_SUPPLIER.payment_terms", "PAYMENT_TERMS")


@with_replay
@pytest.mark.parametrize("persona", PERSONAS)
def test_customer_name(forge, persona):
    assert_masking(forge, persona, "V_CUSTOMER.customer_name", "CUSTOMER_NAME")


@with_replay
@pytest.mark.parametrize("persona", PERSONAS)
def test_customer_email(forge, persona):
    assert_masking(forge, persona, "V_CUSTOMER.email", "CUSTOMER_EMAIL")


@with_replay
@pytest.mark.parametrize("persona", PERSONAS)
def test_customer_credit_limit(forge, persona):
    assert_masking(forge, persona, "V_CUSTOMER.credit_limit", "CREDIT_LIMIT")


@with_replay
@pytest.mark.parametrize("persona", PERSONAS)
def test_sample_has_contract_shape(forge, persona):
    """§5.4 columns, in order, labelled with the persona."""
    df = forge.get_masking_divergence(persona)
    assert list(df.columns) == config.SAMPLE_COLUMNS
    assert (df["PERSONA"] == persona.upper()).all()


def test_every_matrix_row_is_tested():
    tested = {"V_PART.unit_cost", "V_SOURCING.contract_price", "V_SUPPLIER.payment_terms",
              "V_CUSTOMER.customer_name", "V_CUSTOMER.email", "V_CUSTOMER.credit_limit"}
    assert tested == set(config.MASKING_MATRIX)
