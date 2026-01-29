# FINAL IMPLEMENTATION PLAN - Service Requests via Orders System

## Executive Summary

**Goal:** Add service request functionality (COA testing, document generation) by extending the existing orders system.

**Approach:** Zero new core tables. Extend existing `orders`, `order_items`, `products` with JSONB metadata.

**Timeline:** 8 implementation tasks

---

## Current System (What Exists)

### Database Tables:
```
orders
├── id, order_number, store_id, platform_user_id
├── status (pending, confirmed, preparing, packing, ready, completed, cancelled)
├── payment_status, fulfillment_status
├── metadata (JSONB)
└── All pricing, shipping, audit fields

order_items
├── id, order_id, product_id
├── product_name, unit_price, quantity, line_total
├── fulfillment_status (unfulfilled, partial, fulfilled, cancelled)
└── meta_data (JSONB) ← WE EXTEND THIS

products
├── id, store_id, name, slug, sku
├── type (simple, physical, variable) ← ADD 'service'
├── primary_category_id
├── status (published, draft, deleted)
└── meta_data (JSONB) ← WE EXTEND THIS

stores
├── id, store_name, slug, owner_user_id
└── (need to add: compliance_data JSONB)

store_documents
├── id, store_id, document_name, file_url
├── document_type, product_id
└── metadata (JSONB) ← Link back to orders

order_status_history (audit trail - already exists)
order_events (event tracking - already exists)
```

---

## What We're Building

### 1. Service Products (New Product Type)

**Concept:** Services (like "Cannabis COA") are products in your catalog.

**Example Products:**
- "Cannabis COA - Standard Panel" ($150)
- "Cannabis COA - Full Compliance" ($250)
- "Peptide Purity Analysis" ($300)
- "Terpene Profile Only" ($75)

**Product Structure:**
```sql
products
├── type = 'service' (new value)
└── meta_data = {
      "is_service": true,
      "service_config": {
        "service_type": "lab_testing",
        "service_subtype": "cannabis_coa",
        "turnaround_days": 7,
        "test_options": [
          {"id": "potency", "name": "Potency Analysis", "included": true},
          {"id": "terpenes", "name": "Terpene Profile", "included": true},
          {"id": "pesticides", "name": "Pesticides", "included": true}
        ],
        "add_on_tests": [
          {"id": "heavy_metals", "name": "Heavy Metals", "price": 50},
          {"id": "microbials", "name": "Microbials", "price": 75}
        ],
        "required_fields": ["batch_number", "sample_weight", "sample_type"]
      }
    }
```

### 2. Service Requests (Order Items with Metadata)

**Concept:** When user requests a service, create an order with an order_item containing service details.

**Order Item Structure:**
```sql
order_items
├── product_id → service product (e.g., "Cannabis COA - Standard Panel")
├── fulfillment_status = 'unfulfilled'
└── meta_data = {
      "item_type": "service_request",
      "service_data": {
        "product_name": "Blue Razz THCA",
        "batch_number": "BT-5521",
        "strain_name": "Blue Razz",
        "sample_type": "Concentrate",
        "sample_weight_grams": 5.0,
        "test_types": ["potency", "terpenes", "pesticides"],
        "priority": "standard",
        "customer_notes": "Rush if possible"
      },
      "service_provider": {
        "provider_name": "Quantix Analytics",
        "lab_id": null,
        "estimated_completion": "2024-02-15"
      },
      "result_document_id": null,  // Filled when service completes
      "result_url": null,
      "completed_at": null
    }
```

### 3. Status Lifecycle (Reuse Existing)

**Map existing order statuses to service lifecycle:**

| Order Status | Service Meaning | Fulfillment Status |
|--------------|-----------------|-------------------|
| `pending` | Draft - user filling form | `unfulfilled` |
| `confirmed` | Submitted to lab | `unfulfilled` |
| `preparing` | Sample received at lab | `unfulfilled` |
| `packing` | Testing in progress | `unfulfilled` |
| `ready` | Results ready | `unfulfilled` |
| `completed` | Document delivered | `fulfilled` |
| `cancelled` | Request cancelled | `cancelled` |

**Status Flow:**
```
User creates → pending (draft)
User submits → confirmed (submitted to lab)
Lab receives → preparing (sample received)
Lab testing → packing (tests running)
Lab done → ready (results ready)
Document delivered → completed (fulfilled)
```

