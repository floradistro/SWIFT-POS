-- Migration: Fix legacy functions to use Oracle+Apple schema
-- Updates all RPC functions to use:
--   - channel (online/retail) instead of order_type
--   - fulfillments table instead of pickup_location_id column
--   - Backward compatibility computed order_type from channel+fulfillment type

-- =============================================================================
-- 1. Update get_order_for_printing RPC function
-- =============================================================================
-- Changes:
-- - Remove pickup_location_id column reference
-- - Add fulfillments join to get delivery location

CREATE OR REPLACE FUNCTION get_order_for_printing(
  p_order_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSONB;
BEGIN
  -- Single query that fetches order + full product details + fulfillments
  SELECT jsonb_build_object(
    'order_id', o.id,
    'order_number', o.order_number,
    'store_id', o.store_id,
    'location_id', o.location_id,
    'channel', o.channel,
    -- Backward compat: compute order_type from channel + fulfillment type
    'order_type', CASE
      WHEN o.channel = 'retail' THEN 'walk_in'
      WHEN f.type = 'pickup' THEN 'pickup'
      WHEN f.type = 'ship' THEN 'shipping'
      ELSE 'online'
    END,
    -- Get pickup location from fulfillments
    'pickup_location_id', f.delivery_location_id,
    'pickup_location', CASE
      WHEN fl.id IS NOT NULL THEN
        jsonb_build_object('id', fl.id, 'name', fl.name)
      ELSE NULL
    END,
    -- Fulfillments array
    'fulfillments', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', ff.id,
            'type', ff.type,
            'status', ff.status,
            'delivery_location_id', ff.delivery_location_id,
            'delivery_location', CASE
              WHEN ffl.id IS NOT NULL THEN
                jsonb_build_object('id', ffl.id, 'name', ffl.name)
              ELSE NULL
            END
          )
        )
        FROM fulfillments ff
        LEFT JOIN locations ffl ON ffl.id = ff.delivery_location_id
        WHERE ff.order_id = o.id
      ),
      '[]'::jsonb
    ),
    'created_at', o.created_at,
    'items', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', oi.id,
            'product_id', oi.product_id,
            'quantity', oi.quantity,
            'tier_label', oi.tier_label,
            'variant_name', oi.variant_name,
            -- Full product details
            'product', jsonb_build_object(
              'id', p.id,
              'name', p.name,
              'description', p.description,
              'sku', p.sku,
              'featured_image', p.featured_image,
              'custom_fields', p.custom_fields,
              'pricing_data', p.pricing_data,
              'store_id', p.store_id,
              'primary_category_id', p.primary_category_id,
              'status', p.status,
              -- COA if available
              'coa', CASE
                WHEN coa.id IS NOT NULL THEN
                  jsonb_build_object(
                    'id', coa.id,
                    'file_url', coa.file_url,
                    'lab_name', coa.lab_name,
                    'test_date', coa.test_date,
                    'batch_number', coa.batch_number
                  )
                ELSE NULL
              END
            )
          )
        )
        FROM order_items oi
        LEFT JOIN products p ON p.id = oi.product_id
        LEFT JOIN store_coas coa ON coa.product_id = p.id AND coa.is_active = true
        WHERE oi.order_id = o.id
      ),
      '[]'::jsonb
    )
  ) INTO v_result
  FROM orders o
  -- Join primary fulfillment (first one) for backward compat
  LEFT JOIN LATERAL (
    SELECT * FROM fulfillments
    WHERE order_id = o.id
    ORDER BY created_at ASC
    LIMIT 1
  ) f ON true
  LEFT JOIN locations fl ON fl.id = f.delivery_location_id
  WHERE o.id = p_order_id;

  -- Return null if order not found
  IF v_result IS NULL THEN
    RETURN jsonb_build_object('error', 'Order not found');
  END IF;

  RETURN v_result;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_order_for_printing(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_order_for_printing(UUID) TO service_role;

COMMENT ON FUNCTION get_order_for_printing IS 'Fetch order with complete product details for label printing. Uses Oracle+Apple schema with fulfillments table.';


-- =============================================================================
-- 2. Update get_orders_for_location RPC function
-- =============================================================================
-- Changes:
-- - Use channel instead of order_type
-- - Join fulfillments table
-- - Compute backward-compat order_type

CREATE OR REPLACE FUNCTION get_orders_for_location(
  p_store_id UUID,
  p_location_id UUID,
  p_status_group TEXT DEFAULT NULL,
  p_order_type TEXT DEFAULT NULL,
  p_payment_status TEXT DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
  p_date_start TIMESTAMP DEFAULT NULL,
  p_date_end TIMESTAMP DEFAULT NULL,
  p_amount_min NUMERIC DEFAULT NULL,
  p_amount_max NUMERIC DEFAULT NULL,
  p_online_only BOOLEAN DEFAULT FALSE,
  p_limit INTEGER DEFAULT 200
)
RETURNS TABLE(order_data JSONB)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_status_filters TEXT[];
BEGIN
  -- Map status group to individual statuses
  IF p_status_group IS NOT NULL THEN
    CASE p_status_group
      WHEN 'active' THEN
        v_status_filters := ARRAY['pending', 'processing', 'confirmed'];
      WHEN 'in_progress' THEN
        v_status_filters := ARRAY['ready_for_pickup', 'out_for_delivery', 'in_transit'];
      WHEN 'completed' THEN
        v_status_filters := ARRAY['completed', 'delivered'];
      WHEN 'cancelled' THEN
        v_status_filters := ARRAY['cancelled', 'refunded'];
      ELSE
        v_status_filters := NULL;
    END CASE;
  END IF;

  -- Return orders as JSONB with all joins
  RETURN QUERY
  SELECT
    jsonb_build_object(
      'id', o.id,
      'order_number', o.order_number,
      'store_id', o.store_id,
      'location_id', o.location_id,
      'customer_id', o.customer_id,
      'user_id', o.user_id,
      'status', o.status,
      'channel', o.channel,
      -- Backward compat: compute order_type from channel + fulfillment type
      'order_type', CASE
        WHEN o.channel = 'retail' THEN 'walk_in'
        WHEN f.type = 'pickup' THEN 'pickup'
        WHEN f.type = 'ship' THEN 'shipping'
        WHEN f.type = 'immediate' THEN 'walk_in'
        ELSE 'online'
      END,
      'payment_status', o.payment_status,
      'subtotal', o.subtotal,
      'tax_amount', o.tax_amount,
      'discount_amount', o.discount_amount,
      'total_amount', o.total_amount,
      'notes', o.notes,
      'created_at', o.created_at,
      'updated_at', o.updated_at,
      -- Fulfillments array
      'fulfillments', COALESCE(
        (
          SELECT jsonb_agg(
            jsonb_build_object(
              'id', ff.id,
              'order_id', ff.order_id,
              'type', ff.type,
              'status', ff.status,
              'delivery_location_id', ff.delivery_location_id,
              'delivery_address', ff.delivery_address,
              'carrier', ff.carrier,
              'tracking_number', ff.tracking_number,
              'tracking_url', ff.tracking_url,
              'shipping_cost', ff.shipping_cost,
              'created_at', ff.created_at,
              'shipped_at', ff.shipped_at,
              'delivered_at', ff.delivered_at,
              'delivery_location', CASE
                WHEN ffl.id IS NOT NULL THEN
                  jsonb_build_object('id', ffl.id, 'name', ffl.name)
                ELSE NULL
              END
            )
          )
          FROM fulfillments ff
          LEFT JOIN locations ffl ON ffl.id = ff.delivery_location_id
          WHERE ff.order_id = o.id
        ),
        '[]'::jsonb
      ),
      -- Join customer data
      'customer', CASE
        WHEN c.id IS NOT NULL THEN
          jsonb_build_object(
            'id', c.id,
            'first_name', c.first_name,
            'last_name', c.last_name,
            'email', c.email,
            'phone', c.phone
          )
        ELSE NULL
      END,
      -- Join order items
      'items', COALESCE(
        (
          SELECT jsonb_agg(
            jsonb_build_object(
              'id', oi.id,
              'product_id', oi.product_id,
              'product_name', p.name,
              'quantity', oi.quantity,
              'unit_price', oi.unit_price,
              'total', oi.total,
              'tier_label', oi.tier_label,
              'variant_name', oi.variant_name
            )
          )
          FROM order_items oi
          LEFT JOIN products p ON p.id = oi.product_id
          WHERE oi.order_id = o.id
        ),
        '[]'::jsonb
      ),
      -- Join location data
      'location', CASE
        WHEN l.id IS NOT NULL THEN
          jsonb_build_object(
            'id', l.id,
            'name', l.name,
            'store_id', l.store_id
          )
        ELSE NULL
      END
    ) AS order_data
  FROM orders o
  LEFT JOIN customers c ON c.id = o.customer_id
  LEFT JOIN locations l ON l.id = o.location_id
  -- Join primary fulfillment for order_type computation and filtering
  LEFT JOIN LATERAL (
    SELECT * FROM fulfillments
    WHERE order_id = o.id
    ORDER BY created_at ASC
    LIMIT 1
  ) f ON true
  WHERE o.store_id = p_store_id
    AND o.location_id = p_location_id
    -- Status group filter
    AND (
      p_status_group IS NULL
      OR o.status = ANY(v_status_filters)
    )
    -- Order type filter (translate to channel + fulfillment type)
    AND (
      p_order_type IS NULL
      OR (p_order_type = 'walk_in' AND (o.channel = 'retail' OR f.type = 'immediate'))
      OR (p_order_type = 'pickup' AND o.channel = 'online' AND f.type = 'pickup')
      OR (p_order_type = 'shipping' AND o.channel = 'online' AND f.type = 'ship')
      OR (p_order_type = 'direct' AND o.channel = 'online' AND f.type IS NULL)
    )
    -- Payment status filter
    AND (
      p_payment_status IS NULL
      OR o.payment_status = p_payment_status
    )
    -- Search filter (order number or customer name)
    AND (
      p_search IS NULL
      OR o.order_number ILIKE '%' || p_search || '%'
      OR c.first_name ILIKE '%' || p_search || '%'
      OR c.last_name ILIKE '%' || p_search || '%'
      OR (c.first_name || ' ' || c.last_name) ILIKE '%' || p_search || '%'
    )
    -- Date range filter
    AND (
      p_date_start IS NULL
      OR o.created_at >= p_date_start
    )
    AND (
      p_date_end IS NULL
      OR o.created_at <= p_date_end
    )
    -- Amount range filter
    AND (
      p_amount_min IS NULL
      OR o.total_amount >= p_amount_min
    )
    AND (
      p_amount_max IS NULL
      OR o.total_amount <= p_amount_max
    )
    -- Online only filter (channel = online)
    AND (
      NOT p_online_only
      OR o.channel = 'online'
    )
  ORDER BY o.created_at DESC
  LIMIT p_limit;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_orders_for_location(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMP, TIMESTAMP, NUMERIC, NUMERIC, BOOLEAN, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_orders_for_location(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMP, TIMESTAMP, NUMERIC, NUMERIC, BOOLEAN, INTEGER) TO service_role;

COMMENT ON FUNCTION get_orders_for_location IS 'Fetch orders for a location with advanced filtering. Uses Oracle+Apple schema with channel + fulfillments.';


-- =============================================================================
-- 3. Update get_revenue_by_location (if exists)
-- =============================================================================
-- This function might reference old columns

CREATE OR REPLACE FUNCTION get_revenue_by_location(
  p_store_id UUID,
  p_start_date TIMESTAMP DEFAULT NULL,
  p_end_date TIMESTAMP DEFAULT NULL
)
RETURNS TABLE(
  location_id UUID,
  location_name TEXT,
  total_revenue NUMERIC,
  order_count BIGINT,
  avg_order_value NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    l.id as location_id,
    l.name as location_name,
    COALESCE(SUM(o.total_amount), 0) as total_revenue,
    COUNT(o.id) as order_count,
    COALESCE(AVG(o.total_amount), 0) as avg_order_value
  FROM locations l
  LEFT JOIN orders o ON o.location_id = l.id
    AND o.store_id = p_store_id
    AND o.status NOT IN ('cancelled', 'refunded')
    AND (p_start_date IS NULL OR o.created_at >= p_start_date)
    AND (p_end_date IS NULL OR o.created_at <= p_end_date)
  WHERE l.store_id = p_store_id
  GROUP BY l.id, l.name
  ORDER BY total_revenue DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_revenue_by_location(UUID, TIMESTAMP, TIMESTAMP) TO authenticated;
GRANT EXECUTE ON FUNCTION get_revenue_by_location(UUID, TIMESTAMP, TIMESTAMP) TO service_role;


-- =============================================================================
-- 4. Update any triggers that might reference old columns
-- =============================================================================

-- Check if there's an orders trigger that sets order_type
-- Drop and recreate without the old column references
DROP TRIGGER IF EXISTS set_order_defaults ON orders;
DROP FUNCTION IF EXISTS set_order_defaults();

-- Create new trigger that only sets required defaults
CREATE OR REPLACE FUNCTION set_order_defaults()
RETURNS TRIGGER AS $$
BEGIN
  -- Set channel default if not provided
  IF NEW.channel IS NULL THEN
    NEW.channel := 'online';
  END IF;

  -- Set status default if not provided
  IF NEW.status IS NULL THEN
    NEW.status := 'pending';
  END IF;

  -- Set payment_status default if not provided
  IF NEW.payment_status IS NULL THEN
    NEW.payment_status := 'pending';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_order_defaults
  BEFORE INSERT ON orders
  FOR EACH ROW
  EXECUTE FUNCTION set_order_defaults();


-- =============================================================================
-- 5. Cleanup: Verify columns are dropped (idempotent)
-- =============================================================================

DO $$
BEGIN
  -- These columns should have been dropped in the migration
  -- This is just verification - no-op if already dropped

  -- Check if order_type column exists and drop it
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'orders' AND column_name = 'order_type'
  ) THEN
    ALTER TABLE orders DROP COLUMN order_type;
    RAISE NOTICE 'Dropped order_type column from orders';
  END IF;

  -- Check if delivery_type column exists and drop it
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'orders' AND column_name = 'delivery_type'
  ) THEN
    ALTER TABLE orders DROP COLUMN delivery_type;
    RAISE NOTICE 'Dropped delivery_type column from orders';
  END IF;

  -- Check if pickup_location_id column exists and drop it
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'orders' AND column_name = 'pickup_location_id'
  ) THEN
    ALTER TABLE orders DROP COLUMN pickup_location_id;
    RAISE NOTICE 'Dropped pickup_location_id column from orders';
  END IF;

  -- Check if shipping_carrier column exists and drop it
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'orders' AND column_name = 'shipping_carrier'
  ) THEN
    ALTER TABLE orders DROP COLUMN shipping_carrier;
    RAISE NOTICE 'Dropped shipping_carrier column from orders';
  END IF;

  RAISE NOTICE 'Legacy column cleanup complete';
END $$;


-- =============================================================================
-- Done! Log completion
-- =============================================================================
DO $$
BEGIN
  RAISE NOTICE '===========================================';
  RAISE NOTICE 'Oracle+Apple schema migration complete!';
  RAISE NOTICE 'Updated functions:';
  RAISE NOTICE '  - get_order_for_printing';
  RAISE NOTICE '  - get_orders_for_location';
  RAISE NOTICE '  - get_revenue_by_location';
  RAISE NOTICE '  - set_order_defaults trigger';
  RAISE NOTICE '===========================================';
END $$;
