# Roadmap — after the hackathon

> **Status: parked.** Nothing here is built during the hackathon. Each item is built only
> if customer conversations show that people need it (the gate in each section).
>
> Recorded 2026-09-29 at the user's request. Source: the scale and productization
> discussion during B08.

The hackathon delivers the **core system**: one governed semantic layer over messy
multi-system supply chain data, a Cortex Agent on top, and proof that every persona gets
the same number. This roadmap is what turns it into something a logistics or
manufacturing business would buy and install.

**Positioning to validate first:** an *accelerator plus implementation service*. "A
governed supply chain analytics layer on your own Snowflake account in weeks, not
months." Snowflake already sells semantic views and agents; the value on top is the
prebuilt supply chain model, its metric library, its cleansing rules and its source
mappings.

---

## Gate 0 — validate demand before building anything

- [ ] Show the deployed demo to 5–10 target businesses (logistics, 3PL, distribution,
      manufacturing)
- [ ] For each, record:
  - which source systems they run
  - which metrics they argue about today
  - who would own it
  - whether they already use Snowflake
  - what they would pay for
- [ ] Find at least one pilot candidate who will share real (anonymised) data
- **Continue only if** at least two businesses name the same pain and one agrees to a pilot

---

## 1. Connect to real source systems

The hackathon uses synthetic SAP-style tables. Real customers run many different systems,
and mapping their data is most of the real work.

- [ ] Source adapters: a mapping per system (SAP S/4HANA, Oracle, Microsoft Dynamics;
      Manhattan and Blue Yonder WMS; Oracle and SAP TM; carrier and visibility feeds) onto
      the fixed `CONFORMED` model
- [ ] Continuous ingestion (connectors or streaming) instead of batch loads
- [ ] Schema-drift handling: new, renamed or retyped columns in the source
- **Gate:** which systems the pilot customers actually run

## 2. Configurable metric definitions

Every business defines "on-time" a little differently (OTIF, per line vs per shipment,
±1-day tolerance, customer-requested vs promised date).

- [ ] Metric definitions as configuration per customer, with the canonical definition as
      the default
- [ ] A versioned metric catalogue: who changed a definition, when, and why
- [ ] A "governed growth" workflow: the agent proposes a new metric, a human approves it,
      and it's added for everyone
- **Gate:** the pilot needs a definition we don't ship

## 3. Enterprise identity and access

- [ ] Each user queries as themselves (SSO, their own role), instead of the demo's
      owner's-rights app plus persona procedures
- [ ] Row-level access (for example region or business unit), designed so aggregates stay
      identical where the business requires it
- [ ] An audit trail: who asked what, which SQL ran, which data was touched
- **Gate:** the customer's security review

## 4. Packaging and distribution

- [ ] Package as a **Snowflake Native App** so it installs inside the customer's account
      and their data never leaves it (Marketplace distribution)
- [ ] An upgrade path that keeps each customer's configuration and mappings
- [ ] Multi-tenant design for a hosted option, if customers ask for one
- **Gate:** the customer's procurement and data-residency requirements

## 5. Performance and cost at production scale

The core system is designed for scale at the hackathon (B13 proves it on a clone). In
production, the knobs are turned per customer:

- [ ] Warehouse sizing and multi-cluster for concurrency; separate warehouses for
      ingestion, dashboards and the agent
- [ ] Pre-aggregation (dynamic tables, or semantic view materializations) for the
      heaviest metrics
- [ ] **Parallel multi-part router plus KPI shortcut**: split multi-part questions, run
      the parts at the same time, answer known KPIs without the LLM, and merge the answers
      in order (a Day-3 stretch item at the hackathon; productionize it here)
- [ ] Cost dashboards per customer: warehouse credits vs AI tokens, by path
- **Gate:** the pilot's real volume and question patterns

## 6. Operations

- [ ] Monitoring and alerting: data freshness, data-quality failures, agent error rate
      and latency
- [ ] A standing evaluation set per customer, re-run after every change (the agent's
      accuracy is measured, not assumed)
- [ ] Support model, SLAs, incident runbooks
- **Gate:** first paying customer

## 7. Product surface

- [ ] Embeddable answers (API, Teams or Slack, BI tools), beyond the Streamlit app
- [ ] Extra entities if customers need them: carriers as a master entity, lanes,
      warehouses and bins, purchase orders, forecasts
- [ ] Master-data history (slowly changing dimensions), so a supplier that moved region
      is reported correctly over time
- **Gate:** repeated asks from at least two customers
