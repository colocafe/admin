-- Colo Cafe - reconcile paid open orders
-- Idempotente. Ejecutar completo en Supabase SQL Editor.
-- Objetivo: si una venta referencia open_order_id, esa mesa no debe seguir activa.

begin;

create or replace function public.close_open_order_after_sale()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.open_order_id is not null then
    update public.open_orders
    set
      status = 'closed',
      metadata = coalesce(metadata, '{}'::jsonb)
        || jsonb_build_object(
          'status', 'closed',
          'closed_at', coalesce(new.sold_at, now()),
          'close_reason', 'paid',
          'closed_by_sale_id', new.id,
          'closed_by_sale_legacy_id', new.legacy_id
        )
    where id = new.open_order_id
      and store_id = new.store_id
      and status::text = 'open';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_close_open_order_after_sale on public.sales;
create trigger trg_close_open_order_after_sale
after insert or update of open_order_id on public.sales
for each row
when (new.open_order_id is not null)
execute function public.close_open_order_after_sale();

with sold_open_orders as (
  select distinct on (s.store_id, s.open_order_id)
    s.store_id,
    s.open_order_id,
    s.id,
    s.legacy_id,
    s.sold_at
  from public.sales s
  where s.open_order_id is not null
  order by s.store_id, s.open_order_id, s.sold_at desc nulls last, s.id desc
)
update public.open_orders o
set
  status = 'closed',
  metadata = coalesce(o.metadata, '{}'::jsonb)
    || jsonb_build_object(
      'status', 'closed',
      'closed_at', coalesce(s.sold_at, now()),
      'close_reason', 'paid_reconciliation',
      'closed_by_sale_id', s.id,
      'closed_by_sale_legacy_id', s.legacy_id
    )
from sold_open_orders s
where o.store_id = s.store_id
  and o.id = s.open_order_id
  and o.status::text = 'open';

notify pgrst, 'reload schema';

commit;
