-- Capitec Fraud & AML — Synthetic seeder (1/4): customers, accounts, third parties
-- SQL-authored generation. Names/entities are clearly synthetic (no real individuals).
-- Volumes per PRD §10: ~5,000 customers, ~12,000 accounts, ~3,000 third parties.
-- Capitec context: mass-market retail bank. Signature product is the Global One
-- account (transactional + savings pockets); segments and balances reflect a
-- high-volume, lower-average-balance retail base rather than private wealth.

USE CATALOG elexon_app_for_settlement_acc_catalog;

-- ── CUSTOMERS (5,000) ────────────────────────────────────────────────────
-- Deterministic synthetic identities keyed off an integer id.
INSERT OVERWRITE capitec_fraud_aml_bronze.customers
WITH ids AS (SELECT id FROM range(1, 5001))
SELECT
  concat('CUST', lpad(id, 6, '0'))                                   AS customer_id,
  concat(
    element_at(array('Ava','Liam','Noah','Olivia','Ethan','Mia','Kai','Zara','Leo','Nia',
                     'Thabo','Lerato','Sipho','Naledi','Anele','Kagiso','Bongani','Amara'),
              cast(pmod(id * 7,  18) + 1 AS INT)), ' ',
    element_at(array('Mokoena','Nkosi','Dlamini','Botha','Naidoo','Khan','Pillay','Vermaak',
                     'Sithole','Marais','Adams','Fourie','Jacobs','Meyer','Zulu','Ncube'),
              cast(pmod(id * 13, 16) + 1 AS INT))
  )                                                                  AS full_name,
  date_add('1955-01-01', cast(pmod(id * 97, 16000) AS INT))          AS dob,
  concat('ID', lpad(cast(pmod(id * 999983, 9999999999) AS BIGINT), 10, '0')) AS national_id,
  concat('TAX', lpad(cast(pmod(id * 88883, 999999999) AS BIGINT), 9, '0'))   AS tax_number,
  concat('customer', id, '@example.co.za')                          AS email,
  concat('+2782', lpad(cast(pmod(id * 31, 9999999) AS INT), 7, '0')) AS phone,
  concat(cast(pmod(id, 200) + 1 AS INT), ' ', element_at(array('Church','Voortrekker','Main','Klipfontein','Vilakazi','Govan Mbeki'), cast(pmod(id,6)+1 AS INT)), ' St') AS address,
  -- Broad SA metro + township/secondary-city footprint (retail, not private-wealth enclaves)
  element_at(array('Johannesburg','Cape Town','Durban','Pretoria','Soweto','Mitchells Plain','Bloemfontein','Polokwane','Mthatha','Rustenburg'), cast(pmod(id, 10) + 1 AS INT)) AS city,
  'South Africa'                                                     AS country,
  -- Capitec Global One product tiers (mass-market retail), weighted toward entry/active
  element_at(array('global_one_entry','global_one_active','global_one_active','global_one_plus','business'), cast(pmod(id, 5) + 1 AS INT)) AS segment,
  -- FICA CDD tier (most retail clients are simplified tier1; a minority tier2/3)
  element_at(array('tier1','tier1','tier1','tier2','tier3'), cast(pmod(id, 5) + 1 AS INT)) AS kyc_tier,
  element_at(array('Retail worker','Teacher','Nurse','Driver','Small trader','Domestic worker',
                   'Security officer','Student','Pensioner','Self-employed'), cast(pmod(id, 10) + 1 AS INT)) AS declared_occupation,
  -- Declared expected monthly turnover (ZAR). THE key AML field. For legit customers
  -- the seeded actual throughput is engineered to track this; planted subjects breach it.
  cast(element_at(array(8000.0, 12000.0, 18000.0, 25000.0, 40000.0), cast(pmod(id, 5) + 1 AS INT)) AS DOUBLE) AS declared_monthly_turnover,
  (pmod(id, 250) = 0)                                                AS pep_flag,   -- ~0.4% PEPs
  -- Employer name deliberately spelled inconsistently across the base (ER noise)
  element_at(array('Shoprite Holdings','Shoprite Hldgs','Transnet SOC','Transnet','Eskom',
                   'Dept of Education','Dept. of Education','Pick n Pay','PnP Retailers','Self'),
             cast(pmod(id * 3, 10) + 1 AS INT))                      AS employer_name,
  concat('DEV', lpad(cast(pmod(id * 40009, 90000000) AS BIGINT), 8, '0')) AS device_id,
  cast(date_add('2018-01-01', cast(pmod(id * 17, 2900) AS INT)) AS TIMESTAMP) AS onboarded_at,
  element_at(array('app','branch','agent'), cast(pmod(id, 3) + 1 AS INT)) AS onboarding_channel,
  element_at(array('data_vault','tabular','crm'), cast(pmod(id, 3) + 1 AS INT)) AS source_system,
  current_timestamp()                                                AS _ingested_at
