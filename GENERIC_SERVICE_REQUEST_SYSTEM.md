# Generic Service Request System - Platform Architecture

## Overview

This is a **generic service request system** that works with the existing **catalog-based platform** (products, categories, catalogs). NOT a traditional ecommerce cart/checkout system.

The platform supports ANY document-based service:
- **Quantix COAs** (current use case - testing services)
- **Legal documents** (future - contracts, filings)
- **Financial reports** (future - audits, statements)
- **Certifications** (future - inspections, compliance)
- **Custom services** (any document generation service)

## Existing Platform Architecture (What We Have)

### Core Tables:
```
platform_users → stores → products → categories → catalogs (templates)
                     ↓
              store_documents
```

### How It Works:
1. **Catalogs** - Platform templates (Quantix COA Matrix Types)
2. **Categories** - Store copies of templates (Flower, Concentrates, Vapes, etc.)
3. **Products** - Items in catalog (auto-generated from documents OR manually created)
4. **Store Documents** - Actual files (COA PDFs) linked to products

**Example Flow:**
- Quantix creates "Cannabis Testing" catalog template
- Store installs template → gets Flower, Concentrates, Vapes categories
- Store uploads COA → auto-categorizes → creates product → links document

## New Generic Service Request System

### Design Principles:
1. **Service-Agnostic** - Works for any document-based service
2. **Catalog-Integrated** - Uses existing products/categories
3. **Multi-Service** - Multiple service types per platform
4. **Template-Driven** - Service config via templates
5. **Store-Isolated** - Multi-tenant safe

---

## Database Schema Extensions

### 1. **SERVICE_TYPES Table** (Platform-Level Service Definitions)

**Purpose:** Define what services the platform offers

```sql
CREATE TABLE service_types (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Service identification
  name TEXT NOT NULL UNIQUE, -- e.g., "Laboratory Testing", "Legal Services", "Accounting"
  slug TEXT NOT NULL UNIQUE, -- e.g., "lab-testing", "legal-services"
  description TEXT,

  -- Categorization
  vertical TEXT, -- 'cannabis', 'peptide', 'legal', 'financial', 'general'
  category TEXT, -- 'testing', 'documentation', 'compliance'

  -- Service configuration
  config JSONB DEFAULT '{}'::jsonb, -- Flexible service-specific settings

  -- Visibility
  is_active BOOLEAN DEFAULT true,
  is_public BOOLEAN DEFAULT true, -- Available to all stores

  -- Icons & branding
  icon TEXT,
  color TEXT,

  -- Metadata
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_service_types_slug ON service_types(slug);
CREATE INDEX idx_service_types_vertical ON service_types(vertical) WHERE vertical IS NOT NULL;
```

**Example Service Types:**

```sql
INSERT INTO service_types (name, slug, vertical, category, config) VALUES

-- Quantix Cannabis Testing
('Cannabis Laboratory Testing', 'cannabis-lab-testing', 'cannabis', 'testing', '{
  "test_options": [
    {"id": "potency", "name": "Potency Analysis", "description": "Cannabinoid profile"},
    {"id": "terpenes", "name": "Terpene Profile", "description": "Full terpene analysis"},
    {"id": "pesticides", "name": "Pesticides", "description": "Pesticide screening"},
    {"id": "heavy_metals", "name": "Heavy Metals", "description": "Heavy metal testing"},
    {"id": "residual_solvents", "name": "Residual Solvents", "description": "Solvent testing"},
    {"id": "microbials", "name": "Microbials", "description": "Microbiological testing"},
    {"id": "mycotoxins", "name": "Mycotoxins", "description": "Mycotoxin screening"}
  ],
  "sample_types": ["Flower", "Concentrate", "Vape", "Edible", "Pre-Roll", "Tincture"],
  "priority_options": [
    {"value": "routine", "label": "Routine", "turnaround_days": 10, "price_multiplier": 1.0},
    {"value": "standard", "label": "Standard", "turnaround_days": 5, "price_multiplier": 1.2},
    {"value": "rush", "label": "Rush", "turnaround_days": 2, "price_multiplier": 1.8}
  ],
  "required_fields": ["batch_number", "sample_weight"],
  "document_type": "coa"
}'::jsonb),

-- Peptide Testing
('Peptide Laboratory Testing', 'peptide-lab-testing', 'peptide', 'testing', '{
  "test_options": [
    {"id": "purity", "name": "Purity Analysis", "description": "HPLC purity testing"},
    {"id": "mass_spec", "name": "Mass Spectrometry", "description": "Molecular weight confirmation"},
    {"id": "sterility", "name": "Sterility Testing", "description": "Microbiological testing"}
  ],
  "sample_types": ["Powder", "Solution", "Lyophilized"],
  "priority_options": [
    {"value": "standard", "label": "Standard", "turnaround_days": 7, "price_multiplier": 1.0},
    {"value": "rush", "label": "Rush", "turnaround_days": 3, "price_multiplier": 1.5}
  ],
  "required_fields": ["cas_number", "sample_quantity"],
  "document_type": "peptide_coa"
}'::jsonb);
```