### 4. Store Compliance (New Field)

**Add to stores table:**
```sql
stores.compliance_data = {
  "license_number": "C11-0000123-LIC",
  "license_type": "Manufacturer",
  "license_state": "CA",
  "license_expiration": "2025-12-31",
  "business_address": {
    "street": "123 Main St",
    "city": "Los Angeles",
    "state": "CA",
    "zip": "90001"
  },
  "contact_email": "compliance@store.com",
  "contact_phone": "555-123-4567"
}
```

### 5. Document Linking (Bidirectional)

**When service completes:**

```sql
-- Update order_item with result
order_items.meta_data.result_document_id = store_documents.id
order_items.fulfillment_status = 'fulfilled'

-- Update document with order link
store_documents.metadata.order_id = orders.id
store_documents.metadata.order_item_id = order_items.id

-- Update order status
orders.status = 'completed'
```

---

## Implementation Tasks

### Task 1: Database Migration

**File:** `migrations/001_add_service_support.sql`

```sql
-- 1. Add compliance_data to stores
ALTER TABLE stores ADD COLUMN IF NOT EXISTS compliance_data JSONB DEFAULT '{}'::jsonb;
CREATE INDEX idx_stores_compliance ON stores USING GIN (compliance_data);

-- 2. Add indexes for service queries
CREATE INDEX idx_order_items_service_type
ON order_items USING GIN (meta_data)
WHERE (meta_data->>'item_type') = 'service_request';

CREATE INDEX idx_orders_service_type
ON orders USING GIN (metadata)
WHERE (metadata->>'order_type') = 'service_request';

CREATE INDEX idx_products_service_type
ON products USING GIN (meta_data)
WHERE (meta_data->>'is_service') = 'true';

-- 3. No need to alter products.type CHECK constraint - it accepts any text value
-- Just document that 'service' is a valid type

COMMENT ON COLUMN products.type IS 'Product type: simple, physical, variable, service, digital, etc.';
COMMENT ON COLUMN products.meta_data IS 'Product metadata. For services, contains service_config with test_options, turnaround_days, required_fields.';
COMMENT ON COLUMN order_items.meta_data IS 'Order item metadata. For service requests, contains item_type=service_request and service_data.';
COMMENT ON COLUMN stores.compliance_data IS 'Store compliance information: license_number, business_address, contact info, etc.';
```

### Task 2: Create Service Products

**File:** `scripts/setup-service-products.ts`

