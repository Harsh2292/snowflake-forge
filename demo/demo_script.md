# Demo Script — Supply Chain Forge

> Step-by-step hackathon presentation guide.
> Owner: Claude Code (with input from CoCo on Snowflake portions)

## Demo Flow

### 1. The Problem (30 seconds)
- Supply chain data is scattered across ERP, logistics, supplier, and IoT systems
- Same question yields different answers across teams
- Show: raw table with cryptic column names (ORD_DLV_DT, INV_QTY_OH)

### 2. The Ontology (60 seconds)
- Show the entity relationship model
- Highlight the canonical metrics and their single authoritative definitions
- Show the semantic view YAML: business meaning, not column names

### 3. Governance Layer (45 seconds)
- Show the three persona roles
- Demo: planner can't see supplier costs, buyer can't see customer PII
- But the metrics still compute correctly for everyone

### 4. Conversational Analytics (90 seconds)
- Open Streamlit app
- Select "Planner" persona
- Ask: "What is our on-time delivery rate for Q3?"
- Show the answer with metric lineage (which formula was used)
- Switch to "Buyer" persona
- Ask the same question
- Show: identical answer

### 5. Consistency Proof (45 seconds)
- Click "Consistency Proof" tab
- Run all 4 canonical metrics across all 3 personas
- Show: all green checkmarks, all numbers match

### 6. Technical Architecture (30 seconds)
- Quick diagram: Raw → Governed → Semantic → Agent → App
- Highlight: everything is in Snowflake, no external dependencies

## Time: ~5 minutes total
