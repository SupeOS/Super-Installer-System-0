-- ════════════════════════════════════════════════════════════════════════════
-- SUPER INSTALLER OS — FULL SKELETON SCHEMA  (v2 — master-plan aligned)
-- Built from the Process workflow sheet + master plan.
--
-- Design principles:
--   • The CUSTOMER is the spine. Everything references back to it.
--   • A JOB is the unit that gets scheduled, costed, invoiced.
--   • Every dollar event is ONE row in `transactions` (the ledger), carrying
--     its HST, category, customer, and job — so customer / general / HST views
--     and Year→Quarter reports all derive automatically. No triple-entry.
--   • Money stored as INTEGER CENTS (never floating-point dollars).
--   • Every file is cataloged in `documents`.
--   • Soft deletes via archived_at — history is never destroyed.
--   • Future-stage tables exist now as skeletons; only Stage 1–2 used at first.
--
-- Paste whole file into Supabase → SQL Editor → Run. Safe to re-run.
-- ════════════════════════════════════════════════════════════════════════════

create extension if not exists "uuid-ossp";

-- ── SUPPLIERS (referenced by jobs/PO/transactions) ──────────────────────────
create table if not exists suppliers (
  id                    uuid primary key default uuid_generate_v4(),
  name                  text not null unique,
  contact_email         text,
  contact_phone         text,
  catalogue_email_label text,
  lead_time_days        integer,
  account_number        text,
  notes                 text,
  created_at            timestamptz default now(),
  archived_at           timestamptz
);

-- ════════════════════════════════════════════════════════════════════════════
-- PILLAR 1 — TRANSACTIONAL CORE (customer spine)
-- ════════════════════════════════════════════════════════════════════════════

create table if not exists customers (
  id            uuid primary key default uuid_generate_v4(),
  name          text not null,
  company       text,
  address       text,
  city          text,
  province      text default 'AB',
  postal_code   text,
  phone         text,
  email         text,
  source        text,
  referral_code text unique,                  -- THEIR code (Stage 7-ready)
  referred_by   uuid references customers(id) on delete set null,
  notes         text,
  drive_folder  text,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now(),
  archived_at   timestamptz
);

create table if not exists leads (
  id            uuid primary key default uuid_generate_v4(),
  customer_id   uuid references customers(id) on delete cascade,
  source        text,
  campaign      text,
  status        text default 'new',
  notes         text,
  created_at    timestamptz default now(),
  archived_at   timestamptz
);

create table if not exists jobs (
  id            uuid primary key default uuid_generate_v4(),
  job_number    text unique,
  customer_id   uuid references customers(id) on delete set null,
  customer_name text,
  title         text,
  status        text default 'lead',
  site_address  text,
  site_city     text,
  measure_date  date,
  install_date  date,
  completion_date date,
  is_out_of_town boolean default false,
  rate_quote_number text,
  pickup_number text,
  -- Tax driven by job site location
  tax_province  text default 'AB',            -- 'ON' => 13% HST, 'AB' => 5% GST
  tax_rate      numeric default 0.05,         -- stamped from province at creation
  tax_label     text default 'GST',           -- 'HST' or 'GST' for display
  notes         text,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now(),
  archived_at   timestamptz
);

create table if not exists quotes (
  id            uuid primary key default uuid_generate_v4(),
  quote_number  text unique,
  job_id        uuid references jobs(id) on delete cascade,
  customer_id   uuid references customers(id) on delete set null,
  customer_name text,
  product       text,
  version       integer default 1,
  status        text default 'draft',
  date          text,
  rooms         jsonb default '[]',
  extras        jsonb default '[]',
  shipping_cents   bigint default 0,
  supplies_cents   bigint default 0,
  subtotal_cents   bigint default 0,
  hst_cents        bigint default 0,
  total_cents      bigint default 0,
  profit_cents     bigint default 0,
  margin_pct       numeric default 0,
  notes         text,
  terms_labour  text,
  terms_warranty text,
  terms_payment text,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now(),
  archived_at   timestamptz
);

create table if not exists purchase_orders (
  id            uuid primary key default uuid_generate_v4(),
  po_number     text unique,
  job_id        uuid references jobs(id) on delete cascade,
  supplier_id   uuid references suppliers(id) on delete set null,
  supplier_name text,
  status        text default 'draft',
  order_ack_ref text,
  bol_ref       text,
  ordered_at    date,
  delivered_at  date,
  total_cents   bigint default 0,
  hst_cents     bigint default 0,
  notes         text,
  created_at    timestamptz default now(),
  archived_at   timestamptz
);

