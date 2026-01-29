# Proper Extension of Existing Orders System for Document Services

## Current System Analysis

### Existing Architecture (What You Already Have):

```
orders (main order table)
├── order_items (line items in order)
│   ├── product_id → products
│   ├── meta_data (JSONB) ← WE EXTEND THIS
│   └── fulfillment_status
├── order_status_history (audit trail)
├── order_events (event tracking)
└── products (catalog items)
    ├── product_categories
    ├── product_variants
    └── meta_data (JSONB) ← WE EXTEND THIS
```

**Key Insight:** You already have everything needed! We just need to:
1. **Extend** `order_items.meta_data` to store service request details
2. **Extend** `products.meta_data` to mark products as "services"
3. **Use existing** order statuses for service lifecycle
4. **Add** service-specific fields to existing tables

---

## Solution: Extend Orders System for Services

### 1. **Product Types - Add "Service" Products**

Your `products` table already supports different types. We extend it:

```sql
-- Products table already has:
-- - type: 'simple', 'physical', 'variable'
-- - meta_data: JSONB

-- ADD service product types:
UPDATE products SET
  type = 'service',
  meta_data = meta_data || jsonb_build_object(
    'service_config', jsonb_build_object(
      'service_type', 'lab_testing',
      'service_subtype', 'cannabis_coa',
      'requires_sample', true,
      'delivery_method', 'digital',
      'turnaround_days', 7,
      'test_options', jsonb_build_array(
        jsonb_build_object('id', 'potency', 'name', 'Potency Analysis', 'default', true),
        jsonb_build_object('id', 'terpenes', 'name', 'Terpene Profile'),
        jsonb_build_object('id', 'pesticides', 'name', 'Pesticides')
      ),
      'required_fields', jsonb_build_array('batch_number', 'sample_weight')
    )
  )
WHERE ...;
```

**Service Product Examples:**
- "Cannabis COA - Standard Panel" (product_id: uuid)
- "Cannabis COA - Full Compliance Panel" (product_id: uuid)
- "Peptide Purity Analysis" (product_id: uuid)
- "Terpene Profile Only" (product_id: uuid)

---

### 2. **Order Items - Store Service Request Data**

Use existing `order_items` table with extended `meta_data`:

```sql
-- order_items already has:
-- - product_id (links to service product)
-- - meta_data (JSONB) ← EXTEND THIS
-- - fulfillment_status ('unfulfilled', 'partial', 'fulfilled', 'cancelled')

-- Example order_item for COA service:
INSERT INTO order_items (
  order_id,
  product_id, -- Links to "Cannabis COA - Standard Panel" product
  product_name,
  unit_price,
  quantity,
  line_total,
  fulfillment_status,
  meta_data
) VALUES (
  '...order_id...',
  '...service_product_id...',
  'Cannabis COA - Standard Panel',
  150.00,
  1,
  150.00,
  'unfulfilled', -- Service not completed yet
  jsonb_build_object(
    'item_type', 'service_request',
    'service_data', jsonb_build_object(
      'product_name', 'Blue Razz THCA',
      'batch_number', 'BT-5521',
      'strain_name', 'Blue Razz',
      'sample_type', 'Concentrate',
      'sample_weight_grams', 5.0,
      'test_types', jsonb_build_array('potency', 'terpenes', 'pesticides'),
      'priority', 'standard',
      'customer_notes', 'Rush if possible'
    ),
    'service_provider', jsonb_build_object(
      'provider_name', 'Quantix Analytics',
      'lab_id', null,
      'estimated_completion', '2024-02-15'
    ),
    'result_document_id', null, -- Filled when complete
    'result_url', null
  )
);
```

**Benefit:** Uses existing order system, no new tables needed!

---

### 3. **Order Statuses - Map to Service Lifecycle**

Use existing `orders.status` field with service-specific meanings:

```sql
-- orders.status CHECK constraint:
-- 'pending', 'confirmed', 'preparing', 'packing', 'packed',
-- 'ready', 'out_for_delivery', 'ready_to_ship', 'shipped',
-- 'in_transit', 'delivered', 'completed', 'cancelled'
```

**Service Status Mapping:**

| Order Status | Service Meaning | Description |
|--------------|-----------------|-------------|
| `pending` | Draft | Service request being filled out |
| `confirmed` | Submitted | Request submitted, awaiting processing |
| `preparing` | Sample Received | Lab received sample, starting tests |
| `packing` | Testing In Progress | Lab is running tests |
| `ready` | Results Ready | Tests complete, document being prepared |
| `completed` | Service Delivered | COA document delivered |
| `cancelled` | Cancelled | Request cancelled |

