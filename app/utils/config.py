"""Contract constants for the Supply Chain Forge app.

Everything here is copied from docs/CONTRACT.md (v1.5). If Snowflake turns out to differ
from these values, file a Change Request in CONTRACT.md §11. Do not edit them to match
reality.
"""

# Flip to False once .agents/HANDOFF.md shows the handoff rows DONE (contract §10).
USE_MOCK_DATA = True

# ── §1 Fully qualified names ─────────────────────────────────────────────────
DATABASE = "SUPPLY_CHAIN_FORGE"
SEMANTIC_VIEW = "SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV"
AGENT = "SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT"
# The agent's data-health tool (CR-006): freshness, the as-of date and data-quality status.
DATA_HEALTH_PROC = "SUPPLY_CHAIN_FORGE.SEMANTIC.SP_DATA_HEALTH"
STREAMLIT_APP = "SUPPLY_CHAIN_FORGE.APP.FORGE_DEMO"
WAREHOUSE = "FORGE_WH"

PERSONA_SAMPLE_PROCS = {
    "Planner":   "SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_PLANNER",
    "Buyer":     "SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_BUYER",
    "Logistics": "SUPPLY_CHAIN_FORGE.GOVERNED.SP_SAMPLE_AS_LOGISTICS",
}

# Contract §1 / §5.4 (v1.2, CR-002 accepted). Each returns one row:
# PERSONA, ON_TIME_DELIVERY_RATE, FILL_RATE, DAYS_OF_INVENTORY, AVG_LANDED_COST.
PERSONA_METRIC_PROCS = {
    "Planner":   "SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_PLANNER",
    "Buyer":     "SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_BUYER",
    "Logistics": "SUPPLY_CHAIN_FORGE.GOVERNED.SP_METRICS_AS_LOGISTICS",
}

# Contract §5.4 (v1.3, CR-004): result columns of the sample procedures, in order.
SAMPLE_COLUMNS = ["PERSONA", "SAMPLE_PART_ID", "UNIT_COST", "SAMPLE_SUPPLIER_ID",
                  "PAYMENT_TERMS", "SAMPLE_CUSTOMER_ID", "CUSTOMER_NAME", "CREDIT_LIMIT",
                  "CONTRACT_PRICE", "CUSTOMER_EMAIL"]

# ── §2 Persona roles ─────────────────────────────────────────────────────────
PERSONA_ROLES = {
    "Planner":   "PLANNER_ROLE",
    "Buyer":     "BUYER_ROLE",
    "Logistics": "LOGISTICS_ROLE",
}

PERSONA_LABELS = {
    "Planner":   "Production Planner",
    "Buyer":     "Procurement Lead",
    "Logistics": "Logistics Coordinator",
}

PERSONA_DESCRIPTIONS = {
    "Planner":   "Plans production and inventory",
    "Buyer":     "Manages suppliers and cost",
    "Logistics": "Manages shipments and delivery",
}

# ── §3 Canonical metrics ─────────────────────────────────────────────────────
METRICS = {
    "on_time_delivery_rate": {
        "id": "shipments.on_time_delivery_rate",
        "label": "On-Time Delivery",
        "format": "percent",
        "definition": "Share of delivered shipments arriving on or before the TMS "
                      "promised delivery date. Excludes in-transit shipments and "
                      "shipments with no promised date. Without a stated period, "
                      "covers shipments shipped in the last 12 months.",
    },
    "fill_rate": {
        "id": "order_lines.fill_rate",
        "label": "Fill Rate",
        "format": "percent",
        "definition": "Quantity shipped divided by quantity ordered across order "
                      "lines on shipped or delivered orders. Open and cancelled "
                      "orders are excluded. Partial shipments are pro-rated; "
                      "over-shipments count as fully shipped. Without a stated "
                      "period, covers orders placed in the last 12 months.",
    },
    "days_of_inventory": {
        "id": "inventory.days_of_inventory",
        "label": "Days of Inventory",
        "format": "number",
        "definition": "Average on-hand quantity divided by average daily usage. "
                      "Uses gross on-hand, not net of reservations; negative "
                      "on-hand counts as zero. Without a stated period, uses the "
                      "latest inventory snapshot.",
    },
    "avg_landed_cost": {
        "id": "shipments.avg_landed_cost",
        "label": "Avg Landed Cost",
        "format": "currency",
        "definition": "Average total cost to move a shipment to destination, in "
                      "USD: freight plus duties plus handling. Missing duty or "
                      "handling counts as zero; shipments with unknown or "
                      "implausible cost are excluded. Without a stated period, "
                      "covers shipments shipped in the last 12 months.",
    },
}

