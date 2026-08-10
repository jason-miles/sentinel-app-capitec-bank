# Capitec Sentinel — Deployment Guide + Director's Notes

This is the **third** build of the Sentinel Fraud & AML app (after Nedbank and
Investec). It is a **fully isolated** deployment: its own bundle name, schemas, app
name, pipeline/job names, and Genie/dashboard IDs, so it can run alongside the other
two without collision.

> **All data is synthetic — DEMO DATA.** Names, IDs, and entities are fabricated. The
> planted typologies are textbook patterns from public FATF guidance; nothing here is a
> real evasion technique or a real person/company.

---

## 0. What makes this build "Capitec"

| Dimension            | Value |
|----------------------|-------|
| Brand                | Capitec deep blue `#003b5c` + signature red `#e2001a` (light + dark themes, logo, favicon) |
| Market framing       | Mass-market retail bank; **Global One** account tiers; ZAR; SA metro + township footprint |
| Regulatory framing   | **FICA / FIC** (STRs & CTRs to the Financial Intelligence Centre via **goAML**), **SARB** Prudential Authority, **POPIA**, **NCA** |
| Filing institution   | `Capitec Bank Limited` (goAML reporting entity `CAPITEC-ZA`) |
| Bundle name          | `capitec_sentinel` |
| Nested pipeline bundle | `capitec_fraud_aml_pipeline` |
| App name             | `capitec-fraud-aml` |
| Schemas              | `capitec_fraud_aml_bronze` / `_silver` / `_gold` in `elexon_app_for_settlement_acc_catalog` |
| Pipeline / jobs      | `capitec_fraud_aml_pipeline_etl`, `capitec_fraud_aml_daily_report`, `capitec_fraud_aml_stream_trigger`, `capitec_fraud_ml_retrain` |

### Detection families (10)
The nine inherited families (rapid movement, frequency spike, circular ring, dormant
reactivation, risk-rating jump, adverse media, UBO change, account takeover, impossible
travel) **plus** a new **cash structuring** rule (`detect_structuring`) keyed to the SA
R25,000 Cash Threshold Report (CTR) limit.

### New capability surfaces added for the Capitec brief
- **Actual-vs-declared turnover** (`declared_monthly_turnover` on customers → surfaced in
  `customer_360` and scored in `pkyc_customer_risk`) — the flagship CDD signal.
- **AML knowledge + SAR corpus** (`bronze.aml_knowledge`, `bronze.sar_narratives`) with
  vector indexes → the SAR "policy" agent cites bank policy + FATF (`retrieve_policy`).
- **Retrospective typology sweep** (`gold.typology_exposure`, `/api/aml/typology-sweep`)
  for the gaming/third-party-processor layering typology.
- **Merchant categories, device/IP, cross-border flags** on transactions for the above.

---

## 1. Prerequisites
- Databricks CLI ≥ 0.288.0, authenticated to the workspace profile
  `fevm-elexon-app-for-settlement-acc`.
- A running SQL warehouse (setup uses Serverless Starter).
- `ALL PRIVILEGES` on `elexon_app_for_settlement_acc_catalog` (no `CREATE CATALOG`
  needed — the medallion is co-located as prefixed schemas; see README).

## 2. Create schemas + seed synthetic data
Run against the warehouse, in order:
```sql
-- foundation (schemas + landing volume)
sql/00_foundation/00_schemas.sql
-- bronze DDL (now includes declared turnover, merchant_category, device/ip,
-- aml_knowledge, sar_narratives)
sql/01_bronze/01_bronze_tables.sql
-- synthetic data (5 files, in order)
data/01_seed_customers_accounts.sql
data/02_seed_transactions.sql
data/03_seed_supporting.sql
data/04_plant_scenarios.sql      -- legacy families + WOW-A mule net + WOW-C gaming + ER dups
data/05_seed_knowledge.sql       -- AML policy/typology/FATF corpus + historical STRs
```
Then the Sherlock / governance / intelligence SQL under `sql/02_silver` … `sql/06_*`
(same order as the Investec build; the new files `sql/06_sherlock/08_typology_sweep.sql`
and `sql/05_intelligence/07_aml_knowledge_vector_search.sql` slot in with their peers).

## 3. Deploy the bundle (app + pipeline + jobs)
```bash
databricks bundle deploy -t dev --profile fevm-elexon-app-for-settlement-acc
# first/clean pipeline build must be a full refresh so cross-schema MVs order correctly:
databricks bundle run capitec_fraud_aml_pipeline_etl --full-refresh-all \
  -t dev --profile fevm-elexon-app-for-settlement-acc
```
All 10 detection families are expected to fire against the planted scenarios after a
full refresh.