**Fulfillment Status** (order_items.fulfillment_status):
- `unfulfilled` - Service not started
- `partial` - Some tests complete (multi-test orders)
- `fulfilled` - Service complete, document delivered
- `cancelled` - Service cancelled

---

### 4. **Extend Stores Table - Business Compliance**

```sql
-- stores table - add compliance fields
ALTER TABLE stores ADD COLUMN IF NOT EXISTS compliance_data JSONB DEFAULT '{}'::jsonb;

-- Example cannabis store compliance:
UPDATE stores SET compliance_data = jsonb_build_object(
  'license_number', 'C11-0000123-LIC',
  'license_type', 'Manufacturer',
  'license_state', 'CA',
  'license_expiration', '2025-12-31',
  'regulatory_agency', 'California DCC',
  'business_address', jsonb_build_object(
    'street', '123 Main St',
    'city', 'Los Angeles',
    'state', 'CA',
    'zip', '90001'
  ),
  'contact_email', 'compliance@store.com',
  'contact_phone', '555-123-4567'
)
WHERE id = '...store_id...';
```

---

### 5. **Link Results to Documents**

When service completes, link to existing `store_documents`:

```sql
-- Update order_item with result
UPDATE order_items SET
  fulfillment_status = 'fulfilled',
  meta_data = meta_data || jsonb_build_object(
    'result_document_id', '...store_documents.id...',
    'result_url', 'https://storage/path/to/COA.pdf',
    'completed_at', NOW()
  )
WHERE id = '...order_item_id...';

-- Update store_documents with link back
UPDATE store_documents SET
  metadata = metadata || jsonb_build_object(
    'order_id', '...orders.id...',
    'order_item_id', '...order_items.id...'
  )
WHERE id = '...document_id...';
```

---

## Complete Workflow Example

### Step 1: Create Service Products (One-Time Setup)

```sql
INSERT INTO products (
  store_id,
  name,
  slug,
  sku,
  type,
  status,
  primary_category_id,
  description,
  meta_data
) VALUES
(
  '...quantix_store_id...',
  'Cannabis COA - Standard Panel',
  'cannabis-coa-standard',
  'SRV-COA-STD',
  'service', -- Mark as service product
  'published',
  '...testing_services_category_id...',
  'Standard cannabis COA with potency, terpenes, and pesticides testing',
  jsonb_build_object(
    'service_config', jsonb_build_object(
      'service_type', 'lab_testing',
      'service_subtype', 'cannabis_coa',
      'turnaround_days', 7,
      'price', 150.00,
      'test_options', jsonb_build_array(
        jsonb_build_object('id', 'potency', 'name', 'Potency Analysis', 'included', true),
        jsonb_build_object('id', 'terpenes', 'name', 'Terpene Profile', 'included', true),
        jsonb_build_object('id', 'pesticides', 'name', 'Pesticides', 'included', true)
      ),
      'add_on_tests', jsonb_build_array(
        jsonb_build_object('id', 'heavy_metals', 'name', 'Heavy Metals', 'price', 50),
        jsonb_build_object('id', 'microbials', 'name', 'Microbials', 'price', 75)
      ),
      'required_fields', jsonb_build_array('batch_number', 'sample_weight', 'sample_type')
    ),
    'is_service', true,
    'delivery_method', 'digital'
  )
);
```

### Step 2: User Requests Service (Creates Order)

**User Action:** "Request COA for Blue Razz THCA"

```sql
-- Create order
INSERT INTO orders (
  order_number,
  store_id,
  platform_user_id,
  status,
  payment_status,
  subtotal,
  total_amount,
  metadata
) VALUES (
  'REQ-2024-001', -- Can use existing order_number generation
  '...customer_store_id...',
  '...platform_user_id...',
  'pending', -- Draft state
  'pending',
  150.00,
  150.00,
  jsonb_build_object(
    'order_type', 'service_request',
    'service_category', 'lab_testing'
  )
) RETURNING id INTO order_id;

-- Create order_item (the actual service request)
INSERT INTO order_items (
  order_id,
  product_id, -- "Cannabis COA - Standard Panel"
  product_name,
  product_sku,
  unit_price,
  quantity,
  line_total,
  fulfillment_status,
  meta_data
) VALUES (
  order_id,
  '...service_product_id...',
  'Cannabis COA - Standard Panel',
  'SRV-COA-STD',
  150.00,
  1,
  150.00,
  'unfulfilled',
  jsonb_build_object(
    'item_type', 'service_request',
    'service_data', jsonb_build_object(
      'product_name', 'Blue Razz THCA',
      'batch_number', 'BT-5521',
      'strain_name', 'Blue Razz',
      'sample_type', 'Concentrate',
      'sample_weight_grams', 5.0,
      'test_types', jsonb_build_array('potency', 'terpenes', 'pesticides'),
      'priority', 'standard',
      'customer_notes', 'Rush if possible'
    ),
    'service_provider', jsonb_build_object(
      'provider_name', 'Quantix Analytics',
      'estimated_completion', '2024-02-15'
    )
  )
);
```

