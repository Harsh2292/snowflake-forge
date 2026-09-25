"""The four source systems' column names and their governed equivalents (LLD §2, §4).

This is static on purpose. CLAUDE.md forbids querying the source schemas outside the
contract §8 divergence demo, so Tab 3 shows the mapping from the design docs, not from
the source tables.
"""

import pandas as pd

# (system, schema, table, source_column, governed_view, governed_column, meaning, flag)
_ROWS = [
    ("SRM", "SRM_SOURCE", "LFA1", "LIFNR", "V_SUPPLIER", "supplier_id", "Supplier ID", ""),
    ("SRM", "SRM_SOURCE", "LFA1", "NAME1", "V_SUPPLIER", "supplier_name", "Supplier name", ""),
    ("SRM", "SRM_SOURCE", "LFA1", "LAND1", "V_SUPPLIER", "country", "Country code", ""),
    ("SRM", "SRM_SOURCE", "LFA1", "REGIO", "V_SUPPLIER", "region", "Region", ""),
    ("SRM", "SRM_SOURCE", "LFA1", "SUPP_TIER", "V_SUPPLIER", "supplier_tier", "Supplier tier 1-3", ""),
    ("SRM", "SRM_SOURCE", "LFA1", "LEAD_TM_DAYS", "V_SUPPLIER", "lead_time_days", "Lead time in days", ""),
    ("SRM", "SRM_SOURCE", "LFA1", "RELIAB_SCR", "V_SUPPLIER", "reliability_score", "Reliability 0-1", ""),
    ("SRM", "SRM_SOURCE", "LFA1", "ZTERM", "V_SUPPLIER", "payment_terms", "Payment terms", "SENSITIVE"),
    ("SRM", "SRM_SOURCE", "LFA1", "EMAIL", "V_SUPPLIER", "email", "Supplier contact", "PII"),
    ("SRM", "SRM_SOURCE", "MARA", "MATNR", "V_PART", "part_id", "Part ID", ""),
    ("SRM", "SRM_SOURCE", "MARA", "MAKTX", "V_PART", "part_name", "Part description", ""),
    ("SRM", "SRM_SOURCE", "MARA", "MATKL", "V_PART", "category", "Category", ""),
    ("SRM", "SRM_SOURCE", "MARA", "SUBCAT", "V_PART", "subcategory", "Subcategory", ""),
    ("SRM", "SRM_SOURCE", "MARA", "STPRS", "V_PART", "unit_cost", "Standard unit cost", "SENSITIVE"),
    ("SRM", "SRM_SOURCE", "MARA", "BRGEW", "V_PART", "weight_kg", "Gross weight kg", ""),
    ("SRM", "SRM_SOURCE", "MARA", "CRIT_FLG", "V_PART", "is_critical", "Critical part flag", ""),
    ("SRM", "SRM_SOURCE", "SOURCING", "SOURCE_ID", "V_SOURCING", "source_id", "Sourcing link ID", ""),
    ("SRM", "SRM_SOURCE", "SOURCING", "LIFNR", "V_SOURCING", "supplier_id", "Supplier ID", ""),
    ("SRM", "SRM_SOURCE", "SOURCING", "MATNR", "V_SOURCING", "part_id", "Part ID", ""),
    ("SRM", "SRM_SOURCE", "SOURCING", "IS_PRIMARY", "V_SOURCING", "is_primary", "Primary source flag", ""),
    ("SRM", "SRM_SOURCE", "SOURCING", "CONTRACT_PRICE", "V_SOURCING", "contract_price", "Contract price", "SENSITIVE"),
    ("WMS", "WMS_SOURCE", "T001W", "WERKS", "V_PLANT", "plant_id", "Plant ID", ""),
    ("WMS", "WMS_SOURCE", "T001W", "NAME1", "V_PLANT", "plant_name", "Plant name", ""),
    ("WMS", "WMS_SOURCE", "T001W", "LAND1", "V_PLANT", "country", "Country code", ""),
    ("WMS", "WMS_SOURCE", "T001W", "REGION_CD", "V_PLANT", "region", "Region", ""),
    ("WMS", "WMS_SOURCE", "T001W", "PLANT_TYPE", "V_PLANT", "plant_type", "MFG / DC / HUB", ""),
    ("WMS", "WMS_SOURCE", "T001W", "CAPACITY_UNITS", "V_PLANT", "capacity_units", "Capacity", ""),
    ("WMS", "WMS_SOURCE", "MARD", "INV_KEY", "V_INVENTORY", "inventory_key", "Plant-part-date key", ""),
    ("WMS", "WMS_SOURCE", "MARD", "WERKS", "V_INVENTORY", "plant_id", "Plant ID", ""),
    ("WMS", "WMS_SOURCE", "MARD", "MATNR", "V_INVENTORY", "part_id", "Part ID", ""),
    ("WMS", "WMS_SOURCE", "MARD", "LABST", "V_INVENTORY", "quantity_on_hand", "Quantity on hand", ""),
    ("WMS", "WMS_SOURCE", "MARD", "INSME", "V_INVENTORY", "quantity_reserved", "Quantity reserved", ""),
    ("WMS", "WMS_SOURCE", "MARD", "REORD_PT", "V_INVENTORY", "reorder_point", "Reorder point", ""),
    ("WMS", "WMS_SOURCE", "MARD", "DAILY_USG", "V_INVENTORY", "daily_usage", "Daily usage", ""),
    ("WMS", "WMS_SOURCE", "MARD", "SNAP_DT", "V_INVENTORY", "snapshot_date", "Snapshot date", ""),
    ("ERP", "ERP_SOURCE", "KNA1", "KUNNR", "V_CUSTOMER", "customer_id", "Customer ID", ""),
    ("ERP", "ERP_SOURCE", "KNA1", "NAME1", "V_CUSTOMER", "customer_name", "Company name", "PII"),
    ("ERP", "ERP_SOURCE", "KNA1", "EMAIL", "V_CUSTOMER", "email", "Customer contact", "PII"),
    ("ERP", "ERP_SOURCE", "KNA1", "LAND1", "V_CUSTOMER", "country", "Country code", ""),
    ("ERP", "ERP_SOURCE", "KNA1", "REGIO", "V_CUSTOMER", "region", "Region", ""),
    ("ERP", "ERP_SOURCE", "KNA1", "KTOKD", "V_CUSTOMER", "customer_segment", "Segment", ""),
    ("ERP", "ERP_SOURCE", "KNA1", "KLIMK", "V_CUSTOMER", "credit_limit", "Credit limit", "SENSITIVE"),
    ("ERP", "ERP_SOURCE", "VBAK", "VBELN", "V_ORDER", "order_id", "Order ID", ""),
    ("ERP", "ERP_SOURCE", "VBAK", "KUNNR", "V_ORDER", "customer_id", "Customer ID", ""),
    ("ERP", "ERP_SOURCE", "VBAK", "AUDAT", "V_ORDER", "order_date", "Order date", ""),
    ("ERP", "ERP_SOURCE", "VBAK", "ERDAT", "", "", "ERP's promised date: NOT exposed, TMS is authoritative", "CONFLICT"),
    ("ERP", "ERP_SOURCE", "VBAK", "GBSTK", "V_ORDER", "order_status", "Order status", ""),
    ("ERP", "ERP_SOURCE", "VBAK", "PRIO", "V_ORDER", "order_priority", "Priority", ""),
    ("ERP", "ERP_SOURCE", "VBAP", "LINE_ID", "V_ORDER_LINE", "line_id", "Order line ID", ""),
    ("ERP", "ERP_SOURCE", "VBAP", "VBELN", "V_ORDER_LINE", "order_id", "Order ID", ""),
    ("ERP", "ERP_SOURCE", "VBAP", "MATNR", "V_ORDER_LINE", "part_id", "Part ID", ""),
    ("ERP", "ERP_SOURCE", "VBAP", "WERKS", "V_ORDER_LINE", "plant_id", "Fulfilling plant", ""),
    ("ERP", "ERP_SOURCE", "VBAP", "KWMENG", "V_ORDER_LINE", "quantity_ordered", "Quantity ordered", ""),
    ("ERP", "ERP_SOURCE", "VBAP", "QTY_SHIPPED", "V_ORDER_LINE", "quantity_shipped", "Quantity shipped", ""),
    ("ERP", "ERP_SOURCE", "VBAP", "NETPR", "V_ORDER_LINE", "unit_price", "Unit price", ""),
    ("TMS", "TMS_SOURCE", "VTTK", "TKNUM", "V_SHIPMENT", "shipment_id", "Shipment ID", ""),
    ("TMS", "TMS_SOURCE", "VTTK", "VBELN", "V_SHIPMENT", "order_id", "Order ID", ""),
    ("TMS", "TMS_SOURCE", "VTTK", "WERKS", "V_SHIPMENT", "plant_id", "Origin plant", ""),
    ("TMS", "TMS_SOURCE", "VTTK", "CARRIER_CD", "V_SHIPMENT", "carrier", "Carrier", ""),
    ("TMS", "TMS_SOURCE", "VTTK", "DPTBG", "V_SHIPMENT", "ship_date", "Ship date", ""),
    ("TMS", "TMS_SOURCE", "VTTK", "PROM_DLV_DT", "V_SHIPMENT", "promised_delivery_date",
     "TMS promised date: authoritative", "CONFLICT"),
    ("TMS", "TMS_SOURCE", "VTTK", "ACT_DLV_DT", "V_SHIPMENT", "actual_delivery_date", "Actual delivery date", ""),
    ("TMS", "TMS_SOURCE", "VTTK", "FREIGHT_AMT", "V_SHIPMENT", "freight_cost", "Freight cost", ""),
    ("TMS", "TMS_SOURCE", "VTTK", "DUTY_AMT", "V_SHIPMENT", "duty_cost", "Duty cost", ""),
    ("TMS", "TMS_SOURCE", "VTTK", "HANDLING_AMT", "V_SHIPMENT", "handling_cost", "Handling cost", ""),
    ("TMS", "TMS_SOURCE", "VTTK", "SHP_STATUS", "V_SHIPMENT", "shipment_status", "Shipment status", ""),
]

COLUMNS = ["SYSTEM", "SOURCE_SCHEMA", "SOURCE_TABLE", "SOURCE_COLUMN",
           "GOVERNED_VIEW", "GOVERNED_COLUMN", "MEANING", "FLAG"]


def catalog() -> pd.DataFrame:
    return pd.DataFrame(_ROWS, columns=COLUMNS)