```typescript
import { supabase } from '@/lib/supabase'

const QUANTIX_STORE_ID = 'bb73275b-edeb-4d1f-9c51-ddc57fa3a19b'

const serviceProducts = [
  {
    store_id: QUANTIX_STORE_ID,
    name: 'Cannabis COA - Standard Panel',
    slug: 'cannabis-coa-standard',
    sku: 'SRV-COA-STD',
    type: 'service',
    status: 'published',
    description: 'Standard cannabis COA with potency, terpenes, and pesticides testing',
    meta_data: {
      is_service: true,
      delivery_method: 'digital',
      service_config: {
        service_type: 'lab_testing',
        service_subtype: 'cannabis_coa',
        turnaround_days: 7,
        price: 150.00,
        test_options: [
          { id: 'potency', name: 'Potency Analysis (Cannabinoids)', included: true },
          { id: 'terpenes', name: 'Terpene Profile', included: true },
          { id: 'pesticides', name: 'Pesticides Screening', included: true }
        ],
        add_on_tests: [
          { id: 'heavy_metals', name: 'Heavy Metals', price: 50 },
          { id: 'residual_solvents', name: 'Residual Solvents', price: 50 },
          { id: 'microbials', name: 'Microbiological Testing', price: 75 },
          { id: 'mycotoxins', name: 'Mycotoxins', price: 75 }
        ],
        required_fields: ['batch_number', 'sample_weight', 'sample_type']
      }
    }
  },
  {
    store_id: QUANTIX_STORE_ID,
    name: 'Cannabis COA - Full Compliance Panel',
    slug: 'cannabis-coa-full',
    sku: 'SRV-COA-FULL',
    type: 'service',
    status: 'published',
    description: 'Full compliance panel including all required tests',
    meta_data: {
      is_service: true,
      delivery_method: 'digital',
      service_config: {
        service_type: 'lab_testing',
        service_subtype: 'cannabis_coa',
        turnaround_days: 10,
        price: 350.00,
        test_options: [
          { id: 'potency', name: 'Potency Analysis', included: true },
          { id: 'terpenes', name: 'Terpene Profile', included: true },
          { id: 'pesticides', name: 'Pesticides', included: true },
          { id: 'heavy_metals', name: 'Heavy Metals', included: true },
          { id: 'residual_solvents', name: 'Residual Solvents', included: true },
          { id: 'microbials', name: 'Microbiological Testing', included: true },
          { id: 'mycotoxins', name: 'Mycotoxins', included: true }
        ],
        add_on_tests: [],
        required_fields: ['batch_number', 'sample_weight', 'sample_type']
      }
    }
  },
  {
    store_id: QUANTIX_STORE_ID,
    name: 'Peptide Purity Analysis',
    slug: 'peptide-purity',
    sku: 'SRV-PEP-PUR',
    type: 'service',
    status: 'published',
    description: 'HPLC purity analysis for peptide samples',
    meta_data: {
      is_service: true,
      delivery_method: 'digital',
      service_config: {
        service_type: 'lab_testing',
        service_subtype: 'peptide_coa',
        turnaround_days: 7,
        price: 300.00,
        test_options: [
          { id: 'purity', name: 'HPLC Purity Analysis', included: true },
          { id: 'mass_spec', name: 'Mass Spectrometry', included: true }
        ],
        add_on_tests: [
          { id: 'sterility', name: 'Sterility Testing', price: 150 }
        ],
        required_fields: ['cas_number', 'sample_quantity']
      }
    }
  }
]

async function createServiceProducts() {
  console.log('Creating service products...')

  for (const product of serviceProducts) {
    const { data, error } = await supabase
      .from('products')
      .insert(product)
      .select()
      .single()

    if (error) {
      console.error(`Error creating ${product.name}:`, error)
    } else {
      console.log(`✓ Created: ${product.name} (${data.id})`)
    }
  }

  console.log('Done!')
}

createServiceProducts()
```

**Run:** `npx tsx scripts/setup-service-products.ts`

### Task 3: Store Settings Page

**File:** `app/dashboard/settings/page.tsx`

