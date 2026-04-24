begin;

create extension if not exists pgcrypto;
create extension if not exists citext;

-- ============================================================================
-- ENUMS
-- ============================================================================

create type public.store_user_role as enum ('owner', 'admin', 'operator');
create type public.product_section as enum ('cafeteria', 'cocina');
create type public.service_type as enum ('salon', 'delivery', 'takeaway');
create type public.shift_status as enum ('open', 'closed');
create type public.sale_payment_mode as enum ('single', 'mixed');
create type public.payment_method as enum ('efectivo', 'mercado_pago', 'transferencia', 'otro');
create type public.open_order_status as enum ('open', 'closed', 'cancelled');

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============================================================================
-- TABLES
-- ============================================================================

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  legacy_id text,
  email citext,
  full_name text,
  display_name text,
  phone text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'Perfil base por usuario autenticado; reemplaza a futuro parte de Operadores.';

create table public.stores (
  id uuid primary key default gen_random_uuid(),
  legacy_id text,
  name text not null,
  slug citext unique,
  timezone text not null default 'America/Argentina/Buenos_Aires',
  currency_code text not null default 'ARS',
  active boolean not null default true,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stores_currency_code_check check (char_length(currency_code) = 3)
);

comment on table public.stores is 'Sucursal/local lógico. Todas las tablas operativas cuelgan de store_id.';

create table public.store_users (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.store_user_role not null default 'operator',
  active boolean not null default true,
  invited_at timestamptz not null default now(),
  joined_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint store_users_store_user_unique unique (store_id, user_id)
);

comment on table public.store_users is 'Relación entre usuarios y stores con rol owner/admin/operator.';

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  legacy_id text,
  name text not null,
  color text,
  section public.product_section not null default 'cafeteria',
  reservable boolean not null default false,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint categories_store_name_unique unique (store_id, name)
);

comment on table public.categories is 'Categorías del menú; mapea la hoja Menu/Categorias del frontend.';

create table public.products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  legacy_id text,
  category_id uuid references public.categories (id) on delete set null,
  name text not null,
  category_name_legacy text,
  section public.product_section not null default 'cafeteria',
  price numeric(12,2) not null default 0,
  stock numeric(12,3) not null default 0,
  unlimited boolean not null default false,
  active boolean not null default true,
  variants jsonb not null default '[]'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint products_price_check check (price >= 0),
  constraint products_stock_check check (stock >= 0)
);

comment on table public.products is 'Productos del menú; reemplaza Menu con soporte para legacy_id, stock, active y variantes.';

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  legacy_id text,
  full_name text not null,
  phone text,
  email citext,
  allergies text,
  preferences text,
  notes text,
  first_visit_date date,
  total_visits integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint customers_total_visits_check check (total_visits >= 0)
);

comment on table public.customers is 'Clientes; reemplaza la hoja Clientes y conserva campos legacy de contacto/preferencias.';

create table public.reservations (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  legacy_id text,
  customer_id uuid references public.customers (id) on delete set null,
  legacy_customer_id text,
  customer_name text,
  service_type public.service_type,
  reservation_date date,
  reservation_at timestamptz,
  status text not null default 'pending',
  products_text text,
  total_amount numeric(12,2),
  payment_mode public.sale_payment_mode not null default 'single',
  payment_method public.payment_method,
  notes text,
  legacy_raw jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint reservations_total_amount_check check (total_amount is null or total_amount >= 0)
);

comment on table public.reservations is 'Reservas. Mantiene tipado principal y también campos legacy text/json para migraciones desde Sheets.';

create table public.shifts (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  legacy_id text,
  status public.shift_status not null default 'open',
  business_date date not null,
  opened_at timestamptz not null,
  closed_at timestamptz,
  opened_by_user_id uuid references auth.users (id) on delete set null,
  opened_by_name text,
  closed_by_user_id uuid references auth.users (id) on delete set null,
  closed_by_name text,
  opening_cash numeric(12,2) not null default 0,
  total_cash numeric(12,2) not null default 0,
  total_mercado_pago numeric(12,2) not null default 0,
  total_transferencia numeric(12,2) not null default 0,
  total_other numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  total_cafeteria numeric(12,2) not null default 0,
  total_cocina numeric(12,2) not null default 0,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shifts_opening_cash_check check (opening_cash >= 0),
  constraint shifts_closed_after_opened check (closed_at is null or closed_at >= opened_at)
);