FROM ids;

-- ── THIRD PARTIES (3,000) ────────────────────────────────────────────────
INSERT OVERWRITE capitec_fraud_aml_bronze.third_parties
WITH ids AS (SELECT id FROM range(1, 3001))
SELECT
  concat('TP', lpad(id, 6, '0'))                                     AS third_party_id,
  CASE WHEN pmod(id,3)=0
       THEN concat(element_at(array('Aurora','Summit','Delta','Onyx','Vanguard','Meridian','Cobalt','Zenith'), cast(pmod(id*3,8)+1 AS INT)), ' ',
                   element_at(array('Holdings','Trust','Capital','Ventures','Trading','Nominees'), cast(pmod(id*5,6)+1 AS INT)))
       ELSE concat(element_at(array('Sena','Otto','Priya','Marco','Yusuf','Elena','Dumi','Chen'), cast(pmod(id*7,8)+1 AS INT)), ' ',
                   element_at(array('Rossouw','Patel','Ndlovu','Silva','Abrahams','Kruger'), cast(pmod(id*11,6)+1 AS INT)))
  END                                                                AS full_name,
  element_at(array('individual','company','trust'), cast(pmod(id,3)+1 AS INT)) AS entity_kind,
  concat('ID', lpad(cast(pmod(id * 777767, 9999999999) AS BIGINT), 10, '0')) AS national_id,
  concat('TAX', lpad(cast(pmod(id * 66653, 999999999) AS BIGINT), 9, '0'))   AS tax_number,
  concat(cast(pmod(id, 300) + 1 AS INT), ' Commissioner St')         AS address,
  element_at(array('Johannesburg','Cape Town','London','Dubai','Mauritius','Durban'), cast(pmod(id, 6) + 1 AS INT)) AS city,
  element_at(array('South Africa','South Africa','United Kingdom','UAE','Mauritius','South Africa'), cast(pmod(id, 6) + 1 AS INT)) AS country,
  cast(date_add('2015-01-01', cast(pmod(id * 23, 3500) AS INT)) AS TIMESTAMP) AS registered_at,
  element_at(array('register','kyc_doc'), cast(pmod(id,2)+1 AS INT)) AS source_system,
  current_timestamp()                                                AS _ingested_at
FROM ids;

-- ── ACCOUNTS (~12,000: 1–4 per customer) ─────────────────────────────────
INSERT OVERWRITE capitec_fraud_aml_bronze.accounts
WITH cust AS (SELECT id FROM range(1, 5001)),
     -- give each customer between 1 and 4 accounts, ~2.4 avg -> ~12k
     expanded AS (
       SELECT c.id AS cust_num, e.n AS acct_seq
       FROM cust c
       LATERAL VIEW explode(sequence(1, cast(pmod(c.id, 4) + 1 AS INT))) e AS n
     )
SELECT
  concat('ACC', lpad(cast(cust_num * 10 + acct_seq AS BIGINT), 8, '0')) AS account_id,
  concat('CUST', lpad(cust_num, 6, '0'))                             AS customer_id,
  -- Global One structure: transactional account, savings pockets, fixed-term savings, card
  element_at(array('global_one_transact','savings_pocket','fixed_savings','card'), cast(pmod(cust_num + acct_seq, 4) + 1 AS INT)) AS account_type,
  'ZAR'                                                              AS currency,
  cast(date_add('2018-06-01', cast(pmod(cust_num * 7 + acct_seq, 2700) AS INT)) AS TIMESTAMP) AS opened_at,
  -- ~8% dormant (candidates for reactivation planting later)
  CASE WHEN pmod(cust_num * 3 + acct_seq, 12) = 0 THEN 'dormant' ELSE 'active' END AS status,
  CASE WHEN pmod(cust_num * 3 + acct_seq, 12) = 0
       THEN date_sub(current_date(), cast(200 + pmod(cust_num, 160) AS INT))
       ELSE date_sub(current_date(), cast(pmod(cust_num, 30) AS INT)) END AS last_activity_before_ts,
  -- Retail balances: most R200–R60k, with a long tail up to ~R250k (not private-wealth millions)
  round(pmod(cust_num * 9973, 250000) + 200, 2)                     AS balance,
  element_at(array('data_vault','tabular','crm'), cast(pmod(cust_num, 3) + 1 AS INT)) AS source_system,
  current_timestamp()                                                AS _ingested_at
FROM expanded;