### Step 3: Submit Request (Update Order Status)

```sql
UPDATE orders SET
  status = 'confirmed', -- Submitted state
  submitted_at = NOW(),
  metadata = metadata || jsonb_build_object(
    'submitted_by', '...user_id...',
    'submission_timestamp', NOW()
  )
WHERE id = order_id;

-- order_status_history trigger automatically logs this change
```

### Step 4: Lab Receives Sample

```sql
UPDATE orders SET status = 'preparing' -- Sample received
WHERE id = order_id;

-- Add note
INSERT INTO order_notes (order_id, note, created_by) VALUES
(order_id, 'Sample received at lab - ID: LAB-12345', '...lab_user_id...');
```

### Step 5: Testing In Progress

```sql
UPDATE orders SET status = 'packing' -- Testing in progress
WHERE id = order_id;
```

### Step 6: Results Ready

```sql
-- Upload COA to store_documents (existing table)
INSERT INTO store_documents (
  store_id,
  document_name,
  document_type,
  file_url,
  data,
  metadata
) VALUES (
  '...customer_store_id...',
  'Blue Razz THCA - Batch BT-5521 - COA',
  'coa',
  'https://storage/Blue_Razz_THCA_COA.pdf',
  jsonb_build_object('sampleType', 'Concentrate', ...test results...),
  jsonb_build_object(
    'order_id', order_id,
    'order_item_id', '...order_item_id...',
    'batch_number', 'BT-5521'
  )
) RETURNING id INTO document_id;

-- Update order_item with result
UPDATE order_items SET
  fulfillment_status = 'fulfilled',
  meta_data = meta_data || jsonb_build_object(
    'result_document_id', document_id,
    'result_url', 'https://storage/Blue_Razz_THCA_COA.pdf',
    'completed_at', NOW()
  )
WHERE id = '...order_item_id...';

-- Update order status
UPDATE orders SET status = 'ready' -- Results ready
WHERE id = order_id;
```

### Step 7: Deliver Document

```sql
UPDATE orders SET
  status = 'completed', -- Service delivered
  completed_at = NOW()
WHERE id = order_id;

-- Existing auto-categorization runs on store_documents
-- Creates/links product in catalog
```

---

## UI Integration

### Dashboard Changes

#### 1. **"Request Service" Button**

```tsx
// Add to dashboard header
<button onClick={() => showServiceRequestModal()}>
  <Plus /> Request Service
</button>
```

**Opens:** Service product selector or direct form

#### 2. **Service Request Form** (Creates Order)

```tsx
<ServiceRequestForm>
  {/* Step 1: Select Service Product */}
  <ProductSelector
    products={serviceProducts.filter(p => p.meta_data.is_service)}
    onSelect={setSelectedProduct}
  />

  {/* Step 2: Service Details (dynamic from product.meta_data.service_config) */}
  <ServiceDetailsForm
    requiredFields={product.meta_data.service_config.required_fields}
    testOptions={product.meta_data.service_config.test_options}
  />

  {/* Step 3: Review & Submit (Creates Order + Order Item) */}
  <ReviewSubmit onSubmit={createOrder} />
</ServiceRequestForm>
```

#### 3. **Orders Page** (View Service Requests)

**Reuse existing orders UI** with service-specific views:

```tsx
<OrdersPage>
  <FilterBar>
    <OrderTypeFilter> {/* All | Physical Orders | Service Requests */}
      <option value="all">All Orders</option>
      <option value="physical">Physical Orders</option>
      <option value="service">Service Requests</option>
    </OrderTypeFilter>
    <StatusFilter /> {/* Existing status filter */}
  </FilterBar>

  <OrdersTable>
    {orders.map(order => (
      <OrderRow
        order={order}
        displayMode={order.metadata.order_type === 'service_request' ? 'service' : 'standard'}
      />
    ))}
  </OrdersTable>
</OrdersPage>
```

