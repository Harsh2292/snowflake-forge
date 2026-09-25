"""Contract constants for the Supply Chain Forge app.

Everything here is copied from docs/CONTRACT.md (v1.3). If Snowflake turns out to differ
from these values, file a Change Request in CONTRACT.md §11. Do not edit them to match
reality.
"""

# Flip to False once .agents/HANDOFF.md shows the handoff rows DONE (contract §10).
USE_MOCK_DATA = True

# ── §1 Fully qualified names ─────────────────────────────────────────────────
DATABASE = "SUPPLY_CHAIN_FORGE"
SEMANTIC_VIEW = "SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_SV"
AGENT = "SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_AGENT"
MCP_SERVER = "SUPPLY_CHAIN_FORGE.SEMANTIC.SUPPLY_CHAIN_MCP"
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
                      "promised delivery date. Excludes in-transit shipments.",
    },
    "fill_rate": {
        "id": "order_lines.fill_rate",
        "label": "Fill Rate",
        "format": "percent",
        "definition": "Quantity shipped divided by quantity ordered across order "
                      "lines. Partial shipments are pro-rated.",
    },
    "days_of_inventory": {
        "id": "inventory.days_of_inventory",
        "label": "Days of Inventory",
        "format": "number",
        "definition": "Average on-hand quantity divided by average daily usage. "
                      "Uses gross on-hand, not net of reservations.",
    },
    "avg_landed_cost": {
        "id": "shipments.avg_landed_cost",
        "label": "Avg Landed Cost",
        "format": "currency",
        "definition": "Average total cost to move a shipment to destination: "
                      "freight plus duties plus handling.",
    },
}

METRIC_RANGES = {
    "on_time_delivery_rate": (0.84, 0.90),
    "fill_rate": (0.90, 0.95),
    "days_of_inventory": (15, 45),
    "avg_landed_cost": (150, 900),
}

# ── §4 Dimensions ────────────────────────────────────────────────────────────
DIMENSIONS = {
    "suppliers": ["suppliers.supplier_name", "suppliers.supplier_region", "suppliers.supplier_tier"],
    "parts": ["parts.part_name", "parts.category", "parts.subcategory", "parts.is_critical"],
    "plants": ["plants.plant_name", "plants.plant_region", "plants.plant_country", "plants.plant_type"],
    "customers": ["customers.customer_segment", "customers.customer_region"],
    "orders": ["orders.order_date", "orders.order_month", "orders.order_quarter",
               "orders.order_year", "orders.order_status", "orders.order_priority"],
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


def format_value(metric_key: str, value) -> str:
    return FORMATS[METRICS[metric_key]["format"]]["py"].format(value)