## 4. Provision the isolated Genie space + dashboard, then wire the app
The app config (`app/backend/app.yaml`) intentionally ships **placeholders** for the
Capitec-specific Genie space and dashboard so they don't point at Investec's:
```
SENTINEL_GENIE_SPACE   = REPLACE_WITH_CAPITEC_GENIE_SPACE_ID
SENTINEL_DASHBOARD_ID  = REPLACE_WITH_CAPITEC_DASHBOARD_ID
```
1. Create a Genie space from `genie/fraud_aml_analyst_space.json` (already points at the
   `capitec_fraud_aml_*` tables and includes the new turnover + typology questions).
2. Import the dashboard from `dashboards/exec_overview.lvdash.json`.
3. Paste both IDs into `app/backend/app.yaml` (and re-deploy the app), or set them as app
   resources/env in the workspace.

## 5. Rebuild the frontend (only if you change UI)
```bash
cd app/backend/frontend && npm install && npm run build
cp -r dist ../webroot     # the app serves built assets from webroot/
```
The committed `webroot/` is already built with Capitec branding.

## 6. Verify
- `cd app/backend && .venv/bin/python -m pytest -q` → 34 passing (goAML, scoring, SLA,
  casestate, routes, guardrail). Use a **Python 3.12** venv (pydantic-core has no 3.14 wheel).
- App landing page shows the Capitec blue/red hero; favicon is the blue tile + red "C".

---

## Director's Notes — planted signals → scenario map
Keep this handy while driving the demo. All planted IDs use `FRAUD` / `MULE` / `GAME` /
`DUP` prefixes so they are easy to trace.

### WOW-A — the hidden mule network  (detect)
- **Open:** `CASE-90001` (Lerato Sithole, `CUSTMULE01`) — a lone **cash-structuring**
  alert: 3 sub-threshold cash deposits (~R20.5k–24.5k, each under the R25k CTR).
- **Expand:** entity resolution shows 7 mules (`CUSTMULE01`–`07`) sharing device
  `DEVMULE0001`, IP `197.245.10.5`, and address `88 Recruiter St, Soweto`, all opened
  within a 3-week window. Each forwards ~R40k (≈90%) within 48h to aggregator
  `CUSTMULE00` (Kabelo Motaung, `CASE-90002`), which remits **R260k cross-border SWIFT**
  to `Onyx Capital` (Mauritius, `TPFRAUD01`).
- **Killer line:** 3 sibling mule accounts were previously alerted and **closed as false
  positives in isolation** (see `alert_feedback`) — the siloed-rules failure mode.
- **Fires:** `structuring` on each mule + `rapid_movement` on the aggregator + network
  graph + cross-border flag.

### WOW-B — STR drafted in 90 seconds  (document)
- On any hero case, run **SAR Filing** → multi-agent orchestration. The evidence pack is
  auto-gathered; the **policy agent cites** the bank AML policy + FATF typology guides
  (`aml_knowledge`), the adverse-media agent cites retrieved articles, and the supervisor
  emits a **FIC-format STR narrative** + downloadable **goAML XML** (schema-validated).
- Ask the "why structuring, not legitimate cash business?" follow-up — the evidence brief
  includes actual-vs-declared turnover so the answer is grounded.

### WOW-C — retrospective typology sweep  (anticipate)
- Ask (Genie / typology-sweep): *"third-party payment processors layering through gaming
  merchants — do we have exposure?"* → `/api/aml/typology-sweep` surfaces `CUSTGAME01`
  (Werner Pretorius, `CASE-90003`) and `CUSTGAME02`: ~30 matched card debits to a gaming
  TPP with near-equal payouts back (net ≈ 0), **never tripped a rule** (`never_alerted =
  true`).

### Supporting planted signals (legacy families, individually)
- Rapid movement `ACCFRAUD05`; velocity spike `ACCFRAUD01`; circular ring
  `ACCFRAUD01→02→03→04→01`; dormant reactivation `ACCDORM01`–`05`; risk-rating jump
  `CUSTFRAUD01/02`; adverse media (`Sipho Dlamini`/`Onyx Capital`); UBO change `TPFRAUD01`;
  account takeover `ACCATO01` (Lagos device); impossible travel 3 cards (JHB→London/
  Dubai/New York).
- Messy ER duplicates: `Jan van der Merwe` / `J. v.d. Merwe` / `Johannes vdMerwe`
  (`CUSTDUP01`–`03`, shared national_id → one entity).

### Streaming (optional live drama)
`data/stream/drop_transactions.py --scenario layering|impossible_travel|normal` drops a
JSON file into the landing volume; a plain incremental pipeline run surfaces the fresh
alert in seconds (see `fraud_aml_pipeline/CLAUDE.md`).