```tsx
'use client'

import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useRouter } from 'next/navigation'

interface StoreSettings {
  store_name: string
  compliance_data: {
    license_number?: string
    license_type?: string
    license_state?: string
    license_expiration?: string
    business_address?: {
      street: string
      city: string
      state: string
      zip: string
    }
    contact_email?: string
    contact_phone?: string
  }
}

export default function SettingsPage() {
  const router = useRouter()
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [storeId, setStoreId] = useState<string | null>(null)
  const [settings, setSettings] = useState<StoreSettings>({
    store_name: '',
    compliance_data: {
      business_address: {
        street: '',
        city: '',
        state: '',
        zip: ''
      }
    }
  })

  useEffect(() => {
    loadSettings()
  }, [])

  const loadSettings = async () => {
    try {
      // Get user
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) {
        router.push('/login')
        return
      }

      // Get platform user
      const { data: platformUser } = await supabase
        .from('platform_users')
        .select('id')
        .eq('auth_id', session.user.id)
        .single()

      if (!platformUser) return

      // Get store
      const { data: store } = await supabase
        .from('stores')
        .select('id, store_name, compliance_data')
        .eq('owner_user_id', platformUser.id)
        .single()

      if (store) {
        setStoreId(store.id)
        setSettings({
          store_name: store.store_name,
          compliance_data: store.compliance_data || {
            business_address: { street: '', city: '', state: '', zip: '' }
          }
        })
      }
    } catch (err) {
      console.error('Error loading settings:', err)
    } finally {
      setLoading(false)
    }
  }

  const handleSave = async () => {
    if (!storeId) return

    setSaving(true)
    try {
      const { error } = await supabase
        .from('stores')
        .update({
          compliance_data: settings.compliance_data,
          updated_at: new Date().toISOString()
        })
        .eq('id', storeId)

      if (error) throw error

      alert('Settings saved successfully!')
    } catch (err) {
      console.error('Error saving:', err)
      alert('Error saving settings')
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return <div className="p-8">Loading...</div>
  }

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <div className="bg-surface/50 border-b border-white/10 px-6 py-6">
        <h1 className="text-2xl font-bold text-white">Store Settings</h1>
        <p className="text-white/60 text-sm mt-1">
          Configure your business information for service requests
        </p>
      </div>

      {/* Form */}
      <div className="max-w-3xl mx-auto p-6 space-y-8">

        {/* Business Information */}
        <div className="bg-white/5 border border-white/10 rounded-lg p-6">
          <h2 className="text-lg font-semibold text-white mb-4">Business Information</h2>

          <div className="space-y-4">
            <div>
              <label className="block text-white/80 text-sm mb-2">Store Name</label>
              <input
                type="text"
                value={settings.store_name}
                disabled
                className="w-full bg-white/10 border border-white/20 rounded px-4 py-2 text-white"
              />
            </div>
          </div>
        </div>

        {/* License Information */}
        <div className="bg-white/5 border border-white/10 rounded-lg p-6">
          <h2 className="text-lg font-semibold text-white mb-4">License Information</h2>

          <div className="space-y-4">
            <div>
              <label className="block text-white/80 text-sm mb-2">
                License Number <span className="text-red-400">*</span>
              </label>
              <input
                type="text"
                value={settings.compliance_data.license_number || ''}
                onChange={(e) => setSettings({
                  ...settings,
                  compliance_data: {
                    ...settings.compliance_data,
                    license_number: e.target.value
                  }
                })}
                className="w-full bg-white/10 border border-white/20 rounded px-4 py-2 text-white"
                placeholder="e.g., C11-0000123-LIC"
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-white/80 text-sm mb-2">License Type</label>
                <select
                  value={settings.compliance_data.license_type || ''}
                  onChange={(e) => setSettings({
                    ...settings,
                    compliance_data: {
                      ...settings.compliance_data,
                      license_type: e.target.value
                    }
                  })}
                  className="w-full bg-white/10 border border-white/20 rounded px-4 py-2 text-white"
                >
                  <option value="">Select...</option>
                  <option value="Manufacturer">Manufacturer</option>
                  <option value="Distributor">Distributor</option>
                  <option value="Retailer">Retailer</option>
                  <option value="Testing Lab">Testing Lab</option>
                </select>
              </div>

              <div>
                <label className="block text-white/80 text-sm mb-2">State</label>
                <select
                  value={settings.compliance_data.license_state || ''}
                  onChange={(e) => setSettings({
                    ...settings,
                    compliance_data: {
                      ...settings.compliance_data,
                      license_state: e.target.value
                    }
                  })}
                  className="w-full bg-white/10 border border-white/20 rounded px-4 py-2 text-white"
                >
                  <option value="">Select...</option>
                  <option value="CA">California</option>
                  <option value="CO">Colorado</option>
                  <option value="OR">Oregon</option>
                  <option value="WA">Washington</option>
                </select>
              </div>
            </div>

            <div>
              <label className="block text-white/80 text-sm mb-2">Expiration Date</label>
              <input
                type="date"
                value={settings.compliance_data.license_expiration || ''}
                onChange={(e) => setSettings({
                  ...settings,
                  compliance_data: {
                    ...settings.compliance_data,
                    license_expiration: e.target.value
                  }
                })}
                className="w-full bg-white/10 border border-white/20 rounded px-4 py-2 text-white"
              />
            </div>
          </div>
        </div>

        {/* Business Address */}
        <div className="bg-white/5 border border-white/10 rounded-lg p-6">
          <h2 className="text-lg font-semibold text-white mb-4">Business Address</h2>

          <div className="space-y-4">
            <div>
              <label className="block text-white/80 text-sm mb-2">Street Address</label>
              <input
                type="text"
                value={settings.compliance_data.business_address?.street || ''}
                onChange={(e) => setSettings({
                  ...settings,
                  compliance_data: {
                    ...settings.compliance_data,
                    business_address: {
                      ...settings.compliance_data.business_address!,
                      street: e.target.value
                    }
                  }
                })}
                className="w-full bg-white/10 border border-white/20 rounded px-4 py-2 text-white"
              />
            </div>

            <div className="grid grid-cols-3 gap-4">
              <div>
                <label className="block text-white/80 text-sm mb-2">City</label>
                <input
                  type="text"
                  value={settings.compliance_data.business_address?.city || ''}
                  onChange={(e) => setSettings({
                    ...settings,
                    compliance_data: {
                      ...settings.compliance_data,
                      business_address: {
                        ...settings.compliance_data.business_address!,
                        city: e.target.value
                      }
                    }
                  })}
                  className="w-full bg-white/10 border border-white/20 rounded px-4 py-2 text-white"
                />
              </div>

              <div>
                <label className="block text-white/80 text-sm mb-2">State</label>
                <input
                  type="text"
                  value={settings.compliance_data.business_address?.state || ''}
                  onChange={(e) => setSettings({
                    ...settings,
                    compliance_data: {
                      ...settings.compliance_data,
                      business_address: {
                        ...settings.compliance_data.business_address!,
                        state: e.target.value
                      }
                    }
                  })}
                  className="w-full bg-white/10 border border-white/20 rounded px-4 py-2 text-white"
                  maxLength={2}
                />
              </div>

              <div>
                <label className="block text-white/80 text-sm mb-2">ZIP Code</label>
                <input
                  type="text"
                  value={settings.compliance_data.business_address?.zip || ''}
                  onChange={(e) => setSettings({
                    ...settings,
                    compliance_data: {
                      ...settings.compliance_data,
                      business_address: {
                        ...settings.compliance_data.business_address!,
                        zip: e.target.value
                      }
                    }
                  })}
                  className="w-full bg-white/10 border border-white/20 rounded px-4 py-2 text-white"
                />
              </div>
            </div>
          </div>
        </div>

        {/* Contact Information */}
        <div className="bg-white/5 border border-white/10 rounded-lg p-6">
          <h2 className="text-lg font-semibold text-white mb-4">Contact Information</h2>

          <div className="space-y-4">
            <div>
              <label className="block text-white/80 text-sm mb-2">Contact Email</label>
              <input
                type="email"
                value={settings.compliance_data.contact_email || ''}
                onChange={(e) => setSettings({
                  ...settings,
                  compliance_data: {
                    ...settings.compliance_data,
                    contact_email: e.target.value
                  }
                })}
                className="w-full bg-white/10 border border-white/20 rounded px-4 py-2 text-white"
              />
            </div>

            <div>
              <label className="block text-white/80 text-sm mb-2">Contact Phone</label>
              <input
                type="tel"
                value={settings.compliance_data.contact_phone || ''}
                onChange={(e) => setSettings({
                  ...settings,
                  compliance_data: {
                    ...settings.compliance_data,
                    contact_phone: e.target.value
                  }
                })}
                className="w-full bg-white/10 border border-white/20 rounded px-4 py-2 text-white"
                placeholder="(555) 555-5555"
              />
            </div>
          </div>
        </div>

        {/* Save Button */}
        <div className="flex justify-end">
          <button
            onClick={handleSave}
            disabled={saving}
            className="px-6 py-3 bg-[#0071e3] hover:bg-[#0077ED] text-white font-medium rounded-lg transition-colors disabled:opacity-50"
          >
            {saving ? 'Saving...' : 'Save Settings'}
          </button>
        </div>
      </div>
    </div>
  )
}
```

