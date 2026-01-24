-- Fix triggers that reference old columns (pickup_location_id, order_type, delivery_type)

-- 1. Fix trigger_order_completed
CREATE OR REPLACE FUNCTION trigger_order_completed()
RETURNS TRIGGER AS $$
DECLARE
    v_payload JSONB;
    v_event_hash TEXT;
    v_prev_hash TEXT;
    v_order_type TEXT;
    v_location_id UUID;
BEGIN
    IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN

        SELECT event_hash INTO v_prev_hash
        FROM events WHERE aggregate_id = NEW.id
        ORDER BY sequence_num DESC LIMIT 1;

        -- Compute order_type from channel + fulfillment
        SELECT
            CASE
                WHEN NEW.channel = 'retail' THEN 'walk_in'
                WHEN f.type = 'pickup' THEN 'pickup'
                WHEN f.type = 'ship' THEN 'shipping'
                ELSE 'online'
            END,
            COALESCE(f.delivery_location_id, NEW.location_id)
        INTO v_order_type, v_location_id
        FROM orders o
        LEFT JOIN LATERAL (
            SELECT type, delivery_location_id FROM fulfillments
            WHERE order_id = o.id
            ORDER BY created_at ASC
            LIMIT 1
        ) f ON true
        WHERE o.id = NEW.id;

        v_payload := jsonb_build_object(
            'order_id', NEW.id,
            'order_number', NEW.order_number,
            'customer_id', NEW.customer_id,
            'location_id', v_location_id,
            'total_amount', NEW.total_amount,
            'subtotal', NEW.subtotal,
            'tax_amount', NEW.tax_amount,
            'discount_amount', NEW.discount_amount,
            'refund_amount', NEW.refund_amount,
            'cost_of_goods', NEW.cost_of_goods,
            'gross_profit', NEW.gross_profit,
            'payment_method', NEW.payment_method,
            'order_type', v_order_type
        );

        v_event_hash := encode(sha256(convert_to(
            'order.completed' || 'order' || NEW.id::text || NEW.store_id::text ||
            v_payload::text || COALESCE(NEW.completed_at, NOW())::text || COALESCE(v_prev_hash, ''), 'UTF8'
        )), 'hex');

        INSERT INTO events (
            event_type, aggregate_type, aggregate_id, tenant_id,
            payload, occurred_at, event_hash, prev_event_hash,
            partition_month, sequence_num
        ) VALUES (
            'order.completed', 'order', NEW.id, NEW.store_id,
            v_payload, COALESCE(NEW.completed_at, NOW()), v_event_hash, v_prev_hash,
            date_trunc('month', COALESCE(NEW.completed_at, NOW()))::DATE,
            COALESCE((SELECT MAX(sequence_num) + 1 FROM events WHERE aggregate_id = NEW.id), 1)
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Fix trigger_order_cancelled
CREATE OR REPLACE FUNCTION trigger_order_cancelled()
RETURNS TRIGGER AS $$
DECLARE
    v_payload JSONB;
    v_event_hash TEXT;
    v_prev_hash TEXT;
    v_location_id UUID;
BEGIN
    IF NEW.status = 'cancelled' AND (OLD.status IS NULL OR OLD.status != 'cancelled') THEN

        SELECT event_hash INTO v_prev_hash
        FROM events WHERE aggregate_id = NEW.id
        ORDER BY sequence_num DESC LIMIT 1;

        -- Get location from fulfillment
        SELECT COALESCE(f.delivery_location_id, NEW.location_id) INTO v_location_id
        FROM orders o
        LEFT JOIN LATERAL (
            SELECT delivery_location_id FROM fulfillments
            WHERE order_id = o.id
            ORDER BY created_at ASC
            LIMIT 1
        ) f ON true
        WHERE o.id = NEW.id;

        v_payload := jsonb_build_object(
            'order_id', NEW.id,
            'order_number', NEW.order_number,
            'customer_id', NEW.customer_id,
            'location_id', v_location_id,
            'total_amount', NEW.total_amount,
            'cancelled_reason', NEW.staff_notes
        );

        v_event_hash := encode(sha256(convert_to(
            'order.cancelled' || 'order' || NEW.id::text || NEW.store_id::text ||
            v_payload::text || COALESCE(NEW.cancelled_date, NOW())::text, 'UTF8'
        )), 'hex');

        INSERT INTO events (
            event_type, aggregate_type, aggregate_id, tenant_id,
            payload, occurred_at, event_hash, prev_event_hash,
            partition_month, sequence_num
        ) VALUES (
            'order.cancelled', 'order', NEW.id, NEW.store_id,
            v_payload, COALESCE(NEW.cancelled_date, NOW()), v_event_hash, v_prev_hash,
            date_trunc('month', COALESCE(NEW.cancelled_date, NOW()))::DATE,
            COALESCE((SELECT MAX(sequence_num) + 1 FROM events WHERE aggregate_id = NEW.id), 1)
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Fix queue_new_order_email - disable if it references old columns
-- Since this trigger references pickup_location_id and delivery_type which don't exist,
-- we need to drop and recreate without those references
DROP TRIGGER IF EXISTS trigger_new_order_email ON orders;

-- 4. Fix queue_order_status_email - disable if it references old columns
DROP TRIGGER IF EXISTS trigger_order_status_email ON orders;
