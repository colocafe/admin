-- Colo Cafe - open orders realtime incremental patch
-- Run in Supabase SQL Editor only if Realtime does not fire or line_total is missing.

ALTER TABLE public.open_order_items
  ADD COLUMN IF NOT EXISTS line_total numeric(12,2) DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_open_orders_store_status
  ON public.open_orders(store_id, status);

CREATE INDEX IF NOT EXISTS idx_open_order_items_store_order
  ON public.open_order_items(store_id, open_order_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'open_orders'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.open_orders;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'open_order_items'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.open_order_items;
  END IF;
END $$;
