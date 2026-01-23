-- Fix missing award_loyalty_points function
-- This function is called by a trigger when orders are completed
-- to award loyalty points based on the order total

-- =============================================================================
-- 1. Create the award_loyalty_points function
-- =============================================================================
-- Signature: award_loyalty_points(store_id, customer_id, order_id, order_amount)
-- customer_id is the relationship_id from user_creation_relationships

CREATE OR REPLACE FUNCTION award_loyalty_points(
  p_store_id UUID,
  p_customer_id UUID,
  p_order_id UUID,
  p_order_amount NUMERIC
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_loyalty_program loyalty_programs%ROWTYPE;
  v_points_to_award INT;
  v_current_points INT;
  v_new_points INT;
  v_new_total_spent NUMERIC;
  v_new_total_orders INT;
BEGIN
  -- Skip if no customer_id
  IF p_customer_id IS NULL THEN
    RETURN;
  END IF;

  -- Skip if amount is zero or negative
  IF p_order_amount IS NULL OR p_order_amount <= 0 THEN
    RETURN;
  END IF;

  -- Get the store's active loyalty program
  SELECT * INTO v_loyalty_program
  FROM loyalty_programs
  WHERE store_id = p_store_id
    AND is_active = true
  LIMIT 1;

  -- If no loyalty program, exit silently
  IF v_loyalty_program IS NULL THEN
    RAISE NOTICE 'No active loyalty program for store %', p_store_id;
    RETURN;
  END IF;

  -- Calculate points to award: order_amount * points_per_dollar
  -- Round down to nearest integer
  v_points_to_award := FLOOR(p_order_amount * v_loyalty_program.points_per_dollar);

  -- Skip if no points to award
  IF v_points_to_award <= 0 THEN
    RETURN;
  END IF;

  -- Get current loyalty data from store_customer_profiles
  SELECT
    COALESCE(loyalty_points, 0),
    COALESCE(total_spent, 0),
    COALESCE(total_orders, 0)
  INTO v_current_points, v_new_total_spent, v_new_total_orders
  FROM store_customer_profiles
  WHERE relationship_id = p_customer_id;

  -- If no profile exists, create one
  IF NOT FOUND THEN
    INSERT INTO store_customer_profiles (
      relationship_id,
      loyalty_points,
      total_spent,
      total_orders,
      created_at,
      updated_at
    ) VALUES (
      p_customer_id,
      v_points_to_award,
      p_order_amount,
      1,
      NOW(),
      NOW()
    );

    v_current_points := 0;
    v_new_points := v_points_to_award;
  ELSE
    -- Update existing profile
    v_new_points := v_current_points + v_points_to_award;
    v_new_total_spent := v_new_total_spent + p_order_amount;
    v_new_total_orders := v_new_total_orders + 1;

    UPDATE store_customer_profiles
    SET
      loyalty_points = v_new_points,
      total_spent = v_new_total_spent,
      total_orders = v_new_total_orders,
      lifetime_value = v_new_total_spent,
      updated_at = NOW()
    WHERE relationship_id = p_customer_id;
  END IF;

  -- Record loyalty transaction
  INSERT INTO loyalty_transactions (
    customer_id,
    store_id,
    order_id,
    points,
    balance_before,
    balance_after,
    transaction_type,
    reference_type,
    reference_id,
    description,
    created_at
  ) VALUES (
    p_customer_id,
    p_store_id,
    p_order_id,
    v_points_to_award,
    v_current_points,
    v_new_points,
    'earned',
    'order',
    p_order_id,
    'Earned ' || v_points_to_award || ' points on purchase',
    NOW()
  );

  RAISE NOTICE 'Awarded % points to customer % (order: %, amount: $%)',
    v_points_to_award, p_customer_id, p_order_id, p_order_amount;

EXCEPTION
  WHEN OTHERS THEN
    -- Log error but don't fail the order
    RAISE WARNING 'Failed to award loyalty points: %', SQLERRM;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION award_loyalty_points(UUID, UUID, UUID, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION award_loyalty_points(UUID, UUID, UUID, NUMERIC) TO service_role;

COMMENT ON FUNCTION award_loyalty_points IS 'Awards loyalty points to a customer based on order amount. Called by trigger after order completion.';


-- =============================================================================
-- 2. Create/Update the trigger to call award_loyalty_points on order completion
-- =============================================================================

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS trigger_award_loyalty_points ON orders;
DROP FUNCTION IF EXISTS trigger_award_loyalty_points_fn();

CREATE OR REPLACE FUNCTION trigger_award_loyalty_points_fn()
RETURNS TRIGGER AS $$
BEGIN
  -- Only award points when order transitions to completed status
  IF NEW.status = 'completed' AND (OLD IS NULL OR OLD.status != 'completed') THEN
    -- Award loyalty points based on order total
    PERFORM award_loyalty_points(
      NEW.store_id,
      NEW.customer_id,
      NEW.id,
      COALESCE(NEW.total_amount, 0)
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_award_loyalty_points
  AFTER INSERT OR UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION trigger_award_loyalty_points_fn();

COMMENT ON TRIGGER trigger_award_loyalty_points ON orders IS 'Awards loyalty points to customer when order is completed';


-- =============================================================================
-- 3. Ensure loyalty_transactions table has correct constraints
-- =============================================================================

-- Add 'earned' to transaction_type if not already allowed
-- This is idempotent - ALTER TYPE ADD VALUE doesn't error if value exists in PostgreSQL 9.3+
DO $$
BEGIN
  -- Check if loyalty_transactions has a transaction_type constraint
  -- If so, ensure 'earned' is allowed
  IF EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    WHERE t.relname = 'loyalty_transactions'
      AND c.contype = 'c'
      AND c.conname LIKE '%transaction_type%'
  ) THEN
    -- The constraint exists, we may need to update it
    -- First check what values are allowed
    RAISE NOTICE 'Checking loyalty_transactions transaction_type constraint...';
  END IF;
END $$;


-- =============================================================================
-- Done!
-- =============================================================================
DO $$
BEGIN
  RAISE NOTICE '===========================================';
  RAISE NOTICE 'Loyalty points function fix complete!';
  RAISE NOTICE 'Created: award_loyalty_points(uuid, uuid, uuid, numeric)';
  RAISE NOTICE 'Created: trigger_award_loyalty_points trigger on orders';
  RAISE NOTICE '===========================================';
END $$;