create table if not exists invoices (
  id            uuid primary key default uuid_generate_v4(),
  invoice_number text unique,
  job_id        uuid references jobs(id) on delete cascade,
  customer_id   uuid references customers(id) on delete set null,
  customer_name text,
  kind          text default 'balance',        -- deposit | draw | balance | full
  draw_number   integer,                        -- 1,2,3... for progress draws
  status        text default 'draft',
  subtotal_cents bigint default 0,
  hst_cents      bigint default 0,
  total_cents    bigint default 0,
  amount_paid_cents bigint default 0,
  issued_on     date,
  due_on        date,
  paid_on       date,
  qb_reference  text,
  notes         text,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now(),
  archived_at   timestamptz
);

-- ── THE LEDGER (heart of finance + reporting) ───────────────────────────────
create table if not exists transactions (
  id            uuid primary key default uuid_generate_v4(),
  direction     text not null,                -- income | expense
  category      text not null,                -- deposit|balance_payment|material|supplies|shipping|labour|fuel|misc|overhead|other_income
  customer_id   uuid references customers(id) on delete set null,
  job_id        uuid references jobs(id) on delete set null,
  supplier_id   uuid references suppliers(id) on delete set null,
  invoice_id    uuid references invoices(id) on delete set null,
  po_id         uuid references purchase_orders(id) on delete set null,
  is_overhead   boolean default false,          -- true = business overhead, not job-level
  amount_cents  bigint not null default 0,
  tax_cents     bigint not null default 0,      -- renamed concept: GST or HST
  tax_label     text default 'GST',
  total_cents   bigint not null default 0,
  logged_cx       boolean default false,
  logged_general  boolean default false,
  hst_moved       boolean default false,
  reconciled      boolean default false,
  occurred_on   date not null default current_date,
  fiscal_year   integer,
  fiscal_quarter integer,
  description   text,
  document_id   uuid,                          -- FK added after documents table
  created_at    timestamptz default now(),
  archived_at   timestamptz
);

create table if not exists payments (
  id            uuid primary key default uuid_generate_v4(),
  invoice_id    uuid references invoices(id) on delete cascade,
  job_id        uuid references jobs(id) on delete set null,
  customer_id   uuid references customers(id) on delete set null,
  amount_cents  bigint not null default 0,
  method        text,
  received_on   date default current_date,
  reference     text,
  created_at    timestamptz default now()
);

-- ════════════════════════════════════════════════════════════════════════════
-- PILLAR 2 — DOCUMENTS / MEDIA (the filing cabinet)
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists documents (
  id            uuid primary key default uuid_generate_v4(),
  doc_type      text not null,
  title         text,
  storage_path  text,
  mime_type     text,
  customer_id   uuid references customers(id) on delete set null,
  job_id        uuid references jobs(id) on delete set null,
  quote_id      uuid references quotes(id) on delete set null,
  invoice_id    uuid references invoices(id) on delete set null,
  po_id         uuid references purchase_orders(id) on delete set null,
  supplier_id   uuid references suppliers(id) on delete set null,
  transaction_id uuid references transactions(id) on delete set null,
  fiscal_year   integer,
  fiscal_quarter integer,
  tags          text[],
  notes         text,
  created_at    timestamptz default now(),
  archived_at   timestamptz
);

-- Now wire transactions.document_id → documents.id (circular ref resolved)
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'transactions_document_fk'
  ) then
    alter table transactions
      add constraint transactions_document_fk
      foreign key (document_id) references documents(id) on delete set null;
  end if;
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- PILLAR 3 — COMMUNICATIONS (Twilio SMS, email, notes — one timeline)
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists communications (
  id            uuid primary key default uuid_generate_v4(),
  channel       text not null,                  -- sms | email | call | note
  direction     text,                           -- inbound | outbound
  customer_id   uuid references customers(id) on delete cascade,
  job_id        uuid references jobs(id) on delete set null,
  subject       text,
  body          text,
  twilio_sid    text,
  status        text,
  occurred_at   timestamptz default now(),
  created_at    timestamptz default now()
);

-- ════════════════════════════════════════════════════════════════════════════
-- SUPPORTING — products, rates, settings, price history
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists products (
  id          uuid primary key default uuid_generate_v4(),
  sku         text,
  name        text not null,
  supplier    text,
  category    text,
  collection  text,
  unit        text default 'ft',
  cost_cents  bigint default 0,
  notes       text,
  updated_at  timestamptz default now(),
  archived_at timestamptz
);