### Task 4: Service Request Form Component

**File:** `app/components/ServiceRequestForm.tsx`

```typescript
'use client'

import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { X } from 'lucide-react'

interface ServiceProduct {
  id: string
  name: string
  description: string
  meta_data: {
    service_config: {
      test_options: Array<{ id: string; name: string; included: boolean }>
      add_on_tests?: Array<{ id: string; name: string; price: number }>
      required_fields: string[]
      turnaround_days: number
      price: number
    }
  }
}

interface Props {
  onClose: () => void
  onSuccess: () => void
}

export default function ServiceRequestForm({ onClose, onSuccess }: Props) {
  const [step, setStep] = useState(1)
  const [loading, setLoading] = useState(false)
  const [serviceProducts, setServiceProducts] = useState<ServiceProduct[]>([])
  const [selectedProduct, setSelectedProduct] = useState<ServiceProduct | null>(null)

  // Form data
  const [formData, setFormData] = useState({
    product_name: '',
    batch_number: '',
    strain_name: '',
    sample_type: 'Flower',
    sample_weight: '',
    test_types: [] as string[],
    priority: 'standard',
    notes: ''
  })

  useEffect(() => {
    loadServiceProducts()
  }, [])

  const loadServiceProducts = async () => {
    const { data } = await supabase
      .from('products')
      .select('*')
      .eq('type', 'service')
      .eq('status', 'published')

    if (data) setServiceProducts(data as ServiceProduct[])
  }

  const handleSubmit = async () => {
    if (!selectedProduct) return

    setLoading(true)
    try {
      // Get current user and store
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) throw new Error('Not authenticated')

      const { data: platformUser } = await supabase
        .from('platform_users')
        .select('id')
        .eq('auth_id', session.user.id)
        .single()

      const { data: store } = await supabase
        .from('stores')
        .select('id')
        .eq('owner_user_id', platformUser.id)
        .single()

      // Generate order number
      const orderNumber = `REQ-${Date.now()}`

      // Create order
      const { data: order, error: orderError } = await supabase
        .from('orders')
        .insert({
          order_number: orderNumber,
          store_id: store.id,
          platform_user_id: platformUser.id,
          status: 'pending',
          payment_status: 'pending',
          subtotal: selectedProduct.meta_data.service_config.price,
          total_amount: selectedProduct.meta_data.service_config.price,
          metadata: {
            order_type: 'service_request'
          }
        })
        .select()
        .single()

      if (orderError) throw orderError

      // Create order item
      const { error: itemError } = await supabase
        .from('order_items')
        .insert({
          order_id: order.id,
          product_id: selectedProduct.id,
          product_name: selectedProduct.name,
          unit_price: selectedProduct.meta_data.service_config.price,
          quantity: 1,
          line_subtotal: selectedProduct.meta_data.service_config.price,
          line_total: selectedProduct.meta_data.service_config.price,
          fulfillment_status: 'unfulfilled',
          meta_data: {
            item_type: 'service_request',
            service_data: {
              product_name: formData.product_name,
              batch_number: formData.batch_number,
              strain_name: formData.strain_name,
              sample_type: formData.sample_type,
              sample_weight_grams: parseFloat(formData.sample_weight),
              test_types: formData.test_types,
              priority: formData.priority,
              customer_notes: formData.notes
            },
            service_provider: {
              provider_name: 'Quantix Analytics',
              estimated_completion: null
            }
          }
        })

      if (itemError) throw itemError

      onSuccess()
    } catch (err) {
      console.error('Error creating request:', err)
      alert('Error creating request')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/80 flex items-center justify-center z-50 p-4">
      <div className="bg-[#1a1a1a] rounded-lg max-w-2xl w-full max-h-[90vh] overflow-y-auto">
        {/* Header */}
        <div className="sticky top-0 bg-[#1a1a1a] border-b border-white/10 p-6 flex justify-between items-center">
          <div>
            <h2 className="text-xl font-bold text-white">Request Service</h2>
            <p className="text-white/60 text-sm">Step {step} of 3</p>
          </div>
          <button onClick={onClose} className="text-white/60 hover:text-white">
            <X className="w-6 h-6" />
          </button>
        </div>

        {/* Content */}
        <div className="p-6">
          {step === 1 && (
            <div className="space-y-4">
              <h3 className="text-lg font-semibold text-white">Select Service</h3>
              {serviceProducts.map(product => (
                <button
                  key={product.id}
                  onClick={() => {
                    setSelectedProduct(product)
                    setStep(2)
                    // Pre-select included tests
                    setFormData({
                      ...formData,
                      test_types: product.meta_data.service_config.test_options
                        .filter(t => t.included)
                        .map(t => t.id)
                    })
                  }}
                  className="w-full text-left bg-white/5 hover:bg-white/10 border border-white/10 rounded-lg p-4 transition-colors"
                >
                  <div className="flex justify-between items-start">
                    <div>
                      <h4 className="font-semibold text-white">{product.name}</h4>
                      <p className="text-white/60 text-sm mt-1">{product.description}</p>
                      <p className="text-white/40 text-xs mt-2">
                        {product.meta_data.service_config.turnaround_days} day turnaround
                      </p>
                    </div>
                    <div className="text-right">
                      <p className="text-[#0071e3] font-semibold">
                        ${product.meta_data.service_config.price}
                      </p>
                    </div>
                  </div>
                </button>
              ))}
            </div>
          )}

          {step === 2 && selectedProduct && (
            <div className="space-y-6">
              <h3 className="text-lg font-semibold text-white">Sample Details</h3>

              <div>
                <label className="block text-white/80 text-sm mb-2">
                  Product/Sample Name <span className="text-red-400">*</span>
                </label>
                <input
                  type="text"
                  value={formData.product_name}
                  onChange={(e) => setFormData({ ...formData, product_name: e.target.value })}
                  className="w-full bg-white/10 border border-white/20 rounded px-4 py-2 text-white"
                  placeholder="e.g., Blue Razz THCA"
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-white/80 text-sm mb-2">
                    Batch Number <span className="text-red-400">*</span>
                  </label>
                  <input
                    type="text"
                    value={formData.batch_number}
                    onChange={(e) => setFormData({ ...formData, batch_number: e.target.value })}
                    className="w-full bg-white/10 border border-white/20 rounded px-4 py-2 text-white"
                    placeholder="e.g., BT-5521"
                  />
                </div>

                <div>
                  <label className="block text-white/80 text-sm mb-2">Strain Name</label>
                  <input
                    type="text"
                    value={formData.strain_name}
                    onChange={(e) => setFormData({ ...formData, strain_name: e.target.value })}
                    className="w-full bg-white/10 border border-white/20 rounded px-4 py-2 text-white"
                    placeholder="Optional"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-white/80 text-sm mb-2">Sample Type</label>
                  <select
                    value={formData.sample_type}
                    onChange={(e) => setFormData({ ...formData, sample_type: e.target.value })}
                    className="w-full bg-white/10 border border-white/20 rounded px-4 py-2 text-white"
                  >
                    <option value="Flower">Flower</option>
                    <option value="Concentrate">Concentrate</option>
                    <option value="Vape">Vape</option>
                    <option value="Edible">Edible</option>
                    <option value="Pre-Roll">Pre-Roll</option>
                    <option value="Tincture">Tincture</option>
                  </select>
                </div>

                <div>
                  <label className="block text-white/80 text-sm mb-2">
                    Sample Weight (grams) <span className="text-red-400">*</span>
                  </label>
                  <input
                    type="number"
                    step="0.1"
                    value={formData.sample_weight}
                    onChange={(e) => setFormData({ ...formData, sample_weight: e.target.value })}
                    className="w-full bg-white/10 border border-white/20 rounded px-4 py-2 text-white"
                    placeholder="5.0"
                  />
                </div>
              </div>

              <div>
                <label className="block text-white/80 text-sm mb-3">Tests Included</label>
                <div className="space-y-2">
                  {selectedProduct.meta_data.service_config.test_options.map(test => (
                    <label key={test.id} className="flex items-center gap-3">
                      <input
                        type="checkbox"
                        checked={formData.test_types.includes(test.id)}
                        onChange={(e) => {
                          if (e.target.checked) {
                            setFormData({
                              ...formData,
                              test_types: [...formData.test_types, test.id]
                            })
                          } else {
                            setFormData({
                              ...formData,
                              test_types: formData.test_types.filter(t => t !== test.id)
                            })
                          }
                        }}
                        className="w-4 h-4"
                      />
                      <span className="text-white">{test.name}</span>
                    </label>
                  ))}
                </div>
              </div>

              <div>
                <label className="block text-white/80 text-sm mb-2">Notes</label>
                <textarea
                  value={formData.notes}
                  onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
                  className="w-full bg-white/10 border border-white/20 rounded px-4 py-2 text-white h-24"
                  placeholder="Any special instructions..."
                />
              </div>

              <div className="flex gap-3">
                <button
                  onClick={() => setStep(1)}
                  className="px-6 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg"
                >
                  Back
                </button>
                <button
                  onClick={() => setStep(3)}
                  disabled={!formData.product_name || !formData.batch_number || !formData.sample_weight}
                  className="flex-1 px-6 py-2 bg-[#0071e3] hover:bg-[#0077ED] text-white rounded-lg disabled:opacity-50"
                >
                  Continue
                </button>
              </div>
            </div>
          )}

          {step === 3 && selectedProduct && (
            <div className="space-y-6">
              <h3 className="text-lg font-semibold text-white">Review & Submit</h3>

              <div className="bg-white/5 border border-white/10 rounded-lg p-4 space-y-3">
                <div>
                  <p className="text-white/60 text-sm">Service</p>
                  <p className="text-white font-medium">{selectedProduct.name}</p>
                </div>
                <div>
                  <p className="text-white/60 text-sm">Sample</p>
                  <p className="text-white font-medium">
                    {formData.product_name} - Batch {formData.batch_number}
                  </p>
                </div>
                <div>
                  <p className="text-white/60 text-sm">Tests</p>
                  <p className="text-white">{formData.test_types.length} tests selected</p>
                </div>
                <div>
                  <p className="text-white/60 text-sm">Total</p>
                  <p className="text-white font-bold text-lg">
                    ${selectedProduct.meta_data.service_config.price.toFixed(2)}
                  </p>
                </div>
              </div>

              <div className="flex gap-3">
                <button
                  onClick={() => setStep(2)}
                  className="px-6 py-2 bg-white/10 hover:bg-white/20 text-white rounded-lg"
                >
                  Back
                </button>
                <button
                  onClick={handleSubmit}
                  disabled={loading}
                  className="flex-1 px-6 py-2 bg-[#0071e3] hover:bg-[#0077ED] text-white font-medium rounded-lg disabled:opacity-50"
                >
                  {loading ? 'Submitting...' : 'Submit Request'}
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
```

