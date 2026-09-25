-- ============================================================
-- 02_masking_policies.sql — Dynamic Column Masking Policies
-- Task: B06
-- Owner: CoCo
-- Schema: SUPPLY_CHAIN_FORGE.GOVERNED
-- ============================================================

USE DATABASE SUPPLY_CHAIN_FORGE;
USE SCHEMA GOVERNED;

-- 1. MASK_SUPPLIER_COST: Protects unit_cost and contract_price
-- Visible to: FORGE_ADMIN, BUYER_ROLE, ACCOUNTADMIN
-- Masked as: NULL for PLANNER_ROLE, LOGISTICS_ROLE
CREATE OR REPLACE MASKING POLICY MASK_SUPPLIER_COST AS (val NUMBER(12,2)) 
RETURNS NUMBER(12,2) ->
    CASE 
        WHEN CURRENT_ROLE() IN ('FORGE_ADMIN', 'BUYER_ROLE', 'ACCOUNTADMIN') THEN val
        ELSE NULL
    END
COMMENT = 'Masks supplier unit cost and contract price from non-buyer personas';

-- 2. MASK_PAYMENT_TERMS: Protects commercial payment terms
-- Visible to: FORGE_ADMIN, BUYER_ROLE, ACCOUNTADMIN
-- Masked as: '*** RESTRICTED ***' for PLANNER_ROLE, LOGISTICS_ROLE
CREATE OR REPLACE MASKING POLICY MASK_PAYMENT_TERMS AS (val VARCHAR) 
RETURNS VARCHAR ->
    CASE 
        WHEN CURRENT_ROLE() IN ('FORGE_ADMIN', 'BUYER_ROLE', 'ACCOUNTADMIN') THEN val
        ELSE '*** RESTRICTED ***'
    END
COMMENT = 'Masks commercial payment terms from non-buyer personas';

-- 3. MASK_CUSTOMER_PII: Protects customer company name and email
-- Visible to: FORGE_ADMIN, PLANNER_ROLE, LOGISTICS_ROLE, ACCOUNTADMIN
-- Masked as: '*** MASKED ***' for BUYER_ROLE (Procurement should not see customer PII)
CREATE OR REPLACE MASKING POLICY MASK_CUSTOMER_PII AS (val VARCHAR) 
RETURNS VARCHAR ->
    CASE 
        WHEN CURRENT_ROLE() IN ('FORGE_ADMIN', 'PLANNER_ROLE', 'LOGISTICS_ROLE', 'ACCOUNTADMIN') THEN val
        ELSE '*** MASKED ***'
    END
COMMENT = 'Masks customer PII from procurement buyer persona';

-- 4. MASK_CREDIT_LIMIT: Protects customer financial credit limit
-- Visible to: FORGE_ADMIN, ACCOUNTADMIN (only administrator sees credit limits)
-- Masked as: NULL for all 3 persona roles
CREATE OR REPLACE MASKING POLICY MASK_CREDIT_LIMIT AS (val NUMBER(15,2)) 
RETURNS NUMBER(15,2) ->
    CASE 
        WHEN CURRENT_ROLE() IN ('FORGE_ADMIN', 'ACCOUNTADMIN') THEN val
        ELSE NULL
    END
COMMENT = 'Restricts customer credit limits to administrator role only';
