-- Fix get_orders_for_location - remove user_id, use v_store_customers

DROP FUNCTION IF EXISTS get_orders_for_location(uuid, uuid, text, text, text, text, timestamptz, timestamptz, numeric, numeric, boolean, integer);

CREATE OR REPLACE FUNCTION get_orders_for_location(
  p_store_id UUID,
  p_location_id UUID,
  p_status_group TEXT DEFAULT NULL,
  p_order_type TEXT DEFAULT NULL,
  p_payment_status TEXT DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
  p_date_start TIMESTAMPTZ DEFAULT NULL,
  p_date_end TIMESTAMPTZ DEFAULT NULL,
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

  RETURN QUERY
  SELECT
    jsonb_build_object(
      'id', o.id,
      'order_number', o.order_number,
      'store_id', o.store_id,
      'location_id', o.location_id,
      'customer_id', o.customer_id,
      'employee_id', o.employee_id,
      'status', o.status,
      'channel', o.channel,
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
      'staff_notes', o.staff_notes,
      'created_at', o.created_at,
      'updated_at', o.updated_at,
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
      'items', COALESCE(
        (
          SELECT jsonb_agg(
            jsonb_build_object(
              'id', oi.id,
              'product_id', oi.product_id,
              'product_name', COALESCE(p.name, oi.product_name),
              'quantity', oi.quantity,
              'unit_price', oi.unit_price,
              'total', oi.line_total,
              'tier_label', oi.tier_name,
              'variant_name', oi.product_name
            )
          )
          FROM order_items oi
          LEFT JOIN products p ON p.id = oi.product_id
          WHERE oi.order_id = o.id
        ),
        '[]'::jsonb
      ),
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
  LEFT JOIN v_store_customers c ON c.id = o.customer_id
  LEFT JOIN locations l ON l.id = o.location_id
  LEFT JOIN LATERAL (
    SELECT * FROM fulfillments
    WHERE order_id = o.id
    ORDER BY created_at ASC
    LIMIT 1
  ) f ON true
  WHERE o.store_id = p_store_id
    AND o.location_id = p_location_id
    AND (
      p_status_group IS NULL
      OR o.status = ANY(v_status_filters)
    )
    AND (
      p_order_type IS NULL
      OR (p_order_type = 'walk_in' AND (o.channel = 'retail' OR f.type = 'immediate'))
      OR (p_order_type = 'pickup' AND o.channel = 'online' AND f.type = 'pickup')
      OR (p_order_type = 'shipping' AND o.channel = 'online' AND f.type = 'ship')
      OR (p_order_type = 'direct' AND o.channel = 'online' AND f.type IS NULL)
    )
    AND (
      p_payment_status IS NULL
      OR o.payment_status = p_payment_status
    )
    AND (
      p_search IS NULL
      OR o.order_number ILIKE '%' || p_search || '%'
      OR c.first_name ILIKE '%' || p_search || '%'
      OR c.last_name ILIKE '%' || p_search || '%'
      OR (c.first_name || ' ' || c.last_name) ILIKE '%' || p_search || '%'
    )
    AND (
      p_date_start IS NULL
      OR o.created_at >= p_date_start
    )
    AND (
      p_date_end IS NULL
      OR o.created_at <= p_date_end
    )
    AND (
      p_amount_min IS NULL
      OR o.total_amount >= p_amount_min
    )
    AND (
      p_amount_max IS NULL
      OR o.total_amount <= p_amount_max
    )
    AND (
      NOT p_online_only
      OR o.channel = 'online'
    )
  ORDER BY o.created_at DESC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION get_orders_for_location(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, NUMERIC, NUMERIC, BOOLEAN, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_orders_for_location(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, NUMERIC, NUMERIC, BOOLEAN, INTEGER) TO service_role;
