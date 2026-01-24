-- get_order_for_printing RPC - fetch order with FULL product details for label printing
-- Returns everything needed for printing in a single query:
-- - Order metadata
-- - Full product details (images, custom_fields, pricing)
-- - COAs if available
-- - Optimized for label printing workflow

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
  -- Single query that fetches order + full product details
  SELECT jsonb_build_object(
    'order_id', o.id,
    'order_number', o.order_number,
    'store_id', o.store_id,
    'location_id', o.location_id,
    'pickup_location_id', o.pickup_location_id,
    'pickup_location', CASE
      WHEN pl.id IS NOT NULL THEN
        jsonb_build_object('id', pl.id, 'name', pl.name)
      ELSE NULL
    END,
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
  LEFT JOIN locations pl ON pl.id = o.pickup_location_id
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

COMMENT ON FUNCTION get_order_for_printing IS 'Fetch order with complete product details for label printing. Returns order + full product data (images, custom_fields, COAs) in a single optimized query.';
-- get_orders_for_location RPC - fetch orders with advanced filtering
-- This function returns orders visible to a specific location with support for:
-- - Status group filtering (active, in_progress, completed, cancelled)
-- - Order type filtering (pickup, shipping, walk_in, direct, etc.)
-- - Payment status filtering
-- - Search by order number or customer name
-- - Date range filtering
-- - Amount range filtering
-- - Online-only filter

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
      'order_type', o.order_type,
      'payment_status', o.payment_status,
      'subtotal', o.subtotal,
      'tax_amount', o.tax_amount,
      'discount_amount', o.discount_amount,
      'total_amount', o.total_amount,
      'notes', o.notes,
      'created_at', o.created_at,
      'updated_at', o.updated_at,
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
  WHERE o.store_id = p_store_id
    AND o.location_id = p_location_id
    -- Status group filter
    AND (
      p_status_group IS NULL
      OR o.status = ANY(v_status_filters)
    )
    -- Order type filter
    AND (
      p_order_type IS NULL
      OR o.order_type = p_order_type
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
    -- Online only filter (pickup + shipping)
    AND (
      NOT p_online_only
      OR o.order_type IN ('pickup', 'shipping')
    )
  ORDER BY o.created_at DESC
  LIMIT p_limit;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_orders_for_location(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMP, TIMESTAMP, NUMERIC, NUMERIC, BOOLEAN, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_orders_for_location(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMP, TIMESTAMP, NUMERIC, NUMERIC, BOOLEAN, INTEGER) TO service_role;

COMMENT ON FUNCTION get_orders_for_location IS 'Fetch orders for a location with advanced filtering support including status groups, order types, payment status, search, date ranges, and amount ranges.';
-- =============================================================================
-- Print Labels Tool Registration
-- =============================================================================
--
-- Registers the print_labels tool that AI agents can use to print product labels.
-- Supports printing by order ID or individual product IDs.
--

INSERT INTO ai_tool_registry (
  name,
  category,
  description,
  definition,
  is_active,
  tool_mode
) VALUES (
  'print_labels',
  'pos',
  'Print product labels to a configured printer. Can print labels for an entire order (using order_id) or specific products (using product_ids). The system will fetch full product data including images, QR codes, and custom fields, then send to the configured label printer. Respects the saved label start position.',
  '{
    "type": "object",
    "properties": {
      "order_id": {
        "type": "string",
        "description": "UUID of the order to print labels for. Will print labels for all items in the order with proper quantities."
      },
      "product_ids": {
        "type": "array",
        "items": {
          "type": "string"
        },
        "description": "Array of product UUIDs to print labels for. Each product will get one label. Use this for manual label printing."
      },
      "quantity": {
        "type": "integer",
        "description": "When using product_ids, how many labels to print per product (default: 1)",
        "default": 1,
        "minimum": 1,
        "maximum": 100
      },
      "start_position": {
        "type": "integer",
        "description": "Label sheet start position (0-9, representing positions 1-10). Overrides saved position. Use this to continue on a partially-used label sheet.",
        "minimum": 0,
        "maximum": 9
      }
    },
    "oneOf": [
      {"required": ["order_id"]},
      {"required": ["product_ids"]}
    ]
  }'::jsonb,
  true,
  'function'
) ON CONFLICT (name) DO UPDATE SET
  category = EXCLUDED.category,
  description = EXCLUDED.description,
  definition = EXCLUDED.definition,
  is_active = EXCLUDED.is_active,
  tool_mode = EXCLUDED.tool_mode,
  updated_at = NOW();

-- Create RPC function for AI to call
CREATE OR REPLACE FUNCTION print_labels(
  p_user_id UUID,
  p_order_id UUID DEFAULT NULL,
  p_product_ids UUID[] DEFAULT NULL,
  p_quantity INTEGER DEFAULT 1,
  p_start_position INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSONB;
  v_order_data JSONB;
  v_products JSONB;
  v_store_id UUID;
  v_location_id UUID;
  v_item_count INTEGER := 0;
BEGIN
  -- Validate: must have either order_id or product_ids
  IF p_order_id IS NULL AND (p_product_ids IS NULL OR array_length(p_product_ids, 1) IS NULL) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Must provide either order_id or product_ids'
    );
  END IF;

  -- If printing by order
  IF p_order_id IS NOT NULL THEN
    -- Fetch order with full product details
    SELECT get_order_for_printing(p_order_id) INTO v_order_data;

    IF v_order_data IS NULL OR v_order_data->>'error' IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', COALESCE(v_order_data->>'error', 'Order not found')
      );
    END IF;

    -- Count items
    SELECT COUNT(*)::integer INTO v_item_count
    FROM jsonb_array_elements(v_order_data->'items') item,
         LATERAL (SELECT (item->>'quantity')::integer) q;

    RETURN jsonb_build_object(
      'success', true,
      'message', format('Queued %s labels for order %s', v_item_count, v_order_data->>'order_number'),
      'order_id', p_order_id,
      'order_number', v_order_data->>'order_number',
      'item_count', v_item_count,
      'order_data', v_order_data,
      'start_position', p_start_position
    );
  END IF;

  -- If printing by product IDs
  IF p_product_ids IS NOT NULL THEN
    v_item_count := array_length(p_product_ids, 1) * p_quantity;

    -- Fetch product details
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'name', p.name,
        'sku', p.sku,
        'featured_image', p.featured_image,
        'custom_fields', p.custom_fields,
        'store_id', p.store_id
      )
    ) INTO v_products
    FROM products p
    WHERE p.id = ANY(p_product_ids);

    IF v_products IS NULL OR jsonb_array_length(v_products) = 0 THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'No products found with provided IDs'
      );
    END IF;

    RETURN jsonb_build_object(
      'success', true,
      'message', format('Queued %s labels for %s products', v_item_count, jsonb_array_length(v_products)),
      'product_count', jsonb_array_length(v_products),
      'quantity_per_product', p_quantity,
      'total_labels', v_item_count,
      'products', v_products,
      'start_position', p_start_position
    );
  END IF;

  -- Should never reach here
  RETURN jsonb_build_object(
    'success', false,
    'error', 'Invalid parameters'
  );
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION print_labels(UUID, UUID, UUID[], INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION print_labels(UUID, UUID, UUID[], INTEGER, INTEGER) TO service_role;

COMMENT ON FUNCTION print_labels IS 'AI-callable function to print product labels. Returns print job details that the client can execute.';

-- Log registration
DO $$
BEGIN
  RAISE NOTICE 'Registered print_labels tool for AI label printing';
END $$;
