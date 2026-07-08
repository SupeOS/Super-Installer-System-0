# Super Installer OS — Architecture Map

This document maps the database to (a) your real Process workflow sheet and
(b) the master-plan stages. Read it before approving the schema. Your friend
who proofs code should read it too.

---

## The one big idea

Your Process sheet shows that **every dollar event currently gets entered in
three places**: a customer record, a general ledger, and an HST account. That's
triple manual entry — slow and error-prone.

The new design records each event **once** in a central ledger (`transactions`),
tagged with its customer, job, category, and HST. Then the three views you need
(customer / general / HST) and your Year→Quarter reports are just *queries* that
read that one ledger. Enter once, report everywhere.

---

## The three pillars

```
                    ┌──────────────────────────────────┐
                    │  REPORTING LAYER (views, read-only)│
                    │  quarterly · HST · receivables ·   │
                    │  job profit · customer · supplier  │
                    └──────────────────────────────────┘
                                 ▲ reads
   ┌─────────────────────────────┼─────────────────────────────┐
   │ PILLAR 1: TRANSACTIONAL      │ PILLAR 2: DOCUMENTS  PILLAR 3: COMMS
   │ customers                   │ documents            communications
   │  ├ leads                    │  (quotes, supplier   (SMS/email/note,
   │  ├ jobs (tax by location)   │   invoices, BOL,      one timeline)
   │  │  ├ quotes                │   contracts, photos,
   │  │  ├ purchase_orders       │   floor plans, RFP,  PILLAR 4: ADMIN
   │  │  ├ invoices (draws)      │   proposals, service checklist_templates
   │  │  └ (transactions)        │   agreements,        job_checklist_items
   │  ├ transactions  ← LEDGER   │   warranties, legal) reminders
   │  ├ payments                 │                      sop_library
   │  └ referral_code            │                      approvals
   │ suppliers · products ·      │                      workflow_runs
   │ rates · settings · counters │                      (agentic)
   └─────────────────────────────┘
```

---

## Every table, what it is, and when it activates

| Table | Purpose | Activates in | Used now? |
|---|---|---|---|
| `customers` | The spine. Everyone you deal with. Carries referral_code from day 1. | Stage 1–2 | ✅ |
| `leads` | Where work came from; pre-job pipeline. | Stage 2 | soon |
| `jobs` | The unit that gets scheduled, costed, invoiced. One customer → many jobs. | Stage 2 | ✅ |
| `quotes` | Quote versions per job. One gets accepted. | Stage 1 | ✅ |
| `purchase_orders` | Orders to suppliers; tracks Order Ack + BOL. | Stage 3 | later |
| `invoices` | Customer invoices (deposit + balance). | Stage 3 | later |
| `transactions` | **The ledger.** Every income/expense with HST, category, links. | Stage 3 | later |
| `payments` | Money received against invoices. | Stage 3 | later |
| `documents` | Catalog of every file. Bytes live in Storage. | Stage 2–4 | soon |
| `communications` | Twilio SMS, email, notes — one timeline per customer. | Stage 2 | soon |
| `suppliers` | Beaulieu, Centura, etc. | Stage 1 (catalogue) | ✅ |
| `products` | Material catalogue. | Stage 1 | ✅ |
| `price_history` | Audit trail of product cost changes. | Stage 1/6 | later |
| `rates` | Labour/removal/install/shipping rate sheet. | Stage 1 | ✅ |
| `settings` | margin, default tax, wastage, shipping markup. | Stage 1 | ✅ |
| `counters` | Sequential FF-/JOB-/INV-/PO- numbers. | Stage 1–3 | ✅ |
| `checklist_templates` + `_steps` | Reusable process checklists (your sheet). | Stage 2 | soon |
| `job_checklist_items` | Per-job TRUE/FALSE process steps. | Stage 2 | soon |
| `reminders` | Insurance / tax / WCB / registration renewals. | Stage 2/6 | soon |
| `sop_library` | SOPs, doc templates, policies, guides. | Stage 2 | soon |
| `approvals` | Who approved/signed what, when. | Stage 2 | soon |
| `workflow_runs` | Log of agentic/automated actions (human-gated). | Stage 8 | later |