comment on table public.shifts is 'Turnos abiertos/cerrados. Reemplaza Turnos y TurnoActivo con soporte para estado y totales por medio.';
comment on column public.shifts.business_date is 'Fecha operativa local. Debe venir calculada por la app en zona horaria del store, no desde UTC directo.';

create table public.open_orders (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  legacy_id text,
  shift_id uuid references public.shifts (id) on delete set null,
  customer_id uuid references public.customers (id) on delete set null,
  reservation_id uuid references public.reservations (id) on delete set null,
  label text not null,
  service_type public.service_type not null default 'salon',
  status public.open_order_status not null default 'open',
  business_date date not null,
  opened_at timestamptz not null,
  closed_at timestamptz,
  opened_by_user_id uuid references auth.users (id) on delete set null,
  opened_by_name text,
  selected_payment_mode public.sale_payment_mode not null default 'single',
  selected_payment_method public.payment_method not null default 'efectivo',
  selected_payments jsonb not null default '[]'::jsonb,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint open_orders_closed_after_opened check (closed_at is null or closed_at >= opened_at)
);

comment on table public.open_orders is 'Pedidos abiertos/mesas activas a futuro. Reemplaza MesasActivas con soporte para draft de pago simple o mixto.';
comment on column public.open_orders.business_date is 'Fecha operativa local. No derivar desde UTC en SQL.';

create table public.open_order_items (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  open_order_id uuid not null references public.open_orders (id) on delete cascade,
  legacy_id text,
  product_id uuid references public.products (id) on delete set null,
  product_name text not null,
  variant_summary text,
  note text,
  quantity numeric(12,3) not null default 1,
  unit_price numeric(12,2) not null default 0,
  variants_price numeric(12,2) not null default 0,
  line_total numeric(12,2) not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint open_order_items_quantity_check check (quantity > 0),
  constraint open_order_items_unit_price_check check (unit_price >= 0),
  constraint open_order_items_variants_price_check check (variants_price >= 0),
  constraint open_order_items_line_total_check check (line_total >= 0)
);

comment on table public.open_order_items is 'Ítems del pedido abierto; reemplaza items serializados dentro de MesasActivas.';

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  legacy_id text,
  legacy_source text,
  shift_id uuid references public.shifts (id) on delete set null,
  customer_id uuid references public.customers (id) on delete set null,
  reservation_id uuid references public.reservations (id) on delete set null,
  open_order_id uuid references public.open_orders (id) on delete set null,
  business_date date not null,
  sold_at timestamptz not null,
  operator_user_id uuid references auth.users (id) on delete set null,
  operator_name text,
  service_type public.service_type not null default 'salon',
  table_label text,
  payment_mode public.sale_payment_mode not null default 'single',
  subtotal_amount numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sales_subtotal_amount_check check (subtotal_amount >= 0),
  constraint sales_total_amount_check check (total_amount >= 0)
);

comment on table public.sales is 'Cabecera de venta/ticket. business_date es local; sold_at es timestamptz técnico.';
comment on column public.sales.business_date is 'Fecha operativa local enviada por la app. No recalcular desde UTC en la DB.';

create table public.sale_items (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  sale_id uuid not null references public.sales (id) on delete cascade,
  legacy_id text,
  product_id uuid references public.products (id) on delete set null,
  product_name text not null,
  category_name text,
  section public.product_section,
  variant_summary text,
  note text,
  quantity numeric(12,3) not null default 1,
  unit_price numeric(12,2) not null default 0,
  variants_price numeric(12,2) not null default 0,
  line_total numeric(12,2) not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sale_items_quantity_check check (quantity > 0),
  constraint sale_items_unit_price_check check (unit_price >= 0),
  constraint sale_items_variants_price_check check (variants_price >= 0),
  constraint sale_items_line_total_check check (line_total >= 0)
);

comment on table public.sale_items is 'Detalle de productos vendidos. Reemplaza las filas itemizadas de la hoja Ventas.';

create table public.sale_payments (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  sale_id uuid not null references public.sales (id) on delete cascade,
  method public.payment_method not null,
  amount numeric(12,2) not null,
  business_date date not null,
  paid_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sale_payments_amount_check check (amount > 0)
);