METRIC_RANGES = {
    "on_time_delivery_rate": (0.84, 0.90),
    "fill_rate": (0.90, 0.95),
    "days_of_inventory": (15, 45),
    "avg_landed_cost": (150, 900),
}

# ── §3a Time rule (CR-006) ───────────────────────────────────────────────────
# Without a stated period: trailing 12 months on the metric's window date, anchored on
# CURRENT_DATE(); days of inventory uses the latest snapshot instead.
WINDOW_MONTHS = 12
WINDOW_DATE = {
    "on_time_delivery_rate": "shipments.ship_date",
    "fill_rate": "orders.order_date",
    "avg_landed_cost": "shipments.ship_date",
}
LATEST_SNAPSHOT = ("inventory.snapshot_date = "
                   "(SELECT MAX(snapshot_date) FROM SUPPLY_CHAIN_FORGE.GOVERNED.V_INVENTORY)")
WINDOW_LABEL = {  # app wording for the window each number covers
    "on_time_delivery_rate": "last 12 months",
    "fill_rate": "last 12 months",
    "days_of_inventory": "latest snapshot",
    "avg_landed_cost": "last 12 months",
}

# ── §4 Dimensions ────────────────────────────────────────────────────────────
DIMENSIONS = {
    "suppliers": ["suppliers.supplier_name", "suppliers.supplier_region", "suppliers.supplier_tier"],
    "parts": ["parts.part_name", "parts.category", "parts.subcategory", "parts.is_critical"],
    "plants": ["plants.plant_name", "plants.plant_region", "plants.plant_country", "plants.plant_type"],
    "customers": ["customers.customer_segment", "customers.customer_region"],
    "orders": ["orders.order_date", "orders.order_month", "orders.order_quarter",
               "orders.order_year", "orders.order_year_quarter", "orders.order_status",
               "orders.order_priority"],
    "shipments": ["shipments.ship_date", "shipments.carrier", "shipments.shipment_status"],
    "inventory": ["inventory.snapshot_date"],
}

_REGIONS = ["APAC", "EMEA", "AMER"]
DIMENSION_VALUES = {
    "suppliers.supplier_region": _REGIONS,
    "plants.plant_region": _REGIONS,
    "customers.customer_region": _REGIONS,
    "plants.plant_type": ["MFG", "DC", "HUB"],
    "suppliers.supplier_tier": ["1", "2", "3"],
    "customers.customer_segment": ["ENTERPRISE", "MIDMARKET", "SMB"],
    "orders.order_status": ["OPEN", "SHIPPED", "DELIVERED", "CANCELLED"],
    "orders.order_priority": ["HIGH", "NORMAL", "LOW"],
    "shipments.shipment_status": ["IN_TRANSIT", "DELIVERED", "DELAYED"],
    "orders.order_quarter": ["Q1", "Q2", "Q3", "Q4"],
    "parts.category": ["ELECTRONICS", "MECHANICAL", "RAW_MATERIAL", "PACKAGING", "CHEMICAL", "FASTENERS"],
}

# Valid metric × dimension pairings, with the contract's `entity.*` expanded.
# days_of_inventory is deliberately not valid with orders.* or shipments.*.
VALID_PAIRINGS = {
    "on_time_delivery_rate": DIMENSIONS["plants"] + DIMENSIONS["orders"]
                             + DIMENSIONS["shipments"] + DIMENSIONS["customers"],
    "fill_rate": DIMENSIONS["parts"] + DIMENSIONS["plants"]
                 + DIMENSIONS["orders"] + DIMENSIONS["customers"],
    "days_of_inventory": DIMENSIONS["plants"] + DIMENSIONS["parts"] + ["inventory.snapshot_date"],
    "avg_landed_cost": DIMENSIONS["plants"] + DIMENSIONS["orders"]
                       + DIMENSIONS["shipments"] + DIMENSIONS["customers"],
}

# ── §6 Masking matrix (drives the expected-divergence table) ────────────────
# Value per persona: "visible" or the masked value that persona sees.
MASKING_MATRIX = {
    "V_PART.unit_cost":           {"Planner": None, "Buyer": "visible", "Logistics": None},
    "V_SOURCING.contract_price":  {"Planner": None, "Buyer": "visible", "Logistics": None},
    "V_SUPPLIER.payment_terms":   {"Planner": "*** RESTRICTED ***", "Buyer": "visible",
                                   "Logistics": "*** RESTRICTED ***"},
    "V_CUSTOMER.customer_name":   {"Planner": "visible", "Buyer": "*** MASKED ***", "Logistics": "visible"},
    "V_CUSTOMER.email":           {"Planner": "visible", "Buyer": "*** MASKED ***", "Logistics": "visible"},
    "V_CUSTOMER.credit_limit":    {"Planner": None, "Buyer": None, "Logistics": None},
}