---



---

## Tax is per-job, not global

Tax follows the **job site address**, not your business address:

- Job in **Ontario** → 13% HST
- Job in **Alberta** → 5% GST

When a job is created, its province stamps `tax_rate` and `tax_label` onto the
job. Every quote, invoice, and transaction for that job inherits the right rate.
The global `settings` value is only a default for new jobs. This means a Rainy
River job and a Bonnyville job on the same day each carry correct tax, and your
`report_tax` view splits collected vs. paid correctly regardless of mix.

---

## Expenses: job-level vs. business overhead

Every expense is one of two kinds, flagged by `transactions.is_overhead`:

**Job-level** (counts against that job's profit):
material · supplies · **tools** · shipping · labour · **subcontractor**
(plumber, janitorial) · fuel · **equipment_rental** · **lodging** ·
**vehicle_rental** · misc

**Business overhead** (counts against the business P&L, not one job):
insurance · registration · **property_rental** (crew house, shop, storage) ·
utilities · **referral_commission** (e.g. real-estate agent) ·
**sales_commission** · software · admin_other

This split is what lets `report_job_profit` show true per-job margin (job costs
only) while `report_quarterly` shows the whole business including overhead.

---

## Invoicing: deposit → draws → balance

Once a quote is approved:

1. **Deposit invoice** (material) — triggers the sales/ordering workflow
2. **Draw invoice(s)** — optional, for large or long jobs (progress billing),
   numbered 1, 2, 3…
3. **Balance invoice** (labour) — at completion

All attach to the same job. `invoices.kind` = deposit|draw|balance|full, with
`draw_number` for sequencing.

---

## Your Process sheet → the database

This is your current manual workflow, and what replaces each step.

| Process step (your sheet) | Becomes | Tables touched |
|---|---|---|
| **1. Cx Contact** — folder creation, log to Cx Database | Create customer record (folder auto-noted) | `customers` |
| **2. Measure** — samples, quote, print PDF | Create job + quote; generate PDF; file it | `jobs`, `quotes`, `documents` |
| **3. Rate Quote** — log rate quote #, pickup #, receipt → Cx + General + HST | Store on job; receipt becomes one ledger expense (auto-splits to all 3 views) | `jobs`, `transactions`, `documents` |
| **4. Material Deposit** — QB invoice, PDF → Cx invoice + General income, Material HST | Deposit invoice + income transaction (HST captured) | `invoices`, `transactions`, `documents` |
| **5. Order Product** — order ack → Cx + General expense + HST | PO + supplier-invoice document + expense transaction | `purchase_orders`, `transactions`, `documents` |
| **6. Job Prep/Work Order** — supplies, shipping, misc, labour (each → Cx + General + HST) | Each cost = one ledger transaction with its category | `transactions` (categories: supplies, shipping, misc, labour, fuel) |
| **7. Job Completion** — invoice w/ balance, payment, HST | Balance invoice + payment + income transaction | `invoices`, `payments`, `transactions` |
| **8. Overhead Expenses** — scan receipts, review budgeting | Overhead transactions + filed receipts | `transactions` (category: overhead), `documents` |
| **Reconcile HST / Compile Tax** | Already computed — just read the report | `report_hst`, `report_quarterly` |

The triple "Copy to Cx / Copy to General / Move HST" columns become three
boolean flags on each transaction (`logged_cx`, `logged_general`, `hst_moved`)
so you can still tick them off during the QuickBooks transition — then they go
away once the ledger fully replaces QB.

---

## Your job status pipeline (from the checklist column)

The `jobs.status` field walks through exactly your stages:

```
lead → measured → quoted → contract → deposit → ordered →
scheduled → in_progress → completed → invoiced → paid → closed
```

(plus `lost` at any point). This drives the CRM pipeline view in Stage 2.

---

## Your Drive structure → documents

Your sheet's "General Admin → Cx Database → Admin Book → Dashboard, by Year →
Quarter" maps to:

- `documents.fiscal_year` + `fiscal_quarter` — auto-stamped, so "all docs from
  2026 Q2" is one filter.
- `documents.doc_type` — your file kinds: `quote`, `contract`,
  `deposit_receipt`, `customer_invoice`, `supplier_invoice`,
  `order_acknowledgement`, `bol_shipping`, `payment_receipt`, `signoff`,
  `photo_before`, `photo_after`, `photo_progress`, `legal`, `insurance`, `wcb`,
  `correspondence`, `floor_plan`, `rfp`, `proposal_template`,
  `service_agreement`, `warranty`, `registration`, `work_order`,
  `purchase_order`, `other`.
- `documents.customer_id` / `job_id` — so "every file for this job" is one query.

Files themselves live in a Supabase Storage bucket; this table is the index.

---

## The reporting layer (already built as views)

These answer the questions you listed. They read the ledger; you never maintain
them.

| Report view | Answers |
|---|---|
| `report_quarterly` | Revenue, expense, profit, HST by year + quarter |
| `report_tax` | Tax collected − paid = owing, per quarter, correct per province |
| `report_customer_summary` | Lifetime revenue/cost/job-count per customer |
| `report_job_profit` | Profit per job, broken into material/labour/shipping/fuel/supplies/misc |
| `report_receivables` | Every unpaid/partial invoice + balance owing |
| `report_supplier_spend` | Spend with each supplier per quarter (e.g. Beaulieu YTD) |

---

## Decisions locked in (painful to change later, done now)

1. **Money = integer cents.** No floating-point dollar errors, ever.
2. **Customer is the spine; job is the billing unit.** Quote → job → invoice
   flows cleanly.
3. **One ledger, many views.** No manual triple-entry.
4. **Referral code on every customer from creation.** Stage 7 needs no backfill.
5. **Universal documents catalog + Storage.** Every file findable.
6. **Communications timeline from day one.** Twilio plugs in without rework.
7. **Soft deletes.** Accounting/tax history never lost.
8. **Auto fiscal year/quarter** on every transaction and document — matches your
   Year→Quarter filing exactly.
9. **Tax per job location** (ON 13% / AB 5%) — never a wrong rate.
10. **Job-level vs. overhead expense split** — true job margin AND business P&L.
11. **Admin infrastructure** — per-job checklists, reminders, SOPs, approvals,
    and an agentic-workflow log (human-gated) all on the same spine.

---

## What we build against this, in order

- **Now (Stage 1→2 bridge):** customers, jobs, quotes, rates, settings,
  products, counters — save/load a quote, customer autocomplete, quote list.
- **Stage 2:** documents + storage (file the PDF automatically), communications
  (Twilio), lead pipeline.
- **Stage 3:** invoices, transactions ledger, payments — the money layer +
  reports go live.
- **Later stages:** maps, visualization, marketing, AI agents — each just adds
  tables/views that reference the spine. Nothing here gets rebuilt.

---

## Resolved decisions (confirmed)

✅ **Job** is the billing unit; a job may hold multiple quotes to compare; a
   later project is a new job.
✅ **Tax by job site**: ON 13% HST, AB 5% GST.
✅ **Invoicing**: deposit (material) → optional draws → balance (labour).
✅ **Expense categories** expanded and split into job-level vs. overhead
   (tools separated from supplies; subcontractors, equipment/vehicle rental,
   lodging, property rental, utilities, insurance, registration, referral &
   sales commissions, admin all included).
✅ **Document types** expanded: + floor_plan, rfp, proposal_template,
   service_agreement, warranty (plus the originals).
✅ **Admin infrastructure**: per-job checklists, recurring reminders, SOP/
   template library, approvals, agentic workflow log.

## Still open (not blocking — decide when we reach them)

- Quote currently shows a single tax line; we'll switch it to read the job's
  province-based rate once quotes attach to jobs (next build step).
- Whether draws are a fixed schedule or ad-hoc per job (default: ad-hoc).