**Config JSONB Structure:**
- `test_options` - Available tests for this service
- `sample_types` - Types of samples accepted
- `priority_options` - Turnaround time options
- `required_fields` - Fields that must be filled
- `document_type` - What type of document this generates

---

### 2. **SERVICE_REQUESTS Table** (Generic Request System)

**Purpose:** Track any type of service request

```sql
CREATE TABLE service_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Multi-tenancy
  store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,

  -- Service type
  service_type_id UUID NOT NULL REFERENCES service_types(id),

  -- Optional product link (if request is for existing catalog product)
  product_id UUID REFERENCES products(id) ON DELETE SET NULL,

  -- Request identification
  request_number TEXT UNIQUE NOT NULL, -- Format: REQ-{service_slug}-YYYY-###
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN (
    'draft',           -- Being filled out
    'submitted',       -- Sent for processing
    'in_progress',     -- Service provider is working
    'review',          -- Needs review/approval
    'completed',       -- Service completed, document generated
    'cancelled',       -- Request cancelled
    'failed'           -- Service failed
  )),

  -- Request details (flexible per service type)
  request_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  -- Example for COA:
  -- {
  --   "product_name": "Blue Razz THCA",
  --   "batch_number": "BT-5521",
  --   "strain_name": "Blue Razz",
  --   "sample_type": "Concentrate",
  --   "sample_weight_grams": 5.0,
  --   "test_types": ["potency", "terpenes", "pesticides"],
  --   "priority": "standard"
  -- }

  -- Service provider info (optional - for external services)
  provider_name TEXT,
  provider_id TEXT, -- External provider's ID
  provider_metadata JSONB DEFAULT '{}'::jsonb,

  -- Timeline
  estimated_completion_date DATE,
  actual_completion_date DATE,

  -- Results
  result_document_id UUID REFERENCES store_documents(id) ON DELETE SET NULL,
  result_data JSONB DEFAULT '{}'::jsonb, -- Parsed results

  -- Notes
  customer_notes TEXT, -- From store owner
  internal_notes TEXT, -- Private platform notes
  provider_notes TEXT, -- From service provider

  -- Metadata
  metadata JSONB DEFAULT '{}'::jsonb,

  -- Audit
  created_by UUID REFERENCES platform_users(id),
  submitted_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_service_requests_store_id ON service_requests(store_id);
CREATE INDEX idx_service_requests_service_type_id ON service_requests(service_type_id);
CREATE INDEX idx_service_requests_status ON service_requests(status);
CREATE INDEX idx_service_requests_product_id ON service_requests(product_id) WHERE product_id IS NOT NULL;
CREATE INDEX idx_service_requests_created_at ON service_requests(created_at DESC);
CREATE INDEX idx_service_requests_request_number ON service_requests(request_number);
```

**Key Features:**
- **service_type_id** - Links to service definition (COA testing, legal docs, etc.)
- **request_data JSONB** - Flexible structure per service type
- **product_id** - Optional link to catalog product
- **result_document_id** - Links to generated document in store_documents

---

### 3. **REQUEST_STATUS_HISTORY Table** (Audit Trail)

```sql
CREATE TABLE request_status_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  request_id UUID NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,

  from_status TEXT,
  to_status TEXT NOT NULL,

  notes TEXT,
  changed_by UUID REFERENCES platform_users(id),
  changed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

  metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_request_status_history_request_id ON request_status_history(request_id);
CREATE INDEX idx_request_status_history_changed_at ON request_status_history(changed_at DESC);
```

---

### 4. **Extend STORES Table** (Business Profile)