### Task 5: Add to Dashboard

**File:** `app/dashboard/page.tsx`

Add button to header:

```tsx
// Add state
const [showRequestForm, setShowRequestForm] = useState(false)

// Add to header (after Logo, before Sign Out)
<button
  onClick={() => setShowRequestForm(true)}
  className="flex items-center gap-2 px-4 py-2 bg-[#0071e3] hover:bg-[#0077ED] text-white rounded-lg transition-colors"
>
  <Plus className="w-5 h-5" />
  <span className="hidden sm:inline">Request Service</span>
</button>

// Add at end of component
{showRequestForm && (
  <ServiceRequestForm
    onClose={() => setShowRequestForm(false)}
    onSuccess={() => {
      setShowRequestForm(false)
      alert('Service request submitted!')
    }}
  />
)}
```

### Task 6: Orders Page (View Service Requests)

**File:** `app/dashboard/orders/page.tsx`

Create new page to view all orders including service requests.

*I'll provide this in next task - it's a full orders list UI*

### Task 7: API Routes

**File:** `app/api/orders/route.ts`

```typescript
import { NextRequest, NextResponse } from 'next/server'
import { supabase } from '@/lib/supabase'

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url)
  const type = searchParams.get('type') // 'service_request' or 'all'

  try {
    let query = supabase
      .from('orders')
      .select(`
        *,
        order_items (
          *,
          products (name)
        )
      `)
      .order('created_at', { ascending: false })

    if (type === 'service_request') {
      query = query.eq('metadata->>order_type', 'service_request')
    }

    const { data, error } = await query

    if (error) throw error

    return NextResponse.json({ orders: data })
  } catch (error) {
    return NextResponse.json({ error }, { status: 500 })
  }
}

export async function POST(request: NextRequest) {
  // Create order logic here
  // (handled by form for now)
}
```