# ── §7 Governed view columns, in order ───────────────────────────────────────
GOVERNED_COLUMNS = {
    "V_SUPPLIER": ["supplier_id", "supplier_name", "country", "region", "supplier_tier",
                   "lead_time_days", "reliability_score", "payment_terms", "email"],
    "V_PART": ["part_id", "part_name", "category", "subcategory", "unit_cost", "weight_kg", "is_critical"],
    "V_SOURCING": ["source_id", "supplier_id", "part_id", "is_primary", "contract_price"],
    "V_PLANT": ["plant_id", "plant_name", "country", "region", "plant_type", "capacity_units"],
    "V_INVENTORY": ["inventory_key", "plant_id", "part_id", "quantity_on_hand", "quantity_reserved",
                    "reorder_point", "daily_usage", "snapshot_date"],
    "V_CUSTOMER": ["customer_id", "customer_name", "email", "country", "region", "customer_segment",
                   "credit_limit"],
    "V_ORDER": ["order_id", "customer_id", "order_date", "order_status", "order_priority"],
    "V_ORDER_LINE": ["line_id", "order_id", "part_id", "plant_id", "quantity_ordered",
                     "quantity_shipped", "unit_price"],
    "V_SHIPMENT": ["shipment_id", "order_id", "plant_id", "carrier", "ship_date",
                   "promised_delivery_date", "actual_delivery_date", "freight_cost", "duty_cost",
                   "handling_cost", "shipment_status"],
}

# ── §9 Canonical questions ───────────────────────────────────────────────────
CANONICAL_QUESTIONS = [
    "What is our overall on-time delivery rate?",
    "What is on-time delivery rate by region?",
    "What was on-time delivery rate by quarter?",
    "What is our fill rate?",
    "What is fill rate by product category?",
    "What are days of inventory by plant?",
    "What is average landed cost by region?",
    "Which plants have the worst on-time delivery?",  # v1.2, CR-003 option B
]

# ── §10 Mock mode ────────────────────────────────────────────────────────────
MOCK_METRICS = {
    "on_time_delivery_rate": 0.8714,
    "fill_rate": 0.9283,
    "days_of_inventory": 28.4,
    "avg_landed_cost": 412.67,
}

MOCK_BY_REGION = {
    "APAC": {"on_time_delivery_rate": 0.8521, "fill_rate": 0.9147,
             "days_of_inventory": 31.2, "avg_landed_cost": 487.20},
    "EMEA": {"on_time_delivery_rate": 0.8893, "fill_rate": 0.9361,
             "days_of_inventory": 26.8, "avg_landed_cost": 398.45},
    "AMER": {"on_time_delivery_rate": 0.8742, "fill_rate": 0.9329,
             "days_of_inventory": 27.1, "avg_landed_cost": 362.10},
}

# ── App-side settings (not from the contract) ────────────────────────────────
CONSISTENCY_DP = 6  # §6 invariant: metrics identical across roles to 6 decimal places

# Format strings per contract §3 format (docs/references/plotly_streamlit.md §4).
FORMATS = {
    "percent":  {"tickformat": ".0%", "text_auto": ".1%", "py": "{:.1%}"},
    "number":   {"tickformat": None,  "text_auto": ".1f", "py": "{:.1f}"},
    "currency": {"tickformat": None,  "text_auto": "$,.2f", "py": "${:,.2f}", "tickprefix": "$"},
}


def column_name(identifier: str) -> str:
    """Output column for a semantic view identifier: unqualified name, uppercased (§5.2)."""
    return identifier.split(".")[-1].upper()


MISSING = "—"  # shown where Snowflake returns NULL: nothing in the group meets the definition


def as_number(value):
    """float, or None for NULL / NaN / empty. Snowflake returns NULL where a metric has
    nothing to measure (e.g. fill rate for OPEN and CANCELLED orders, CR-005)."""
    if value is None:
        return None
    try:
        number = float(value)  # "" and pandas' NA raise here too
    except (TypeError, ValueError):
        return None
    return None if number != number else number  # NaN is the only value unequal to itself


def format_value(metric_key: str, value) -> str:
    number = as_number(value)
    return MISSING if number is None else FORMATS[METRICS[metric_key]["format"]]["py"].format(number)
