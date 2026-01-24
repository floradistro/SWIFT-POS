-- Fix backfill functions that reference orders.pickup_location_id and orders.order_type
-- These functions create events from historical orders

-- =============================================================================
-- 1. backfill_order_events - main backfill function
-- =============================================================================
DROP FUNCTION IF EXISTS backfill_order_events(uuid, timestamptz, integer);

CREATE OR REPLACE FUNCTION backfill_order_events(
  p_tenant_id UUID DEFAULT NULL,
  p_start_date TIMESTAMPTZ DEFAULT '2020-01-01'::timestamptz,
  p_batch_size INTEGER DEFAULT 1000
)
RETURNS TABLE(
  orders_processed BIGINT,
  items_processed BIGINT,
  events_created BIGINT,
  elapsed_seconds NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_start_time TIMESTAMPTZ := NOW();
  v_order RECORD;
  v_item RECORD;
  v_orders_processed BIGINT := 0;
  v_items_processed BIGINT := 0;
  v_events_created BIGINT := 0;
  v_prev_hash TEXT;
  v_event_hash TEXT;
  v_partition_month DATE;
  v_order_payload JSONB;
  v_item_payload JSONB;
  v_location_id UUID;
  v_order_type TEXT;
BEGIN
  -- Process completed orders
  FOR v_order IN
    SELECT
      o.id, o.order_number, o.store_id, o.customer_id,
      o.location_id, o.channel,
      o.total_amount, o.subtotal, o.tax_amount, o.discount_amount,
      o.refund_amount, o.cost_of_goods, o.gross_profit,
      o.payment_method, o.employee_id,
      COALESCE(o.completed_at, o.created_at) as completed_at,
      o.created_at,
      f.delivery_location_id,
      f.type as fulfillment_type
    FROM orders o
    LEFT JOIN LATERAL (
      SELECT delivery_location_id, type FROM fulfillments WHERE order_id = o.id ORDER BY created_at ASC LIMIT 1
    ) f ON true
    WHERE o.status = 'completed'
      AND (p_tenant_id IS NULL OR o.store_id = p_tenant_id)
      AND o.created_at >= p_start_date
      AND NOT EXISTS (
        SELECT 1 FROM events e
        WHERE e.aggregate_id = o.id
          AND e.event_type = 'order.completed'
      )
    ORDER BY o.created_at
    LIMIT p_batch_size
  LOOP
    v_partition_month := date_trunc('month', v_order.completed_at)::DATE;

    -- Compute location_id (fulfillment location or order location)
    v_location_id := COALESCE(v_order.delivery_location_id, v_order.location_id);

    -- Compute order_type from channel + fulfillment type
    v_order_type := CASE
      WHEN v_order.channel = 'retail' THEN 'walk_in'
      WHEN v_order.fulfillment_type = 'pickup' THEN 'pickup'
      WHEN v_order.fulfillment_type = 'ship' THEN 'shipping'
      WHEN v_order.fulfillment_type = 'immediate' THEN 'walk_in'
      ELSE 'online'
    END;

    -- Get previous hash for this aggregate
    SELECT event_hash INTO v_prev_hash
    FROM events
    WHERE tenant_id = v_order.store_id
      AND aggregate_type = 'order'
      AND aggregate_id = v_order.id
    ORDER BY sequence_num DESC
    LIMIT 1;

    -- Build FULL payload
    v_order_payload := jsonb_build_object(
      'order_id', v_order.id,
      'order_number', v_order.order_number,
      'customer_id', v_order.customer_id,
      'location_id', v_location_id,
      'total_amount', v_order.total_amount,
      'subtotal', v_order.subtotal,
      'tax_amount', v_order.tax_amount,
      'discount_amount', v_order.discount_amount,
      'refund_amount', v_order.refund_amount,
      'cost_of_goods', v_order.cost_of_goods,
      'gross_profit', v_order.gross_profit,
      'payment_method', v_order.payment_method,
      'order_type', v_order_type,
      'channel', v_order.channel
    );

    -- Compute hash with FULL payload
    v_event_hash := compute_event_hash(
      'order.completed', 'order', v_order.id, v_order.store_id,
      v_order_payload,
      v_order.completed_at,
      v_prev_hash
    );

    -- Insert order.completed event
    INSERT INTO events (
      event_type, aggregate_type, aggregate_id, tenant_id,
      payload, occurred_at, actor_type, actor_id,
      prev_event_hash, event_hash, partition_month,
      metadata
    ) VALUES (
      'order.completed', 'order', v_order.id, v_order.store_id,
      v_order_payload,
      v_order.completed_at,
      'migration', v_order.employee_id,
      v_prev_hash, v_event_hash, v_partition_month,
      jsonb_build_object('source', 'backfill', 'original_created_at', v_order.created_at)
    );

    v_events_created := v_events_created + 1;
    v_orders_processed := v_orders_processed + 1;
    v_prev_hash := v_event_hash;

    -- Process order items
    FOR v_item IN
      SELECT
        oi.id, oi.product_id, oi.product_name, oi.product_sku,
        oi.quantity, oi.quantity_grams, oi.unit_price, oi.line_total,
        oi.tax_amount as item_tax,
        COALESCE(oi.location_id, v_location_id) as loc_id,
        p.primary_category_id
      FROM order_items oi
      LEFT JOIN products p ON oi.product_id = p.id
      WHERE oi.order_id = v_order.id
    LOOP
      -- Build item payload
      v_item_payload := jsonb_build_object(
        'order_id', v_order.id,
        'item_id', v_item.id,
        'product_id', v_item.product_id,
        'product_name', v_item.product_name,
        'location_id', v_item.loc_id,
        'category_id', v_item.primary_category_id,
        'quantity', v_item.quantity,
        'quantity_grams', v_item.quantity_grams,
        'unit_price', v_item.unit_price,
        'line_total', v_item.line_total
      );

      -- Compute hash with same payload
      v_event_hash := compute_event_hash(
        'order.item_added', 'order', v_order.id, v_order.store_id,
        v_item_payload,
        v_order.completed_at,
        v_prev_hash
      );

      INSERT INTO events (
        event_type, aggregate_type, aggregate_id, tenant_id,
        payload, occurred_at, actor_type,
        prev_event_hash, event_hash, partition_month,
        metadata
      ) VALUES (
        'order.item_added', 'order', v_order.id, v_order.store_id,
        v_item_payload,
        v_order.completed_at,
        'migration',
        v_prev_hash, v_event_hash, v_partition_month,
        jsonb_build_object('source', 'backfill')
      );

      v_events_created := v_events_created + 1;
      v_items_processed := v_items_processed + 1;
      v_prev_hash := v_event_hash;
    END LOOP;
  END LOOP;

  RETURN QUERY SELECT
    v_orders_processed,
    v_items_processed,
    v_events_created,
    ROUND(EXTRACT(EPOCH FROM (NOW() - v_start_time))::NUMERIC, 2);
END;
$$;


-- =============================================================================
-- 2. backfill_order_cancelled_events
-- =============================================================================
DROP FUNCTION IF EXISTS backfill_order_cancelled_events(integer);

CREATE OR REPLACE FUNCTION backfill_order_cancelled_events(
  p_batch_size INTEGER DEFAULT 1000
)
RETURNS TABLE(
  events_created BIGINT,
  elapsed_seconds NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order RECORD;
  v_payload JSONB;
  v_event_hash TEXT;
  v_prev_hash TEXT;
  v_start_time TIMESTAMPTZ := clock_timestamp();
  v_created BIGINT := 0;
  v_occurred_at TIMESTAMPTZ;
  v_location_id UUID;
  v_order_type TEXT;
BEGIN
  FOR v_order IN
    SELECT o.*,
           f.delivery_location_id,
           f.type as fulfillment_type
    FROM orders o
    LEFT JOIN LATERAL (
      SELECT delivery_location_id, type FROM fulfillments WHERE order_id = o.id ORDER BY created_at ASC LIMIT 1
    ) f ON true
    WHERE o.status = 'cancelled'
    AND NOT EXISTS (
      SELECT 1 FROM events e
      WHERE e.aggregate_id = o.id
      AND e.event_type = 'order.cancelled'
    )
    ORDER BY o.cancelled_date NULLS LAST, o.updated_at
    LIMIT p_batch_size
  LOOP
    v_occurred_at := COALESCE(v_order.cancelled_date, v_order.updated_at);
    v_location_id := COALESCE(v_order.delivery_location_id, v_order.location_id);
    v_order_type := CASE
      WHEN v_order.channel = 'retail' THEN 'walk_in'
      WHEN v_order.fulfillment_type = 'pickup' THEN 'pickup'
      WHEN v_order.fulfillment_type = 'ship' THEN 'shipping'
      ELSE 'online'
    END;

    -- Get previous hash for this aggregate
    SELECT event_hash INTO v_prev_hash
    FROM events
    WHERE aggregate_id = v_order.id
    ORDER BY sequence_num DESC
    LIMIT 1;

    -- Build payload
    v_payload := jsonb_build_object(
      'order_id', v_order.id,
      'order_number', v_order.order_number,
      'customer_id', v_order.customer_id,
      'location_id', v_location_id,
      'total_amount', v_order.total_amount,
      'subtotal', v_order.subtotal,
      'tax_amount', v_order.tax_amount,
      'discount_amount', v_order.discount_amount,
      'payment_method', v_order.payment_method,
      'order_type', v_order_type,
      'channel', v_order.channel,
      'cancelled_reason', v_order.staff_notes
    );

    -- Compute hash
    v_event_hash := compute_event_hash(
      'order.cancelled', 'order', v_order.id, v_order.store_id,
      v_payload,
      v_occurred_at,
      v_prev_hash
    );

    -- Insert event
    INSERT INTO events (
      event_type, aggregate_type, aggregate_id, tenant_id,
      payload, occurred_at, event_hash, prev_event_hash,
      partition_month, sequence_num
    ) VALUES (
      'order.cancelled', 'order', v_order.id, v_order.store_id,
      v_payload,
      v_occurred_at,
      v_event_hash, v_prev_hash,
      date_trunc('month', v_occurred_at)::DATE,
      COALESCE((SELECT MAX(sequence_num) + 1 FROM events WHERE aggregate_id = v_order.id), 1)
    );

    v_created := v_created + 1;
  END LOOP;

  RETURN QUERY SELECT v_created, EXTRACT(EPOCH FROM clock_timestamp() - v_start_time)::NUMERIC;
END;
$$;


-- =============================================================================
-- 3. backfill_order_refunded_events
-- =============================================================================
DROP FUNCTION IF EXISTS backfill_order_refunded_events(integer);

CREATE OR REPLACE FUNCTION backfill_order_refunded_events(
  p_batch_size INTEGER DEFAULT 1000
)
RETURNS TABLE(
  events_created BIGINT,
  elapsed_seconds NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_start_time TIMESTAMPTZ := clock_timestamp();
  v_created BIGINT := 0;
BEGIN
  WITH refunded_orders AS (
    SELECT
      o.id,
      o.order_number,
      o.customer_id,
      COALESCE(f.delivery_location_id, o.location_id) as location_id,
      o.store_id,
      o.total_amount,
      o.refund_amount,
      o.payment_method,
      o.channel,
      f.type as fulfillment_type,
      o.updated_at as occurred_at
    FROM orders o
    LEFT JOIN LATERAL (
      SELECT delivery_location_id, type FROM fulfillments WHERE order_id = o.id ORDER BY created_at ASC LIMIT 1
    ) f ON true
    WHERE o.refund_amount > 0
    AND NOT EXISTS (
      SELECT 1 FROM events e
      WHERE e.aggregate_id = o.id
      AND e.event_type = 'order.refunded'
    )
    ORDER BY o.updated_at
    LIMIT p_batch_size
  ),
  payloads AS (
    SELECT
      ro.*,
      CASE
        WHEN ro.channel = 'retail' THEN 'walk_in'
        WHEN ro.fulfillment_type = 'pickup' THEN 'pickup'
        WHEN ro.fulfillment_type = 'ship' THEN 'shipping'
        ELSE 'online'
      END as order_type,
      jsonb_build_object(
        'order_id', ro.id,
        'order_number', ro.order_number,
        'customer_id', ro.customer_id,
        'location_id', ro.location_id,
        'original_total', ro.total_amount,
        'refund_amount', ro.refund_amount,
        'payment_method', ro.payment_method,
        'channel', ro.channel,
        'order_type', CASE
          WHEN ro.channel = 'retail' THEN 'walk_in'
          WHEN ro.fulfillment_type = 'pickup' THEN 'pickup'
          WHEN ro.fulfillment_type = 'ship' THEN 'shipping'
          ELSE 'online'
        END
      ) as payload
    FROM refunded_orders ro
  ),
  inserted AS (
    INSERT INTO events (
      event_type, aggregate_type, aggregate_id, tenant_id,
      payload, occurred_at, event_hash, prev_event_hash,
      partition_month, sequence_num
    )
    SELECT
      'order.refunded',
      'order',
      p.id,
      p.store_id,
      p.payload,
      p.occurred_at,
      encode(sha256(
        ('order.refunded' || 'order' || p.id::text || p.store_id::text ||
         p.payload::text || p.occurred_at::text)::bytea
      ), 'hex'),
      (SELECT event_hash FROM events WHERE aggregate_id = p.id ORDER BY sequence_num DESC LIMIT 1),
      date_trunc('month', p.occurred_at)::DATE,
      COALESCE((SELECT MAX(sequence_num) + 1 FROM events WHERE aggregate_id = p.id), 1)
    FROM payloads p
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_created FROM inserted;

  RETURN QUERY SELECT v_created, EXTRACT(EPOCH FROM clock_timestamp() - v_start_time)::NUMERIC;
END;
$$;


-- =============================================================================
-- 4. backfill_order_shipped_events
-- =============================================================================
DROP FUNCTION IF EXISTS backfill_order_shipped_events(integer);

CREATE OR REPLACE FUNCTION backfill_order_shipped_events(
  p_batch_size INTEGER DEFAULT 1000
)
RETURNS TABLE(
  events_created BIGINT,
  elapsed_seconds NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_start_time TIMESTAMPTZ := clock_timestamp();
  v_created BIGINT := 0;
BEGIN
  WITH shipped_orders AS (
    SELECT o.id, o.order_number, o.store_id, o.customer_id,
           COALESCE(f.delivery_location_id, o.location_id) as location_id,
           o.total_amount, o.tracking_number,
           f.carrier,
           o.shipped_by_user_id, o.shipped_at
    FROM orders o
    LEFT JOIN LATERAL (
      SELECT delivery_location_id, carrier FROM fulfillments WHERE order_id = o.id ORDER BY created_at ASC LIMIT 1
    ) f ON true
    WHERE o.shipped_at IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM events e WHERE e.aggregate_id = o.id AND e.event_type = 'order.shipped'
    )
    LIMIT p_batch_size
  ),
  inserted AS (
    INSERT INTO events (event_type, aggregate_type, aggregate_id, tenant_id, payload, occurred_at,
                       event_hash, prev_event_hash, partition_month, sequence_num)
    SELECT 'order.shipped', 'order', so.id, so.store_id,
           jsonb_build_object('order_id', so.id, 'order_number', so.order_number,
               'tracking_number', so.tracking_number, 'carrier', so.carrier,
               'shipped_by', so.shipped_by_user_id),
           so.shipped_at,
           encode(sha256(convert_to('order.shipped'||'order'||so.id::text||so.store_id::text||so.shipped_at::text,'UTF8')),'hex'),
           (SELECT event_hash FROM events WHERE aggregate_id = so.id ORDER BY sequence_num DESC LIMIT 1),
           date_trunc('month', so.shipped_at)::DATE,
           COALESCE((SELECT MAX(sequence_num)+1 FROM events WHERE aggregate_id = so.id), 1)
    FROM shipped_orders so
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_created FROM inserted;
  RETURN QUERY SELECT v_created, EXTRACT(EPOCH FROM clock_timestamp() - v_start_time)::NUMERIC;
END;
$$;


-- Grant permissions
GRANT EXECUTE ON FUNCTION backfill_order_events(UUID, TIMESTAMPTZ, INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION backfill_order_cancelled_events(INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION backfill_order_refunded_events(INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION backfill_order_shipped_events(INTEGER) TO service_role;