comment on table public.sale_payments is 'Pagos de una venta. Soporta simple o mixto mediante una o más filas por sale_id.';
comment on column public.sale_payments.business_date is 'Fecha operativa local del cobro, enviada por la app.';

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  legacy_id text,
  legacy_source text,
  business_date date not null,
  spent_at timestamptz not null,
  description text not null,
  amount numeric(12,2) not null,
  payment_method public.payment_method not null default 'efectivo',
  operator_user_id uuid references auth.users (id) on delete set null,
  operator_name text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint expenses_amount_check check (amount > 0)
);

comment on table public.expenses is 'Gastos operativos con fecha local de negocio y medio de pago.';
comment on column public.expenses.business_date is 'Fecha operativa local del gasto. No derivar desde UTC dentro de SQL.';

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores (id) on delete cascade,
  actor_user_id uuid references auth.users (id) on delete set null,
  actor_name text,
  entity_type text not null,
  entity_id uuid,
  action text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

comment on table public.audit_logs is 'Bitácora opcional de acciones críticas por store.';

-- ============================================================================
-- POST-TABLE FUNCTIONS
-- ============================================================================

create or replace function public.handle_auth_user_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (
    id,
    email,
    full_name,
    display_name
  )
  values (
    new.id,
    new.email,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      split_part(coalesce(new.email, ''), '@', 1)
    ),
    coalesce(
      new.raw_user_meta_data ->> 'display_name',
      new.raw_user_meta_data ->> 'name',
      split_part(coalesce(new.email, ''), '@', 1)
    )
  )
  on conflict (id) do update
    set email = excluded.email,
        updated_at = now();

  return new;
end;
$$;

create or replace function public.handle_store_created_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.created_by is not null then
    insert into public.store_users (
      store_id,
      user_id,
      role,
      active,
      invited_at,
      joined_at
    )
    values (
      new.id,
      new.created_by,
      'owner',
      true,
      now(),
      now()
    )
    on conflict (store_id, user_id) do nothing;
  end if;

  return new;
end;
$$;

create or replace function public.is_store_member(p_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.store_users su
    where su.store_id = p_store_id
      and su.user_id = auth.uid()
      and su.active = true
  );
$$;

create or replace function public.has_store_role(
  p_store_id uuid,
  p_roles public.store_user_role[]
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.store_users su
    where su.store_id = p_store_id
      and su.user_id = auth.uid()
      and su.active = true
      and su.role = any(p_roles)
  );
$$;

create or replace function public.shares_store_with_user(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.store_users mine
    join public.store_users theirs
      on theirs.store_id = mine.store_id
    where mine.user_id = auth.uid()
      and mine.active = true
      and theirs.user_id = p_user_id
      and theirs.active = true
  );
$$;

-- ============================================================================
-- INDEXES
-- ============================================================================

create index profiles_email_idx on public.profiles (email);

create index store_users_user_idx on public.store_users (user_id);
create index store_users_store_role_idx on public.store_users (store_id, role) where active = true;

create index categories_store_active_idx on public.categories (store_id, active, section);
create index products_store_active_idx on public.products (store_id, active, section);
create index products_category_idx on public.products (category_id);

create index customers_store_name_idx on public.customers (store_id, full_name);
create index customers_store_phone_idx on public.customers (store_id, phone);

create index reservations_store_date_idx on public.reservations (store_id, reservation_date);
create index reservations_store_status_idx on public.reservations (store_id, status);

create index shifts_store_business_date_idx on public.shifts (store_id, business_date desc);
create unique index shifts_one_open_per_store_idx
  on public.shifts (store_id)
  where status = 'open';

create index open_orders_store_status_date_idx on public.open_orders (store_id, status, business_date desc);
create index open_orders_shift_idx on public.open_orders (shift_id);
create index open_order_items_order_idx on public.open_order_items (open_order_id);

create index sales_store_business_date_idx on public.sales (store_id, business_date desc);
create index sales_store_sold_at_idx on public.sales (store_id, sold_at desc);
create index sales_shift_idx on public.sales (shift_id);
create index sales_customer_idx on public.sales (customer_id);
create index sale_items_sale_idx on public.sale_items (sale_id);
create index sale_payments_sale_idx on public.sale_payments (sale_id);
create index sale_payments_store_business_date_idx on public.sale_payments (store_id, business_date desc);

create index expenses_store_business_date_idx on public.expenses (store_id, business_date desc);
create index expenses_store_spent_at_idx on public.expenses (store_id, spent_at desc);

create index audit_logs_store_created_at_idx on public.audit_logs (store_id, created_at desc);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger stores_set_updated_at
before update on public.stores
for each row execute function public.set_updated_at();