```sql
-- Generic business fields needed for ANY service
ALTER TABLE stores ADD COLUMN IF NOT EXISTS business_name TEXT;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS dba_name TEXT;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS business_address JSONB DEFAULT '{
  "street": "",
  "city": "",
  "state": "",
  "zip": "",
  "country": "USA"
}'::jsonb;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS contact_phone TEXT;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS contact_email TEXT;

-- Service-specific compliance fields (flexible JSONB)
ALTER TABLE stores ADD COLUMN IF NOT EXISTS compliance_data JSONB DEFAULT '{}'::jsonb;
-- Example for cannabis:
-- {
--   "license_number": "...",
--   "license_type": "Manufacturer",
--   "license_state": "CA",
--   "license_expiration": "2025-12-31",
--   "regulatory_agency": "California DCC",
--   "ein": "...",
--   "certifications": [...]
-- }

-- Generic metadata
ALTER TABLE stores ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;
```

**Why JSONB for compliance_data?**
- Different services need different fields
- Cannabis: license number, state, type
- Legal services: bar number, jurisdiction
- Accounting: CPA license, firm registration
- Medical: DEA number, medical license

---

### 5. **Link SERVICE_REQUESTS to STORE_DOCUMENTS**

```sql
-- Add request_id to store_documents (already in design)
ALTER TABLE store_documents ADD COLUMN IF NOT EXISTS request_id UUID REFERENCES service_requests(id) ON DELETE SET NULL;
CREATE INDEX idx_store_documents_request_id ON store_documents(request_id) WHERE request_id IS NOT NULL;
```

**Workflow:**
1. User submits service_request
2. Service provider completes work
3. Document uploaded to store_documents
4. store_documents.request_id links back to service_request
5. Auto-categorization creates/links product
6. Document appears in dashboard

---

## Database Functions

### 1. **Generate Request Number**

```sql
CREATE OR REPLACE FUNCTION generate_request_number(
  store_id_param UUID,
  service_slug TEXT
) RETURNS TEXT AS $$
DECLARE
  year_part TEXT;
  sequence_num INTEGER;
  request_num TEXT;
BEGIN
  year_part := TO_CHAR(NOW(), 'YYYY');

  -- Get next sequence number for this store/service/year
  SELECT COALESCE(MAX(
    CAST(SPLIT_PART(request_number, '-', 4) AS INTEGER)
  ), 0) + 1
  INTO sequence_num
  FROM service_requests
  WHERE store_id = store_id_param
  AND request_number LIKE 'REQ-' || service_slug || '-' || year_part || '-%';

  -- Format: REQ-cannabis-lab-testing-2024-001
  request_num := 'REQ-' || service_slug || '-' || year_part || '-' || LPAD(sequence_num::TEXT, 3, '0');

  RETURN request_num;
END;
$$ LANGUAGE plpgsql;
```

**Examples:**
- `REQ-cannabis-lab-testing-2024-001`
- `REQ-peptide-lab-testing-2024-001`
- `REQ-legal-services-2024-042`

---

## How It Works with Existing Catalog System

### Integration Points:

#### 1. **Products → Service Requests**
```
User browses catalog → Selects product → "Request Service" → Pre-fills form with product info
```

**Example Flow:**
1. User views "Blue Razz THCA" product in Concentrates category
2. Clicks "Request COA for this product"
3. Form pre-fills:
   - Product name: Blue Razz THCA
   - Sample type: Concentrate (from category)
   - Product ID linked
4. User adds batch number, selects tests
5. Submits request

#### 2. **Service Requests → Products** (Reverse)
```
User submits service request → Document generated → Auto-categorization creates product
```

**Example Flow:**
1. User requests COA for "New Strain X" (not in catalog)
2. Request processed → COA PDF generated
3. Document uploaded to store_documents
4. Auto-categorization runs:
   - Creates new product "New Strain X"
   - Assigns to Flower category (based on COA sampleType)
   - Links document to product
5. Product appears in catalog

#### 3. **Categories → Service Types**
```
Categories define what service types they support
```

**Example:**
```sql
-- Category metadata
{
  "supported_service_types": ["cannabis-lab-testing"],
  "matrix_types": ["Flower", "Flower - Cured"],
  "default_tests": ["potency", "terpenes", "pesticides"]
}
```

When user is in "Flower" category and clicks "Request Service", form defaults to:
- Service Type: Cannabis Lab Testing
- Sample Type: Flower
- Pre-selected tests: potency, terpenes, pesticides

---

## UI Components Architecture

### 1. **Service Request Button** (Context-Aware)

**Location:** Dashboard, Product Detail, Category View

**Variants:**

**A. Dashboard Header (Global)**
```tsx
<button onClick={() => showServiceRequestModal()}>
  <Plus /> Request Service
</button>
```
Opens modal with service type selector

**B. Product Detail (Context)**
```tsx
<button onClick={() => showServiceRequestModal(product)}>
  <FileText /> Request COA for this Product
</button>
```
Pre-fills form with product info