create table if not exists price_history (
  id          uuid primary key default uuid_generate_v4(),
  product_id  uuid references products(id) on delete cascade,
  old_cents   bigint,
  new_cents   bigint,
  source      text default 'manual',
  changed_at  timestamptz default now()
);

create table if not exists rates (
  id          uuid primary key default uuid_generate_v4(),
  section     text not null,
  name        text not null,
  rate_cents  bigint not null default 0,
  unit        text not null default 'ft',
  updated_at  timestamptz default now(),
  unique (section, name)
);

create table if not exists settings (
  key         text primary key,
  value       numeric not null,
  updated_at  timestamptz default now()
);

-- ════════════════════════════════════════════════════════════════════════════
-- PILLAR 4 — ADMINISTRATIVE INFRASTRUCTURE
-- Checklists, reminders, SOP library, approvals, agentic workflow runs.
-- ════════════════════════════════════════════════════════════════════════════

-- ── CHECKLIST TEMPLATES (your Process sheet, reusable) ──────────────────────
-- A template is an ordered set of steps. Each job gets its own copy of the
-- relevant template's steps in `job_checklist_items`.
create table if not exists checklist_templates (
  id          uuid primary key default uuid_generate_v4(),
  name        text not null,                  -- e.g. "Standard Job Process"
  description text,
  created_at  timestamptz default now(),
  archived_at timestamptz
);

create table if not exists checklist_template_steps (
  id          uuid primary key default uuid_generate_v4(),
  template_id uuid references checklist_templates(id) on delete cascade,
  phase       text,                           -- Contact|Measure|Quote|Jobs|Invoicing
  step_order  integer not null default 0,
  label       text not null,                  -- e.g. "QB Invoice Generated"
  detail      text,                           -- e.g. "Print to Invoice Folder / Log Income"
  created_at  timestamptz default now()
);

-- ── PER-JOB CHECKLIST (mirrors your FALSE/TRUE columns) ─────────────────────
create table if not exists job_checklist_items (
  id          uuid primary key default uuid_generate_v4(),
  job_id      uuid references jobs(id) on delete cascade,
  phase       text,
  step_order  integer not null default 0,
  label       text not null,
  detail      text,
  done        boolean default false,          -- the TRUE/FALSE
  done_at     timestamptz,
  created_at  timestamptz default now()
);

-- ── RECURRING REMINDERS (insurance, HST/GST remittance, WCB, registration) ──
create table if not exists reminders (
  id            uuid primary key default uuid_generate_v4(),
  title         text not null,                -- "Liability insurance renewal"
  category      text,                         -- insurance|tax|wcb|registration|other
  due_on        date,
  recurrence    text,                         -- none|monthly|quarterly|annually
  lead_days     integer default 14,           -- notify this many days before
  completed_at  timestamptz,
  notes         text,
  created_at    timestamptz default now(),
  archived_at   timestamptz
);

-- ── SOP / TEMPLATE LIBRARY (how-to docs, standard procedures, doc templates) ─
create table if not exists sop_library (
  id          uuid primary key default uuid_generate_v4(),
  title       text not null,
  kind        text,                           -- sop | template | policy | guide
  category    text,                           -- ops|admin|sales|install|safety
  body        text,                           -- markdown content
  document_id uuid references documents(id) on delete set null, -- if it's a file
  version     integer default 1,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now(),
  archived_at timestamptz
);

-- ── APPROVALS / SIGN-OFFS (who approved what, when) ─────────────────────────
create table if not exists approvals (
  id            uuid primary key default uuid_generate_v4(),
  entity_type   text not null,                -- quote|invoice|po|job|document
  entity_id     uuid not null,                -- id of the thing approved
  action        text not null,                -- approved|signed|rejected|sent
  approved_by   text,                         -- name/role (client or owner)
  signature_ref text,                         -- link to signed document
  note          text,
  occurred_at   timestamptz default now()
);

-- ── AGENTIC WORKFLOW RUNS (Stage 8 — log of automated actions) ──────────────
-- Records each time an AI agent or automation does something, for audit + undo.
create table if not exists workflow_runs (
  id            uuid primary key default uuid_generate_v4(),
  agent         text,                          -- sales|estimating|purchasing|scheduling|marketing|price_update|executive
  trigger       text,                          -- what kicked it off
  status        text default 'pending',        -- pending|running|success|failed|needs_review
  entity_type   text,                          -- what it acted on
  entity_id     uuid,
  input         jsonb,                          -- params it received
  output        jsonb,                          -- what it produced (e.g. draft quote)
  needs_approval boolean default true,          -- human-in-the-loop gate
  approved_at   timestamptz,
  error         text,
  created_at    timestamptz default now()
);