create trigger store_users_set_updated_at
before update on public.store_users
for each row execute function public.set_updated_at();

create trigger categories_set_updated_at
before update on public.categories
for each row execute function public.set_updated_at();

create trigger products_set_updated_at
before update on public.products
for each row execute function public.set_updated_at();

create trigger customers_set_updated_at
before update on public.customers
for each row execute function public.set_updated_at();

create trigger reservations_set_updated_at
before update on public.reservations
for each row execute function public.set_updated_at();

create trigger shifts_set_updated_at
before update on public.shifts
for each row execute function public.set_updated_at();

create trigger open_orders_set_updated_at
before update on public.open_orders
for each row execute function public.set_updated_at();

create trigger open_order_items_set_updated_at
before update on public.open_order_items
for each row execute function public.set_updated_at();

create trigger sales_set_updated_at
before update on public.sales
for each row execute function public.set_updated_at();

create trigger sale_items_set_updated_at
before update on public.sale_items
for each row execute function public.set_updated_at();

create trigger sale_payments_set_updated_at
before update on public.sale_payments
for each row execute function public.set_updated_at();

create trigger expenses_set_updated_at
before update on public.expenses
for each row execute function public.set_updated_at();

create trigger auth_users_profile_sync_insert
after insert on auth.users
for each row execute function public.handle_auth_user_change();

create trigger auth_users_profile_sync_update
after update on auth.users
for each row execute function public.handle_auth_user_change();

create trigger stores_create_owner_membership
after insert on public.stores
for each row execute function public.handle_store_created_owner();

-- ============================================================================
-- RLS
-- ============================================================================

alter table public.profiles enable row level security;
alter table public.profiles force row level security;

alter table public.stores enable row level security;
alter table public.stores force row level security;

alter table public.store_users enable row level security;
alter table public.store_users force row level security;

alter table public.categories enable row level security;
alter table public.categories force row level security;

alter table public.products enable row level security;
alter table public.products force row level security;

alter table public.customers enable row level security;
alter table public.customers force row level security;

alter table public.reservations enable row level security;
alter table public.reservations force row level security;

alter table public.shifts enable row level security;
alter table public.shifts force row level security;

alter table public.open_orders enable row level security;
alter table public.open_orders force row level security;

alter table public.open_order_items enable row level security;
alter table public.open_order_items force row level security;

alter table public.sales enable row level security;
alter table public.sales force row level security;

alter table public.sale_items enable row level security;
alter table public.sale_items force row level security;

alter table public.sale_payments enable row level security;
alter table public.sale_payments force row level security;

alter table public.expenses enable row level security;
alter table public.expenses force row level security;

alter table public.audit_logs enable row level security;
alter table public.audit_logs force row level security;

-- ============================================================================
-- POLICIES
-- ============================================================================

create policy profiles_select_self_or_store_peers
on public.profiles
for select
to authenticated
using (
  auth.uid() = id
  or public.shares_store_with_user(id)
);

create policy profiles_insert_self
on public.profiles
for insert
to authenticated
with check (auth.uid() = id);

create policy profiles_update_self
on public.profiles
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

create policy stores_select_members
on public.stores
for select
to authenticated
using (public.is_store_member(id));

create policy stores_insert_owner
on public.stores
for insert
to authenticated
with check (created_by = auth.uid());

create policy stores_update_owner
on public.stores
for update
to authenticated
using (public.has_store_role(id, array['owner']::public.store_user_role[]))
with check (public.has_store_role(id, array['owner']::public.store_user_role[]));

create policy stores_delete_owner
on public.stores
for delete
to authenticated
using (public.has_store_role(id, array['owner']::public.store_user_role[]));

create policy store_users_select_members
on public.store_users
for select
to authenticated
using (public.is_store_member(store_id));

create policy store_users_manage_owner
on public.store_users
for insert
to authenticated
with check (public.has_store_role(store_id, array['owner']::public.store_user_role[]));

create policy store_users_update_owner
on public.store_users
for update
to authenticated
using (public.has_store_role(store_id, array['owner']::public.store_user_role[]))
with check (public.has_store_role(store_id, array['owner']::public.store_user_role[]));

create policy store_users_delete_owner
on public.store_users
for delete
to authenticated
using (public.has_store_role(store_id, array['owner']::public.store_user_role[]));

