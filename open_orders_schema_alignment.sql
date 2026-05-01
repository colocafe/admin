-- Alineación incremental e idempotente para Caja / mesas abiertas.
-- Ejecutar en Supabase SQL Editor. No borra datos.

begin;

-- =========================
-- public.open_orders
-- =========================
alter table public.open_orders
  add column if not exists label text,
  add column if not exists table_label text,
  add column if not exists business_date date,
  add column if not exists opened_at timestamptz,
  add column if not exists status text default 'open',
  add column if not exists service_type text default 'salon',
  add column if not exists shift_id uuid,
  add column if not exists operator_name text,
  add column if not exists metadata jsonb default '{}'::jsonb,
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();

update public.open_orders
set
  label = coalesce(nullif(label,''), nullif(table_label,''), nullif(metadata->>'label',''), nullif(metadata->>'table_label',''), 'Mesa'),
  table_label = coalesce(nullif(table_label,''), nullif(label,''), nullif(metadata->>'table_label',''), nullif(metadata->>'label',''), 'Mesa'),
  opened_at = coalesce(opened_at, created_at, now()),
  business_date = coalesce(business_date, (coalesce(opened_at, created_at, now()) at time zone 'America/Argentina/Buenos_Aires')::date),
  status = coalesce(nullif(status,''), 'open'),
  service_type = coalesce(nullif(service_type,''), metadata->>'service_type', 'salon'),
  metadata = coalesce(metadata, '{}'::jsonb);

alter table public.open_orders
  alter column label set default 'Mesa',
  alter column label set not null,
  alter column table_label set default 'Mesa',
  alter column business_date set default ((now() at time zone 'America/Argentina/Buenos_Aires')::date),
  alter column business_date set not null,
  alter column opened_at set default now(),
  alter column opened_at set not null,
  alter column status set default 'open',
  alter column service_type set default 'salon',
  alter column metadata set default '{}'::jsonb;

create or replace function public.sync_open_order_labels()
returns trigger
language plpgsql
as $$
begin
  new.label := coalesce(nullif(new.label,''), nullif(new.table_label,''), nullif(new.metadata->>'label',''), nullif(new.metadata->>'table_label',''), 'Mesa');
  new.table_label := coalesce(nullif(new.table_label,''), nullif(new.label,''), 'Mesa');
  new.metadata := coalesce(new.metadata, '{}'::jsonb)
    || jsonb_build_object('label', new.label, 'table_label', new.table_label);
  new.opened_at := coalesce(new.opened_at, now());
  new.business_date := coalesce(new.business_date, (new.opened_at at time zone 'America/Argentina/Buenos_Aires')::date);
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_sync_open_order_labels on public.open_orders;
create trigger trg_sync_open_order_labels
before insert or update on public.open_orders
for each row execute function public.sync_open_order_labels();

create index if not exists idx_open_orders_store_status
  on public.open_orders(store_id, status);

create index if not exists idx_open_orders_store_business_date
  on public.open_orders(store_id, business_date);

-- =========================
-- public.open_order_items
-- =========================
alter table public.open_order_items
  add column if not exists store_id uuid,
  add column if not exists open_order_id uuid,
  add column if not exists product_id uuid,
  add column if not exists product_legacy_id text,
  add column if not exists product_name text,
  add column if not exists quantity numeric default 1,
  add column if not exists unit_price numeric default 0,
  add column if not exists line_total numeric default 0,
  add column if not exists variants jsonb default '[]'::jsonb,
  add column if not exists note text,
  add column if not exists sort_order integer default 0,
  add column if not exists metadata jsonb default '{}'::jsonb,
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();

update public.open_order_items
set
  quantity = coalesce(quantity, 1),
  unit_price = coalesce(unit_price, 0),
  line_total = coalesce(line_total, coalesce(quantity,1) * coalesce(unit_price,0), 0),
  variants = coalesce(variants, '[]'::jsonb),
  metadata = coalesce(metadata, '{}'::jsonb),
  product_legacy_id = coalesce(nullif(product_legacy_id,''), nullif(metadata->>'product_legacy_id',''), nullif(metadata->>'prodId',''));

alter table public.open_order_items
  alter column quantity set default 1,
  alter column quantity set not null,
  alter column unit_price set default 0,
  alter column unit_price set not null,
  alter column line_total set default 0,
  alter column line_total set not null,
  alter column variants set default '[]'::jsonb,
  alter column metadata set default '{}'::jsonb;

create or replace function public.sync_open_order_item_totals()
returns trigger
language plpgsql
as $$
begin
  new.quantity := coalesce(new.quantity, 1);
  new.unit_price := coalesce(new.unit_price, 0);
  new.line_total := coalesce(new.line_total, new.quantity * new.unit_price, 0);
  new.variants := coalesce(new.variants, '[]'::jsonb);
  new.metadata := coalesce(new.metadata, '{}'::jsonb)
    || jsonb_build_object('line_total', new.line_total, 'product_legacy_id', new.product_legacy_id);
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_sync_open_order_item_totals on public.open_order_items;
create trigger trg_sync_open_order_item_totals
before insert or update on public.open_order_items
for each row execute function public.sync_open_order_item_totals();

create index if not exists idx_open_order_items_store_order
  on public.open_order_items(store_id, open_order_id);

create index if not exists idx_open_order_items_order
  on public.open_order_items(open_order_id);

-- =========================
-- RLS policies usando patrón real del proyecto.
-- Ajustar roles si tu operación requiere permitir otros roles.
-- =========================
alter table public.open_orders enable row level security;
alter table public.open_order_items enable row level security;

drop policy if exists open_orders_select_members on public.open_orders;
create policy open_orders_select_members on public.open_orders
for select using (
  public.has_store_role(store_id, array['owner','admin','operator']::public.store_user_role[])
);

drop policy if exists open_orders_insert_ops on public.open_orders;
create policy open_orders_insert_ops on public.open_orders
for insert with check (
  public.has_store_role(store_id, array['owner','admin','operator']::public.store_user_role[])
);

drop policy if exists open_orders_update_ops on public.open_orders;
create policy open_orders_update_ops on public.open_orders
for update using (
  public.has_store_role(store_id, array['owner','admin','operator']::public.store_user_role[])
) with check (
  public.has_store_role(store_id, array['owner','admin','operator']::public.store_user_role[])
);

drop policy if exists open_orders_delete_ops on public.open_orders;
create policy open_orders_delete_ops on public.open_orders
for delete using (
  public.has_store_role(store_id, array['owner','admin','operator']::public.store_user_role[])
);

drop policy if exists open_order_items_select_members on public.open_order_items;
create policy open_order_items_select_members on public.open_order_items
for select using (
  public.has_store_role(store_id, array['owner','admin','operator']::public.store_user_role[])
);

drop policy if exists open_order_items_insert_ops on public.open_order_items;
create policy open_order_items_insert_ops on public.open_order_items
for insert with check (
  public.has_store_role(store_id, array['owner','admin','operator']::public.store_user_role[])
);

drop policy if exists open_order_items_update_ops on public.open_order_items;
create policy open_order_items_update_ops on public.open_order_items
for update using (
  public.has_store_role(store_id, array['owner','admin','operator']::public.store_user_role[])
) with check (
  public.has_store_role(store_id, array['owner','admin','operator']::public.store_user_role[])
);

drop policy if exists open_order_items_delete_ops on public.open_order_items;
create policy open_order_items_delete_ops on public.open_order_items
for delete using (
  public.has_store_role(store_id, array['owner','admin','operator']::public.store_user_role[])
);

commit;