**Service Order Row Display:**
```
| Order # | Service | Sample | Status | Submitted | Est. Completion | Actions |
|---------|---------|--------|--------|-----------|-----------------|---------|
| REQ-001 | COA Standard | Blue Razz (BT-5521) | Testing | Jan 20 | Jan 27 | [View] |
```

#### 4. **Order Detail Modal** (Service-Specific View)

```tsx
<OrderDetailModal order={order}>
  {order.metadata.order_type === 'service_request' ? (
    <ServiceOrderView>
      {/* Service Details */}
      <ServiceInfo>
        <h3>{order.items[0].product_name}</h3>
        <ServiceData data={order.items[0].meta_data.service_data} />
      </ServiceInfo>

      {/* Status Timeline */}
      <StatusTimeline history={order.status_history} />

      {/* Result Document (if completed) */}
      {order.items[0].meta_data.result_document_id && (
        <ResultDocument documentId={order.items[0].meta_data.result_document_id} />
      )}
    </ServiceOrderView>
  ) : (
    <StandardOrderView order={order} />
  )}
</OrderDetailModal>
```

---

## API Routes (Reuse Existing Patterns)

### Create Service Request

**Endpoint:** `POST /api/orders` (existing)

**Body:**
```json
{
  "store_id": "uuid",
  "items": [
    {
      "product_id": "service-product-uuid",
      "quantity": 1,
      "meta_data": {
        "item_type": "service_request",
        "service_data": {
          "product_name": "Blue Razz THCA",
          "batch_number": "BT-5521",
          "sample_type": "Concentrate",
          "test_types": ["potency", "terpenes", "pesticides"]
        }
      }
    }
  ],
  "metadata": {
    "order_type": "service_request"
  }
}
```

**Response:** Standard order object

### List Service Requests

**Endpoint:** `GET /api/orders?type=service_request` (existing with filter)

### Update Service Status

**Endpoint:** `PATCH /api/orders/:id` (existing)

**Body:**
```json
{
  "status": "preparing" // or "packing", "ready", "completed"
}
```

---

## Database Migrations

### Migration 1: Add Service Product Type

```sql
-- No schema change needed! Already supports custom types
-- Just insert service products with type='service'
```

### Migration 2: Add Compliance to Stores

```sql
ALTER TABLE stores ADD COLUMN IF NOT EXISTS compliance_data JSONB DEFAULT '{}'::jsonb;
CREATE INDEX idx_stores_compliance ON stores USING GIN (compliance_data);
```

### Migration 3: Add Service Metadata Indexes

```sql
-- Index order_items meta_data for service queries
CREATE INDEX idx_order_items_service_type
ON order_items USING GIN (meta_data)
WHERE (meta_data->>'item_type') = 'service_request';

-- Index orders metadata for service orders
CREATE INDEX idx_orders_service_type
ON orders USING GIN (metadata)
WHERE (metadata->>'order_type') = 'service_request';
```

---

## Benefits of This Approach

### ✅ Extends Existing System
- Uses existing `orders` and `order_items` tables
- Leverages existing status workflow
- Reuses order number generation
- Maintains audit trails (order_status_history)

### ✅ No Duplication
- Don't rebuild order management
- Don't rebuild status tracking
- Don't rebuild audit logging
- Don't rebuild payment integration

### ✅ Unified Order Management
- Service requests appear in same orders list
- Same permissions/policies apply
- Same reporting/analytics
- Same admin tools

### ✅ Flexible via JSONB
- Service-specific data in `meta_data`
- No rigid schemas
- Easy to add new service types
- Different services, same structure

### ✅ Product Catalog Integration
- Services are products
- Browse/search service catalog
- Product variants for different service tiers
- Pricing tied to product pricing system

---

## Summary

**What to Build:**

1. ✅ **Service Products** - Create products with `type='service'` and service config in `meta_data`
2. ✅ **Order Creation** - Use existing order system, store service data in `order_items.meta_data`
3. ✅ **Status Mapping** - Map order statuses to service lifecycle
4. ✅ **Compliance Fields** - Add `compliance_data` JSONB to `stores`
5. ✅ **UI Components** - Service request form, service order views
6. ✅ **Document Linking** - Link completed services to `store_documents`

**What NOT to Build:**

❌ **New Orders Table** - Use existing `orders`
❌ **New Line Items** - Use existing `order_items`
❌ **New Status System** - Use existing order statuses
❌ **New Audit System** - Use existing `order_status_history`

**This is the proper way** - extend what exists, don't rebuild!
