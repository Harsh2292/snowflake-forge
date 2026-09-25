# Reference — Plotly charts in Streamlit (only what the app uses)

| | |
|---|---|
| **Sources** | <https://docs.streamlit.io/develop/api-reference/charts/st.plotly_chart> |
| | <https://docs.streamlit.io/develop/quick-reference/release-notes/2025> |
| | <https://plotly.com/python-api-reference/generated/plotly.express.bar.html> |
| | <https://plotly.com/python/bar-charts/> · <https://plotly.com/python/horizontal-bar-charts/> · <https://plotly.com/python/line-charts/> |
| | Supported SiS versions: <https://docs.snowflake.com/en/developer-guide/streamlit/app-development/dependency-management> |
| **Fetched** | 2026-09-24 |
| **Used by** | Tab 4 · Metrics (C03) |

---

## 1. Version pin — decided by SiS

The SiS **warehouse runtime** supports Streamlit **1.42.0 – 1.52.2** (limited list; newest
is `1.52.2`). Streamlit release notes:

| Version | `st.plotly_chart` change |
|---------|--------------------------|
| 1.50.0 | `**kwargs` deprecated → use `config=` |
| **1.51.0** | **`width` parameter added** (`"stretch"` / `"content"` / int) |
| 1.52.0 | `height` parameter added |

**Decision**: pin **`streamlit=1.52.2`** in `environment.yml` (SiS) and
`streamlit==1.52.2` in `requirements.txt` (local). Local and SiS then behave the same, and
we can use the current API.

Plotly: `text_auto` needs Plotly **≥ 5.5**. `plotly=5.*` in the Snowflake Conda channel
covers it.

---

## 2. `st.plotly_chart` (1.52 signature)

```python
st.plotly_chart(figure_or_data, use_container_width=None, *, width="stretch",
                height="content", theme="streamlit", key=None,
                on_select="ignore", selection_mode=("points","box","lasso"), config=None)
```

- Use **`width="stretch"`** (the default). `use_container_width` is **deprecated**; don't use it.
- `theme="streamlit"` (default) applies Streamlit's palette. `theme=None` uses Plotly's own.
- `key=` gives a stable identity. **Needed when the same chart function renders more than
  once** (e.g. inside tabs), or Streamlit raises a duplicate-element error.
- `on_select="ignore"` (default) = static chart. We don't need selections.
- Pass Plotly options via `config={...}`, not `**kwargs` (deprecated since 1.50).
- More than 1000 points switches to WebGL. Not an issue at our sizes (3 regions, ~6
  categories, ≤ 20 plants).

---

## 3. The three patterns we need

All figures take a pandas DataFrame from `forge_data.get_metric()`. Column names are the
**uppercased unqualified** names from `SEMANTIC_VIEW()` (see `semantic_view_query.md`).

### 3a. Bar by category — OTD by region, landed cost by region

```python
import plotly.express as px

fig = px.bar(
    df, x="PLANT_REGION", y="ON_TIME_DELIVERY_RATE",
    text_auto=".1%",                                   # label bars: 87.1%
    category_orders={"PLANT_REGION": ["AMER", "APAC", "EMEA"]},
    labels={"PLANT_REGION": "Region", "ON_TIME_DELIVERY_RATE": "On-Time Delivery"},
)
fig.update_yaxes(tickformat=".0%", range=[0, 1])
st.plotly_chart(fig, key="otd_by_region")
```

Currency variant: `text_auto="$,.2f"`, `fig.update_yaxes(tickprefix="$")`.

### 3b. Grouped bar — metric by two dimensions (e.g. OTD by region × quarter)

```python
fig = px.bar(df, x="ORDER_QUARTER", y="ON_TIME_DELIVERY_RATE",
             color="PLANT_REGION", barmode="group",
             category_orders={"ORDER_QUARTER": ["Q1", "Q2", "Q3", "Q4"]})
```

`barmode`: `'relative'` (default, stacked), `'group'` (side by side), `'overlay'`.
Rates must use **`group`**. Stacking percentages is meaningless.

### 3c. Horizontal bar — ranked lists (DOI by plant, worst suppliers by OTD)

```python
fig = px.bar(df.sort_values("DAYS_OF_INVENTORY"),
             x="DAYS_OF_INVENTORY", y="PLANT_NAME", orientation="h",
             text_auto=".1f")
fig.update_layout(height=max(300, 28 * len(df)))   # keep bars readable
```

`orientation='h'` → x is the value, y is the category. Sort the DataFrame first. Plotly
draws the first row at the bottom.

### 3d. Line over time — trend by month

```python
fig = px.line(df.sort_values("ORDER_MONTH"), x="ORDER_MONTH", y="FILL_RATE",
              markers=True)
fig.update_yaxes(tickformat=".0%")
```

`ORDER_MONTH` is a `'YYYY-MM'` string (GAPS_RESOLVED GAP-2), so it sorts correctly as
text. Add `color="PLANT_REGION"` for one line per region.

---

## 4. Formatting map (contract §3 formats → d3 format strings)

| Contract format | Axis `tickformat` | Bar `text_auto` | Python f-string (tables/metrics) |
|-----------------|-------------------|-----------------|----------------------------------|
| percent, 1 dp | `".0%"` | `".1%"` | `f"{v:.1%}"` |
| number, 1 dp | — | `".1f"` | `f"{v:.1f}"` |
| currency USD, 2 dp | `tickprefix="$"` | `"$,.2f"` | `f"${v:,.2f}"` |

Keep this map in `config.py` next to `METRICS` so charts, `st.metric` tiles and tables
format identically.

---

## 5. Gotchas

- `NUMBER` columns from Snowpark can be `Decimal` / object dtype. Run `pd.to_numeric`
  before plotting, or Plotly treats them as categories.
- Always set `category_orders` for region/quarter so charts don't reorder between mock
  and live data.
- Pass a unique `key=` to every `st.plotly_chart` call inside tabs.