create policy categories_select_members
on public.categories
for select
to authenticated
using (public.is_store_member(store_id));

create policy categories_insert_admin
on public.categories
for insert
to authenticated
with check (public.has_store_role(store_id, array['owner', 'admin']::public.store_user_role[]));

create policy categories_update_admin
on public.categories
for update
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin']::public.store_user_role[]))
with check (public.has_store_role(store_id, array['owner', 'admin']::public.store_user_role[]));

create policy categories_delete_admin
on public.categories
for delete
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin']::public.store_user_role[]));

create policy products_select_members
on public.products
for select
to authenticated
using (public.is_store_member(store_id));

create policy products_insert_admin
on public.products
for insert
to authenticated
with check (public.has_store_role(store_id, array['owner', 'admin']::public.store_user_role[]));

create policy products_update_admin
on public.products
for update
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin']::public.store_user_role[]))
with check (public.has_store_role(store_id, array['owner', 'admin']::public.store_user_role[]));

create policy products_delete_admin
on public.products
for delete
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin']::public.store_user_role[]));

create policy customers_select_members
on public.customers
for select
to authenticated
using (public.is_store_member(store_id));

create policy customers_insert_ops
on public.customers
for insert
to authenticated
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy customers_update_ops
on public.customers
for update
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]))
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy customers_delete_admin
on public.customers
for delete
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin']::public.store_user_role[]));

create policy reservations_select_members
on public.reservations
for select
to authenticated
using (public.is_store_member(store_id));

create policy reservations_insert_ops
on public.reservations
for insert
to authenticated
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy reservations_update_ops
on public.reservations
for update
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]))
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy reservations_delete_ops
on public.reservations
for delete
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy shifts_select_members
on public.shifts
for select
to authenticated
using (public.is_store_member(store_id));

create policy shifts_insert_ops
on public.shifts
for insert
to authenticated
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy shifts_update_ops
on public.shifts
for update
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]))
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy shifts_delete_admin
on public.shifts
for delete
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin']::public.store_user_role[]));

create policy open_orders_select_members
on public.open_orders
for select
to authenticated
using (public.is_store_member(store_id));

create policy open_orders_insert_ops
on public.open_orders
for insert
to authenticated
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy open_orders_update_ops
on public.open_orders
for update
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]))
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy open_orders_delete_ops
on public.open_orders
for delete
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy open_order_items_select_members
on public.open_order_items
for select
to authenticated
using (public.is_store_member(store_id));

create policy open_order_items_insert_ops
on public.open_order_items
for insert
to authenticated
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy open_order_items_update_ops
on public.open_order_items
for update
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]))
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy open_order_items_delete_ops
on public.open_order_items
for delete
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy sales_select_members
on public.sales
for select
to authenticated
using (public.is_store_member(store_id));

create policy sales_insert_ops
on public.sales
for insert
to authenticated
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy sales_update_ops
on public.sales
for update
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]))
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy sales_delete_admin
on public.sales
for delete
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin']::public.store_user_role[]));

create policy sale_items_select_members
on public.sale_items
for select
to authenticated
using (public.is_store_member(store_id));

create policy sale_items_insert_ops
on public.sale_items
for insert
to authenticated
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy sale_items_update_ops
on public.sale_items
for update
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]))
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy sale_items_delete_admin
on public.sale_items
for delete
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin']::public.store_user_role[]));

create policy sale_payments_select_members
on public.sale_payments
for select
to authenticated
using (public.is_store_member(store_id));

create policy sale_payments_insert_ops
on public.sale_payments
for insert
to authenticated
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy sale_payments_update_ops
on public.sale_payments
for update
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]))
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy sale_payments_delete_admin
on public.sale_payments
for delete
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin']::public.store_user_role[]));

create policy expenses_select_members
on public.expenses
for select
to authenticated
using (public.is_store_member(store_id));

create policy expenses_insert_ops
on public.expenses
for insert
to authenticated
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy expenses_update_ops
on public.expenses
for update
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]))
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

create policy expenses_delete_admin
on public.expenses
for delete
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin']::public.store_user_role[]));

create policy audit_logs_select_admin
on public.audit_logs
for select
to authenticated
using (public.has_store_role(store_id, array['owner', 'admin']::public.store_user_role[]));

create policy audit_logs_insert_ops
on public.audit_logs
for insert
to authenticated
with check (public.has_store_role(store_id, array['owner', 'admin', 'operator']::public.store_user_role[]));

commit;