**C. Category View (Context)**
```tsx
<button onClick={() => showServiceRequestModal(null, category)}>
  <Plus /> Request Service for {category.name}
</button>
```
Pre-selects service type and sample type based on category

---

### 2. **Service Request Form** (Dynamic)

**Component:** `<ServiceRequestForm serviceType={type} product={product} category={category} />`

**Form Structure (Dynamic based on service_type.config):**

```tsx
// Step 1: Service Type Selection (if not pre-selected)
{!serviceType && (
  <ServiceTypeSelector
    serviceTypes={availableServiceTypes}
    onSelect={setServiceType}
  />
)}

// Step 2: Request Details (dynamic fields from config)
<DynamicFormFields
  fields={serviceType.config.required_fields}
  sampleTypes={serviceType.config.sample_types}
  defaultValues={productDefaults}
/>

// Step 3: Service Options (test types, priority, etc.)
<ServiceOptions
  testOptions={serviceType.config.test_options}
  priorityOptions={serviceType.config.priority_options}
/>

// Step 4: Review & Submit
<RequestReview
  requestData={formData}
  storeInfo={storeSettings}
  onSubmit={handleSubmit}
/>
```

**Example for Cannabis COA:**
```tsx
Step 1: ✓ Cannabis Laboratory Testing (pre-selected from category)
Step 2:
  - Product Name: [input]
  - Batch Number: [input] *Required*
  - Strain Name: [input]
  - Sample Type: [dropdown: Flower, Concentrate, Vape, etc.]
  - Sample Weight: [number] grams *Required*
Step 3:
  - Test Types: [checkboxes: Potency, Terpenes, Pesticides, ...]
  - Priority: [radio: Routine (10 days) | Standard (5 days) | Rush (2 days) +$50]
Step 4:
  - Review all details
  - Validate store settings (license required)
  - Submit
```

---

### 3. **Service Requests Page** (`/dashboard/requests`)

**Layout:**

```tsx
<RequestsPage>
  {/* Filters */}
  <FilterBar>
    <ServiceTypeFilter /> {/* All | Cannabis Testing | Peptide Testing */}
    <StatusFilter /> {/* All | Draft | Submitted | In Progress | Completed */}
    <DateRangeFilter />
    <SearchInput />
  </FilterBar>

  {/* Requests Table */}
  <RequestsTable>
    <columns>
      - Request #
      - Service Type
      - Product/Sample
      - Status
      - Submitted Date
      - Est. Completion
      - Actions
    </columns>
  </RequestsTable>

  {/* Request Detail Modal */}
  <RequestDetailModal>
    - Status timeline
    - Request details (dynamic based on service type)
    - Service provider info
    - Notes/communications
    - Result document (if completed)
    - Actions (cancel, download, add to catalog)
  </RequestDetailModal>
</RequestsPage>
```

---

### 4. **Store Settings Page** (`/dashboard/settings`)

**Sections:**

```tsx
<SettingsPage>
  {/* Business Information (Generic) */}
  <BusinessInfoSection>
    - Store Name
    - Legal Business Name
    - DBA Name
    - Business Address (street, city, state, zip)
    - Contact Phone
    - Contact Email
  </BusinessInfoSection>

  {/* Service-Specific Compliance (Dynamic) */}
  <ComplianceSection>
    {enabledServiceTypes.map(serviceType => (
      <ServiceComplianceFields
        key={serviceType.id}
        serviceType={serviceType}
        fields={serviceType.config.required_compliance_fields}
      />
    ))}
  </ComplianceSection>

  {/* Example for Cannabis Testing */}
  <CannabisCompliance>
    - License Number *Required*
    - License Type: [dropdown]
    - License State: [dropdown]
    - Expiration Date: [date]
  </CannabisCompliance>

  {/* Example for Legal Services */}
  <LegalCompliance>
    - Bar Number *Required*
    - Jurisdiction: [dropdown]
    - Practice Areas: [multi-select]
  </LegalCompliance>
</SettingsPage>
```

---

## API Routes

### Service Types
- `GET /api/service-types` - List available service types
- `GET /api/service-types/[slug]` - Get service type config

### Service Requests
- `GET /api/service-requests` - List requests (filtered by store, service type, status)
- `POST /api/service-requests` - Create new request
- `GET /api/service-requests/[id]` - Get request details
- `PATCH /api/service-requests/[id]` - Update request
- `DELETE /api/service-requests/[id]` - Cancel request
- `POST /api/service-requests/[id]/submit` - Submit draft
- `POST /api/service-requests/[id]/complete` - Mark complete (admin)

