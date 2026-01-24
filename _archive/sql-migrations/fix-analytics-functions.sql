-- Fix analytics functions that reference orders.pickup_location_id
-- These functions now need to use fulfillments or order_items for location tracking

-- =============================================================================
-- 1. get_top_products - fix to use fulfillments.delivery_location_id
-- =============================================================================
CREATE OR REPLACE FUNCTION get_top_products(
  p_store_id UUID DEFAULT NULL,
  p_location_id UUID DEFAULT NULL,
  p_category_name TEXT DEFAULT NULL,
  p_days INTEGER DEFAULT 30,
  p_limit INTEGER DEFAULT 20
)
RETURNS TABLE(
  product_id UUID,
  product_name TEXT,
  category_name TEXT,
  total_grams NUMERIC,
  total_revenue NUMERIC,
  order_count BIGINT,
  avg_price_per_gram NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    p.name,
    c.name,
    ROUND(SUM(oi.quantity_grams), 2),
    ROUND(SUM(oi.line_total), 2),
    COUNT(DISTINCT o.id),
    ROUND(SUM(oi.line_total) / NULLIF(SUM(oi.quantity_grams), 0), 2)
  FROM order_items oi
  JOIN orders o ON oi.order_id = o.id
  JOIN products p ON oi.product_id = p.id
  LEFT JOIN categories c ON p.primary_category_id = c.id
  LEFT JOIN fulfillments f ON f.order_id = o.id
  WHERE o.status = 'completed'
    AND o.created_at >= NOW() - (p_days || ' days')::INTERVAL
    AND (p_store_id IS NULL OR o.store_id = p_store_id)
    AND (p_location_id IS NULL OR f.delivery_location_id = p_location_id OR o.location_id = p_location_id)
    AND (p_category_name IS NULL OR c.name ILIKE p_category_name)
  GROUP BY p.id, p.name, c.name
  ORDER BY SUM(oi.line_total) DESC
  LIMIT p_limit;
END;
$$;


-- =============================================================================
-- 2. get_category_performance - fix to use fulfillments.delivery_location_id
-- =============================================================================
CREATE OR REPLACE FUNCTION get_category_performance(
  p_store_id UUID DEFAULT NULL,
  p_location_id UUID DEFAULT NULL,
  p_days INTEGER DEFAULT 30
)
RETURNS TABLE(
  category_id UUID,
  category_name TEXT,
  order_count BIGINT,
  total_grams NUMERIC,
  total_revenue NUMERIC,
  avg_price_per_gram NUMERIC,
  revenue_share NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_revenue NUMERIC;
BEGIN
  -- Get total revenue first
  SELECT SUM(oi.line_total) INTO v_total_revenue
  FROM order_items oi
  JOIN orders o ON oi.order_id = o.id
  LEFT JOIN fulfillments f ON f.order_id = o.id
  WHERE o.status = 'completed'
    AND o.created_at >= NOW() - (p_days || ' days')::INTERVAL
    AND (p_store_id IS NULL OR o.store_id = p_store_id)
    AND (p_location_id IS NULL OR f.delivery_location_id = p_location_id OR o.location_id = p_location_id);

  RETURN QUERY
  SELECT
    c.id,
    c.name,
    COUNT(DISTINCT o.id),
    ROUND(SUM(oi.quantity_grams), 2),
    ROUND(SUM(oi.line_total), 2),
    ROUND(SUM(oi.line_total) / NULLIF(SUM(oi.quantity_grams), 0), 2),
    ROUND(100.0 * SUM(oi.line_total) / NULLIF(v_total_revenue, 0), 1)
  FROM order_items oi
  JOIN orders o ON oi.order_id = o.id
  JOIN products p ON oi.product_id = p.id
  LEFT JOIN categories c ON p.primary_category_id = c.id
  LEFT JOIN fulfillments f ON f.order_id = o.id
  WHERE o.status = 'completed'
    AND o.created_at >= NOW() - (p_days || ' days')::INTERVAL
    AND (p_store_id IS NULL OR o.store_id = p_store_id)
    AND (p_location_id IS NULL OR f.delivery_location_id = p_location_id OR o.location_id = p_location_id)
  GROUP BY c.id, c.name
  ORDER BY SUM(oi.line_total) DESC;
END;
$$;


-- =============================================================================
-- 3. get_week_over_week - fix to use fulfillments.delivery_location_id
-- =============================================================================
CREATE OR REPLACE FUNCTION get_week_over_week(
  p_store_id UUID DEFAULT NULL
)
RETURNS TABLE(
  location_id UUID,
  location_name TEXT,
  last_week_revenue NUMERIC,
  this_week_revenue NUMERIC,
  change_percent NUMERIC,
  trend TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH this_week AS (
    SELECT
      COALESCE(f.delivery_location_id, o.location_id) as loc_id,
      l.name as loc_name,
      SUM(o.total_amount) as revenue
    FROM orders o
    LEFT JOIN fulfillments f ON f.order_id = o.id
    JOIN locations l ON COALESCE(f.delivery_location_id, o.location_id) = l.id
    WHERE o.status = 'completed'
      AND o.created_at >= NOW() - INTERVAL '7 days'
      AND (p_store_id IS NULL OR o.store_id = p_store_id)
      AND l.type = 'retail'
    GROUP BY COALESCE(f.delivery_location_id, o.location_id), l.name
  ),
  last_week AS (
    SELECT
      COALESCE(f.delivery_location_id, o.location_id) as loc_id,
      SUM(o.total_amount) as revenue
    FROM orders o
    LEFT JOIN fulfillments f ON f.order_id = o.id
    JOIN locations l ON COALESCE(f.delivery_location_id, o.location_id) = l.id
    WHERE o.status = 'completed'
      AND o.created_at >= NOW() - INTERVAL '14 days'
      AND o.created_at < NOW() - INTERVAL '7 days'
      AND (p_store_id IS NULL OR o.store_id = p_store_id)
      AND l.type = 'retail'
    GROUP BY COALESCE(f.delivery_location_id, o.location_id)
  )
  SELECT
    tw.loc_id,
    tw.loc_name,
    ROUND(COALESCE(lw.revenue, 0), 2),
    ROUND(tw.revenue, 2),
    CASE
      WHEN COALESCE(lw.revenue, 0) = 0 THEN NULL
      ELSE ROUND(100.0 * (tw.revenue - COALESCE(lw.revenue, 0)) / lw.revenue, 1)
    END,
    CASE
      WHEN COALESCE(lw.revenue, 0) = 0 THEN 'new'
      WHEN tw.revenue > lw.revenue * 1.1 THEN 'growing'
      WHEN tw.revenue < lw.revenue * 0.9 THEN 'declining'
      ELSE 'stable'
    END
  FROM this_week tw
  LEFT JOIN last_week lw ON tw.loc_id = lw.loc_id
  ORDER BY tw.revenue DESC;
END;
$$;


-- =============================================================================
-- 4. get_inventory_velocity - fix to use fulfillments.delivery_location_id
-- =============================================================================
CREATE OR REPLACE FUNCTION get_inventory_velocity(
  p_store_id UUID DEFAULT NULL,
  p_location_id UUID DEFAULT NULL,
  p_category_name TEXT DEFAULT NULL,
  p_days INTEGER DEFAULT 30
)
RETURNS TABLE(
  location_id UUID,
  location_name TEXT,
  location_type TEXT,
  category_id UUID,
  category_name TEXT,
  current_stock NUMERIC,
  sold_in_period NUMERIC,
  daily_velocity NUMERIC,
  days_of_stock NUMERIC,
  status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH location_stock AS (
    SELECT
      l.id as loc_id,
      l.name as loc_name,
      l.type as loc_type,
      c.id as cat_id,
      c.name as cat_name,
      SUM(i.quantity) as stock
    FROM inventory i
    JOIN locations l ON i.location_id = l.id
    JOIN products p ON i.product_id = p.id
    LEFT JOIN categories c ON p.primary_category_id = c.id
    WHERE (p_store_id IS NULL OR i.store_id = p_store_id)
      AND (p_location_id IS NULL OR l.id = p_location_id)
      AND (p_category_name IS NULL OR c.name ILIKE p_category_name)
      AND l.type = 'retail'
    GROUP BY l.id, l.name, l.type, c.id, c.name
  ),
  location_sales AS (
    SELECT
      COALESCE(f.delivery_location_id, o.location_id) as loc_id,
      c.id as cat_id,
      SUM(oi.quantity_grams) as sold
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.id
    JOIN products p ON oi.product_id = p.id
    LEFT JOIN categories c ON p.primary_category_id = c.id
    LEFT JOIN fulfillments f ON f.order_id = o.id
    WHERE o.status = 'completed'
      AND o.created_at >= NOW() - (p_days || ' days')::INTERVAL
      AND (p_store_id IS NULL OR o.store_id = p_store_id)
      AND (p_category_name IS NULL OR c.name ILIKE p_category_name)
    GROUP BY COALESCE(f.delivery_location_id, o.location_id), c.id
  )
  SELECT
    st.loc_id,
    st.loc_name,
    st.loc_type,
    st.cat_id,
    st.cat_name,
    ROUND(st.stock, 2),
    ROUND(COALESCE(sa.sold, 0), 2),
    ROUND(COALESCE(sa.sold, 0) / p_days, 2),
    CASE
      WHEN COALESCE(sa.sold, 0) = 0 THEN NULL
      ELSE ROUND(st.stock / (sa.sold / p_days), 1)
    END,
    CASE
      WHEN COALESCE(sa.sold, 0) = 0 THEN 'no_sales'
      WHEN st.stock / (sa.sold / p_days) <= 7 THEN 'critical'
      WHEN st.stock / (sa.sold / p_days) <= 14 THEN 'low'
      WHEN st.stock / (sa.sold / p_days) <= 30 THEN 'ok'
      ELSE 'overstocked'
    END
  FROM location_stock st
  LEFT JOIN location_sales sa ON st.loc_id = sa.loc_id AND st.cat_id = sa.cat_id
  ORDER BY
    CASE
      WHEN COALESCE(sa.sold, 0) = 0 THEN 9999
      ELSE st.stock / (sa.sold / p_days)
    END ASC;
END;
$$;


-- =============================================================================
-- 5. is_order_visible_to_location - use fulfillments + channel
-- =============================================================================
CREATE OR REPLACE FUNCTION is_order_visible_to_location(
  p_order_id UUID,
  p_location_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order RECORD;
  v_fulfillment RECORD;
BEGIN
  -- Get order details
  SELECT id, channel, location_id
  INTO v_order
  FROM orders
  WHERE id = p_order_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  -- Get primary fulfillment
  SELECT type, delivery_location_id
  INTO v_fulfillment
  FROM fulfillments
  WHERE order_id = p_order_id
  ORDER BY created_at ASC
  LIMIT 1;

  -- Retail orders: visible to the order's location
  IF v_order.channel = 'retail' THEN
    RETURN v_order.location_id = p_location_id;
  END IF;

  -- Online orders: check fulfillment location
  IF v_fulfillment.delivery_location_id = p_location_id THEN
    RETURN true;
  END IF;

  -- Check if any items are routed to this location
  RETURN EXISTS (
    SELECT 1 FROM order_items
    WHERE order_id = p_order_id
    AND location_id = p_location_id
  );
END;
$$;


-- =============================================================================
-- 6. can_location_update_order - use fulfillments + channel
-- =============================================================================
CREATE OR REPLACE FUNCTION can_location_update_order(
  p_order_id UUID,
  p_location_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order RECORD;
  v_fulfillment RECORD;
  v_has_items boolean;
BEGIN
  -- Get order details
  SELECT id, channel, location_id
  INTO v_order
  FROM orders
  WHERE id = p_order_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('can_update', false, 'reason', 'Order not found');
  END IF;

  -- Get primary fulfillment
  SELECT type, delivery_location_id
  INTO v_fulfillment
  FROM fulfillments
  WHERE order_id = p_order_id
  ORDER BY created_at ASC
  LIMIT 1;

  -- Retail orders: must match order location exactly
  IF v_order.channel = 'retail' THEN
    IF v_order.location_id = p_location_id THEN
      RETURN jsonb_build_object('can_update', true, 'reason', 'Order location matches');
    END IF;
    RETURN jsonb_build_object('can_update', false, 'reason', 'Order belongs to another location');
  END IF;

  -- Online pickup: check fulfillment location
  IF v_fulfillment.type = 'pickup' THEN
    IF v_fulfillment.delivery_location_id = p_location_id THEN
      RETURN jsonb_build_object('can_update', true, 'reason', 'Pickup location matches');
    END IF;
    RETURN jsonb_build_object('can_update', false, 'reason', 'Order not assigned to this location');
  END IF;

  -- Shipping: can update if items are routed here
  IF v_fulfillment.type = 'ship' THEN
    SELECT EXISTS (
      SELECT 1 FROM order_items
      WHERE order_id = p_order_id
      AND location_id = p_location_id
    ) INTO v_has_items;

    IF v_has_items THEN
      RETURN jsonb_build_object('can_update', true, 'reason', 'Items routed to this location');
    END IF;
    RETURN jsonb_build_object('can_update', false, 'reason', 'No items to fulfill at this location');
  END IF;

  -- Default: check if items are routed here
  SELECT EXISTS (
    SELECT 1 FROM order_items
    WHERE order_id = p_order_id
    AND location_id = p_location_id
  ) INTO v_has_items;

  IF v_has_items THEN
    RETURN jsonb_build_object('can_update', true, 'reason', 'Items at this location');
  END IF;

  RETURN jsonb_build_object('can_update', false, 'reason', 'Not authorized for this order');
END;
$$;


-- =============================================================================
-- 7. get_order_items_for_location - use fulfillments + channel
-- =============================================================================
CREATE OR REPLACE FUNCTION get_order_items_for_location(
  p_order_id UUID,
  p_location_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order RECORD;
  v_fulfillment RECORD;
  v_items_for_location jsonb;
  v_items_other jsonb;
BEGIN
  -- Get order and fulfillment info
  SELECT o.id, o.channel, o.location_id, f.type as fulfillment_type, f.delivery_location_id
  INTO v_order
  FROM orders o
  LEFT JOIN LATERAL (
    SELECT * FROM fulfillments WHERE order_id = o.id ORDER BY created_at ASC LIMIT 1
  ) f ON true
  WHERE o.id = p_order_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('items_for_location', '[]'::jsonb, 'items_other', '[]'::jsonb);
  END IF;

  -- For retail or immediate fulfillment, all items belong to order location
  IF v_order.channel = 'retail' OR v_order.fulfillment_type = 'immediate' THEN
    IF v_order.location_id = p_location_id OR v_order.delivery_location_id = p_location_id THEN
      SELECT jsonb_agg(jsonb_build_object(
        'id', id, 'product_id', product_id, 'product_name', product_name,
        'quantity', quantity, 'unit_price', unit_price, 'line_total', line_total,
        'location_id', location_id
      )) INTO v_items_for_location
      FROM order_items WHERE order_id = p_order_id;

      RETURN jsonb_build_object(
        'items_for_location', COALESCE(v_items_for_location, '[]'::jsonb),
        'items_other', '[]'::jsonb
      );
    ELSE
      SELECT jsonb_agg(jsonb_build_object(
        'id', id, 'product_id', product_id, 'product_name', product_name,
        'quantity', quantity, 'unit_price', unit_price, 'line_total', line_total,
        'location_id', location_id
      )) INTO v_items_other
      FROM order_items WHERE order_id = p_order_id;

      RETURN jsonb_build_object(
        'items_for_location', '[]'::jsonb,
        'items_other', COALESCE(v_items_other, '[]'::jsonb)
      );
    END IF;
  END IF;

  -- For shipping/pickup, filter by item location_id
  SELECT jsonb_agg(jsonb_build_object(
    'id', id, 'product_id', product_id, 'product_name', product_name,
    'quantity', quantity, 'unit_price', unit_price, 'line_total', line_total,
    'location_id', location_id
  )) INTO v_items_for_location
  FROM order_items WHERE order_id = p_order_id AND location_id = p_location_id;

  SELECT jsonb_agg(jsonb_build_object(
    'id', id, 'product_id', product_id, 'product_name', product_name,
    'quantity', quantity, 'unit_price', unit_price, 'line_total', line_total,
    'location_id', location_id
  )) INTO v_items_other
  FROM order_items WHERE order_id = p_order_id AND (location_id IS NULL OR location_id != p_location_id);

  RETURN jsonb_build_object(
    'items_for_location', COALESCE(v_items_for_location, '[]'::jsonb),
    'items_other', COALESCE(v_items_other, '[]'::jsonb)
  );
END;
$$;


-- =============================================================================
-- 8. sync_order_locations - use fulfillments instead of pickup_location_id
-- =============================================================================
CREATE OR REPLACE FUNCTION sync_order_locations(p_order_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Delete existing entries for this order
  DELETE FROM order_locations WHERE order_id = p_order_id;

  -- Insert aggregated data from order_items, using fulfillment location as fallback
  INSERT INTO order_locations (order_id, location_id, item_count, total_quantity)
  SELECT
    oi.order_id,
    COALESCE(oi.location_id, f.delivery_location_id, o.location_id) as location_id,
    COUNT(*) as item_count,
    SUM(oi.quantity) as total_quantity
  FROM order_items oi
  JOIN orders o ON o.id = oi.order_id
  LEFT JOIN LATERAL (
    SELECT delivery_location_id FROM fulfillments WHERE order_id = o.id ORDER BY created_at ASC LIMIT 1
  ) f ON true
  WHERE oi.order_id = p_order_id
    AND COALESCE(oi.location_id, f.delivery_location_id, o.location_id) IS NOT NULL
  GROUP BY oi.order_id, COALESCE(oi.location_id, f.delivery_location_id, o.location_id);
END;
$$;


-- Grant permissions on all updated functions
GRANT EXECUTE ON FUNCTION get_top_products(UUID, UUID, TEXT, INTEGER, INTEGER) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_category_performance(UUID, UUID, INTEGER) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_week_over_week(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_inventory_velocity(UUID, UUID, TEXT, INTEGER) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION is_order_visible_to_location(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION can_location_update_order(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_order_items_for_location(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION sync_order_locations(UUID) TO authenticated, service_role;