### Task 8: Testing Checklist

```
□ Run migration: psql < migrations/001_add_service_support.sql
□ Create service products: npx tsx scripts/setup-service-products.ts
□ Test Settings page:
  - Load existing settings
  - Save license number
  - Save business address
□ Test Service Request Form:
  - Select service product
  - Fill sample details
  - Submit request
  - Verify order created in database
□ Test Dashboard:
  - "Request Service" button opens form
  - Form submits successfully
□ Test Complete Workflow:
  - Create request (order with status='pending')
  - Admin updates status to 'confirmed'
  - Admin uploads COA document
  - Link document to order_item
  - Mark order as 'completed'
  - Verify auto-categorization creates product
```

---

## File Structure

```
/Users/f/Desktop/quantix new/
├── migrations/
│   └── 001_add_service_support.sql
├── scripts/
│   └── setup-service-products.ts
├── app/
│   ├── dashboard/
│   │   ├── page.tsx (add Request button)
│   │   ├── settings/
│   │   │   └── page.tsx (new)
│   │   └── orders/
│   │       └── page.tsx (new)
│   ├── components/
│   │   └── ServiceRequestForm.tsx (new)
│   └── api/
│       └── orders/
│           └── route.ts (new)
└── FINAL_IMPLEMENTATION_PLAN.md (this file)
```

---

## Summary

**Zero New Core Tables** - Extends existing orders system
**8 Implementation Tasks** - Clear, sequential steps
**No Confusion** - Every piece documented with exact code

Ready to implement?
