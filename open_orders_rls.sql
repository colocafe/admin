-- ══════════════════════════════════════════════════════════════════════
-- COLO CAFÉ — RLS Policies para open_orders y open_order_items
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ══════════════════════════════════════════════════════════════════════

-- ── 1. Habilitar RLS (si no está habilitado) ──────────────────────────
ALTER TABLE public.open_orders      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.open_order_items ENABLE ROW LEVEL SECURITY;

-- ── 2. Eliminar políticas viejas si existen ───────────────────────────
DROP POLICY IF EXISTS "open_orders_select"      ON public.open_orders;
DROP POLICY IF EXISTS "open_orders_insert"      ON public.open_orders;
DROP POLICY IF EXISTS "open_orders_update"      ON public.open_orders;
DROP POLICY IF EXISTS "open_orders_delete"      ON public.open_orders;
DROP POLICY IF EXISTS "open_order_items_select" ON public.open_order_items;
DROP POLICY IF EXISTS "open_order_items_insert" ON public.open_order_items;
DROP POLICY IF EXISTS "open_order_items_update" ON public.open_order_items;
DROP POLICY IF EXISTS "open_order_items_delete" ON public.open_order_items;

-- ── 3. Políticas para open_orders ─────────────────────────────────────
-- Un usuario autenticado puede ver las open_orders de los stores a los que pertenece

CREATE POLICY "open_orders_select" ON public.open_orders
  FOR SELECT TO authenticated
  USING (
    store_id IN (
      SELECT store_id FROM public.store_users
      WHERE user_id = auth.uid()
        AND active = true
    )
  );

CREATE POLICY "open_orders_insert" ON public.open_orders
  FOR INSERT TO authenticated
  WITH CHECK (
    store_id IN (
      SELECT store_id FROM public.store_users
      WHERE user_id = auth.uid()
        AND active = true
    )
  );

CREATE POLICY "open_orders_update" ON public.open_orders
  FOR UPDATE TO authenticated
  USING (
    store_id IN (
      SELECT store_id FROM public.store_users
      WHERE user_id = auth.uid()
        AND active = true
    )
  );

CREATE POLICY "open_orders_delete" ON public.open_orders
  FOR DELETE TO authenticated
  USING (
    store_id IN (
      SELECT store_id FROM public.store_users
      WHERE user_id = auth.uid()
        AND active = true
    )
  );

-- ── 4. Políticas para open_order_items ────────────────────────────────

CREATE POLICY "open_order_items_select" ON public.open_order_items
  FOR SELECT TO authenticated
  USING (
    store_id IN (
      SELECT store_id FROM public.store_users
      WHERE user_id = auth.uid()
        AND active = true
    )
  );

CREATE POLICY "open_order_items_insert" ON public.open_order_items
  FOR INSERT TO authenticated
  WITH CHECK (
    store_id IN (
      SELECT store_id FROM public.store_users
      WHERE user_id = auth.uid()
        AND active = true
    )
  );

CREATE POLICY "open_order_items_update" ON public.open_order_items
  FOR UPDATE TO authenticated
  USING (
    store_id IN (
      SELECT store_id FROM public.store_users
      WHERE user_id = auth.uid()
        AND active = true
    )
  );

CREATE POLICY "open_order_items_delete" ON public.open_order_items
  FOR DELETE TO authenticated
  USING (
    store_id IN (
      SELECT store_id FROM public.store_users
      WHERE user_id = auth.uid()
        AND active = true
    )
  );

-- ── 5. Columnas mínimas requeridas (verificar que existan) ────────────
-- Si alguna no existe, ejecutar el ALTER TABLE correspondiente.

-- Para open_orders:
--   id           UUID PRIMARY KEY DEFAULT gen_random_uuid()
--   store_id     UUID NOT NULL REFERENCES stores(id)
--   status       TEXT NOT NULL DEFAULT 'open'   -- valores: 'open', 'closed'
--   service_type TEXT                           -- 'salon' | 'delivery' | 'takeaway'
--   table_label  TEXT                           -- nombre visible de la mesa
--   shift_id     UUID REFERENCES shifts(id)
--   operator_name TEXT
--   operator_id  UUID
--   metadata     JSONB DEFAULT '{}'             -- datos extra del frontend
--   created_at   TIMESTAMPTZ DEFAULT NOW()

-- Para open_order_items:
--   id                UUID PRIMARY KEY DEFAULT gen_random_uuid()
--   store_id          UUID NOT NULL REFERENCES stores(id)
--   open_order_id     UUID NOT NULL REFERENCES open_orders(id) ON DELETE CASCADE
--   product_id        UUID REFERENCES products(id)
--   product_legacy_id TEXT
--   product_name      TEXT
--   quantity          INTEGER DEFAULT 1
--   unit_price        NUMERIC(12,2) DEFAULT 0
--   variants          JSONB DEFAULT '[]'
--   note              TEXT DEFAULT ''
--   sort_order        INTEGER DEFAULT 0
--   metadata          JSONB DEFAULT '{}'
--   created_at        TIMESTAMPTZ DEFAULT NOW()

-- Si las tablas no tienen la columna `status`, agregarla:
-- ALTER TABLE public.open_orders ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'open';

-- Si la columna metadata no existe:
-- ALTER TABLE public.open_orders      ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}';
-- ALTER TABLE public.open_order_items ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}';

-- ── 6. Índices recomendados para performance ──────────────────────────
CREATE INDEX IF NOT EXISTS idx_open_orders_store_status
  ON public.open_orders(store_id, status);

CREATE INDEX IF NOT EXISTS idx_open_order_items_order
  ON public.open_order_items(open_order_id);

CREATE INDEX IF NOT EXISTS idx_open_order_items_store
  ON public.open_order_items(store_id);