### Store Settings
- `GET /api/stores/[storeId]/settings` - Get store settings
- `PUT /api/stores/[storeId]/settings` - Update store settings
- `GET /api/stores/[storeId]/compliance` - Get compliance data
- `PUT /api/stores/[storeId]/compliance` - Update compliance data

---

## Complete Workflow Example: Cannabis COA Request

### 1. **User Browses Catalog**
```
Dashboard → Concentrates category → Sees "Blue Razz THCA" product
```

### 2. **Initiate Request**
```
Clicks "Request COA" → Opens form
Pre-filled:
  - Service Type: Cannabis Lab Testing
  - Product: Blue Razz THCA (linked)
  - Sample Type: Concentrate (from category)
```

### 3. **Fill Details**
```
User adds:
  - Batch Number: BT-5521
  - Sample Weight: 5.0 grams
  - Tests: [✓] Potency, [✓] Terpenes, [✓] Pesticides
  - Priority: Standard (5 days)
  - Notes: "Rush if possible"
```

### 4. **Validate Settings**
```
System checks:
  - Store has license number? ✓
  - Store has business address? ✓
  - Contact email valid? ✓
→ Allow submission
```

### 5. **Submit Request**
```
Generates: REQ-cannabis-lab-testing-2024-001
Status: draft → submitted
Creates status history entry
Request appears in /dashboard/requests
```

### 6. **Lab Processing** (External or Admin)
```
Status: submitted → in_progress
Estimated completion: Jan 25, 2024
Lab receives notification (future: webhook)
```

### 7. **Results Upload**
```
Lab/Admin uploads COA PDF
Creates store_documents entry:
  - file_url: "Blue_Razz_THCA_COA.pdf"
  - document_type: "coa"
  - request_id: links to service_request
  - data: {sampleType: "Concentrate", ...}
```

### 8. **Auto-Categorization**
```
auto_categorize_documents() runs:
  - Finds existing product "Blue Razz THCA"
  - Links document to product (product_id)
  - Assigns to Concentrates category
  - Updates product metadata
```

### 9. **Request Completion**
```
Status: in_progress → completed
result_document_id: links to store_documents
User receives notification (future)
```

### 10. **User Views Result**
```
Dashboard → Concentrates → Blue Razz THCA → COA visible
Requests page → REQ-cannabis-lab-testing-2024-001 → "View COA" button
```

---

## Service Type Examples

### Cannabis Laboratory Testing
```json
{
  "id": "uuid",
  "name": "Cannabis Laboratory Testing",
  "slug": "cannabis-lab-testing",
  "vertical": "cannabis",
  "config": {
    "document_type": "coa",
    "test_options": [...],
    "sample_types": ["Flower", "Concentrate", "Vape", "Edible"],
    "required_compliance_fields": ["license_number", "license_state"]
  }
}
```

### Peptide Testing
```json
{
  "id": "uuid",
  "name": "Peptide Laboratory Testing",
  "slug": "peptide-lab-testing",
  "vertical": "peptide",
  "config": {
    "document_type": "peptide_coa",
    "test_options": [...],
    "sample_types": ["Powder", "Solution", "Lyophilized"],
    "required_fields": ["cas_number", "molecular_weight"]
  }
}
```

### Legal Document Services
```json
{
  "id": "uuid",
  "name": "Legal Document Services",
  "slug": "legal-services",
  "vertical": "legal",
  "config": {
    "document_type": "legal_document",
    "service_options": [
      {"id": "contract", "name": "Contract Drafting"},
      {"id": "filing", "name": "Court Filing"},
      {"id": "compliance", "name": "Compliance Review"}
    ],
    "required_compliance_fields": ["bar_number", "jurisdiction"]
  }
}
```

---

## Summary

This generic service request system:

✅ **Works with existing catalog** (products, categories, catalogs)
✅ **Service-agnostic** (COAs, legal docs, reports, certifications)
✅ **Template-driven** (service types defined in database)
✅ **Multi-tenant safe** (store isolation)
✅ **Flexible** (JSONB for service-specific data)
✅ **Integrated** (auto-categorization links requests → documents → products)
✅ **Extensible** (add new service types without code changes)

**Key Tables:**
- `service_types` - Define available services
- `service_requests` - Track any type of request
- `request_status_history` - Audit trail
- `stores` (extended) - Generic business + compliance fields
- `store_documents` (extended) - Links to requests

**Integration:**
- Products can trigger requests
- Requests create products (via documents)
- Categories support service types
- Existing auto-categorization works seamlessly