-- ── COUNTERS ────────────────────────────────────────────────────────────────
create table if not exists counters (
  name     text primary key,
  current  integer not null default 0,
  prefix   text not null
);
insert into counters (name, current, prefix) values
  ('quote',   0, 'FF-'),
  ('job',     0, 'JOB-'),
  ('invoice', 0, 'INV-'),
  ('po',      0, 'PO-')
  on conflict (name) do nothing;

create or replace function next_number(counter_name text)
returns text language plpgsql as $$
declare n integer; p text;
begin
  update counters set current = current + 1
    where name = counter_name
    returning current, prefix into n, p;
  return p || lpad(n::text, 3, '0');
end;
$$;

-- ── TRIGGERS ────────────────────────────────────────────────────────────────
create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

create or replace function set_fiscal()
returns trigger language plpgsql as $$
declare d date;
begin
  d := coalesce(new.occurred_on, current_date);
  new.fiscal_year := extract(year from d);
  new.fiscal_quarter := extract(quarter from d);
  return new;
end; $$;

do $$
declare t text;
begin
  foreach t in array array['customers','jobs','quotes','invoices']
  loop
    execute format('drop trigger if exists touch_%I on %I;', t, t);
    execute format('create trigger touch_%I before update on %I
      for each row execute function touch_updated_at();', t, t);
  end loop;
end $$;

drop trigger if exists fiscal_tx on transactions;
create trigger fiscal_tx before insert or update on transactions
  for each row execute function set_fiscal();

-- ════════════════════════════════════════════════════════════════════════════
-- REPORTING VIEWS
-- ════════════════════════════════════════════════════════════════════════════
create or replace view report_quarterly as
select fiscal_year, fiscal_quarter,
  sum(case when direction='income'  then amount_cents else 0 end) as income_cents,
  sum(case when direction='expense' then amount_cents else 0 end) as expense_cents,
  sum(case when direction='income'  then amount_cents else 0 end)
    - sum(case when direction='expense' then amount_cents else 0 end) as profit_cents,
  sum(tax_cents) as tax_cents
from transactions where archived_at is null
group by fiscal_year, fiscal_quarter order by fiscal_year, fiscal_quarter;

create or replace view report_tax as
select fiscal_year, fiscal_quarter,
  sum(case when direction='income'  then tax_cents else 0 end) as tax_collected_cents,
  sum(case when direction='expense' then tax_cents else 0 end) as tax_paid_cents,
  sum(case when direction='income'  then tax_cents else 0 end)
    - sum(case when direction='expense' then tax_cents else 0 end) as tax_owing_cents
from transactions where archived_at is null
group by fiscal_year, fiscal_quarter order by fiscal_year, fiscal_quarter;

create or replace view report_customer_summary as
select c.id, c.name, c.company,
  count(distinct j.id) as job_count,
  coalesce(sum(case when t.direction='income'  then t.amount_cents else 0 end),0) as revenue_cents,
  coalesce(sum(case when t.direction='expense' then t.amount_cents else 0 end),0) as cost_cents
from customers c
left join jobs j on j.customer_id = c.id and j.archived_at is null
left join transactions t on t.customer_id = c.id and t.archived_at is null
where c.archived_at is null
group by c.id, c.name, c.company;

create or replace view report_job_profit as
select j.id, j.job_number, j.title, j.customer_name, j.status,
  coalesce(sum(case when t.direction='income' then t.amount_cents else 0 end),0) as revenue_cents,
  coalesce(sum(case when t.direction='expense' and t.category='material' then t.amount_cents else 0 end),0) as material_cents,
  coalesce(sum(case when t.direction='expense' and t.category='labour'   then t.amount_cents else 0 end),0) as labour_cents,
  coalesce(sum(case when t.direction='expense' and t.category='shipping' then t.amount_cents else 0 end),0) as shipping_cents,
  coalesce(sum(case when t.direction='expense' and t.category='fuel'     then t.amount_cents else 0 end),0) as fuel_cents,
  coalesce(sum(case when t.direction='expense' and t.category='supplies' then t.amount_cents else 0 end),0) as supplies_cents,
  coalesce(sum(case when t.direction='expense' and t.category='misc'     then t.amount_cents else 0 end),0) as misc_cents,
  coalesce(sum(case when t.direction='income'  then t.amount_cents else 0 end),0)
    - coalesce(sum(case when t.direction='expense' then t.amount_cents else 0 end),0) as profit_cents
from jobs j
left join transactions t on t.job_id = j.id and t.archived_at is null and t.is_overhead = false
where j.archived_at is null
group by j.id, j.job_number, j.title, j.customer_name, j.status;

create or replace view report_receivables as
select i.id, i.invoice_number, i.customer_name, i.job_id,
  i.total_cents, i.amount_paid_cents,
  i.total_cents - i.amount_paid_cents as balance_cents,
  i.due_on, i.status
from invoices i
where i.archived_at is null and i.status in ('sent','overdue')
  and i.total_cents > i.amount_paid_cents
order by i.due_on;

create or replace view report_supplier_spend as
select s.name as supplier, t.fiscal_year, t.fiscal_quarter,
  sum(t.amount_cents) as spend_cents, sum(t.tax_cents) as tax_cents
from transactions t join suppliers s on s.id = t.supplier_id
where t.archived_at is null and t.direction='expense'
group by s.name, t.fiscal_year, t.fiscal_quarter
order by s.name, t.fiscal_year, t.fiscal_quarter;

-- ════════════════════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY — single-owner full access
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare t text;
begin
  foreach t in array array[
    'customers','leads','jobs','quotes','purchase_orders','transactions',
    'invoices','payments','documents','communications','suppliers','products',
    'price_history','rates','settings','counters',
    'checklist_templates','checklist_template_steps','job_checklist_items',
    'reminders','sop_library','approvals','workflow_runs'
  ]
  loop
    execute format('alter table %I enable row level security;', t);
    execute format('drop policy if exists owner_all on %I;', t);
    execute format('create policy owner_all on %I for all to authenticated
      using (true) with check (true);', t);
  end loop;
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- SEED — your Process sheet as the default checklist template
-- (Each new job can copy these steps into job_checklist_items.)
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare tpl uuid;
begin
  -- only seed once
  if not exists (select 1 from checklist_templates where name = 'Standard Job Process') then
    insert into checklist_templates (name, description)
      values ('Standard Job Process', 'Default flooring job workflow from contact to paid')
      returning id into tpl;

    insert into checklist_template_steps (template_id, phase, step_order, label, detail) values
      (tpl,'Contact',   1, 'Contact info captured',        'Name, address, phone, email'),
      (tpl,'Contact',   2, 'Customer folder created',      'Logged to Cx Database'),
      (tpl,'Measure',   3, 'Site measured',                'Record room dimensions'),
      (tpl,'Measure',   4, 'Samples provided',             ''),
      (tpl,'Measure',   5, 'Shipping rate quote logged',   'Log in Cx file'),
      (tpl,'Quote',     6, 'Quote sent',                   'Print to invoice folder / copy to admin / create dashboard'),
      (tpl,'Quote',     7, 'Contract docs sent',           ''),
      (tpl,'Quote',     8, 'Deposit received',             ''),
      (tpl,'Jobs',      9, 'Deposit invoice generated',    'Print to invoice folder / log income / QB Income+tax / bank'),
      (tpl,'Jobs',     10, 'Material ordered',             'Print material expense / copy to admin / log expense'),
      (tpl,'Jobs',     11, 'Supplies ordered',             'Print material expense / copy to admin / log expense'),
      (tpl,'Jobs',     12, 'BOL received',                 'Print to shipping expense / copy to admin'),
      (tpl,'Jobs',     13, 'Shipping payment receipt',     'Scan to shipping expense / log expense'),
      (tpl,'Jobs',     14, 'Delivery scheduled',           ''),
      (tpl,'Jobs',     15, 'Work order / job prep',        'Tools, supplies, labour, fuel'),
      (tpl,'Invoicing',16, 'Job completion / sign-off',    'Scan to docs folder'),
      (tpl,'Invoicing',17, 'Balance invoice sent',         ''),
      (tpl,'Invoicing',18, 'Invoice PAID',                 'QB Income+tax / bank'),
      (tpl,'Invoicing',19, 'Final job report / dashboard', '');
  end if;
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- DONE. 23 tables, 6 report views, auto-numbering, auto-fiscal-dating.
-- Pillars: Transactional · Documents · Communications · Admin Infrastructure.
-- ════════════════════════════════════════════════════════════════════════════
