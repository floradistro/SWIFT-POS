# COA Request System & Store Account Details - Design Document

## Overview

Adding two interconnected features:
1. **Store Account Details** - License numbers, addresses, contact info for COA submissions
2. **COA Request System** - Request new COAs for products, track status, manage submissions

## Current System Analysis

### What Exists:
- ✅ Multi-tenant store system
- ✅ Document management (COAs stored as PDFs)
- ✅ Product catalog with auto-categorization
- ✅ Dashboard for viewing COAs
- ✅ User authentication via Supabase

### What's Missing:
- ❌ Store profile fields (license, address, contact)
- ❌ COA request workflow
- ❌ Request tracking system
- ❌ Store settings page

## Database Schema Changes

### 1. Update `stores` Table

Add new fields for account details:

```sql
ALTER TABLE stores ADD COLUMN IF NOT EXISTS license_number TEXT;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS license_type TEXT;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS license_state TEXT;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS license_expiration DATE;

-- Business address as JSONB
ALTER TABLE stores ADD COLUMN IF NOT EXISTS business_address JSONB DEFAULT '{
  "street": "",
  "city": "",
  "state": "",
  "zip": "",
  "country": "USA"
}'::jsonb;

-- Contact information
ALTER TABLE stores ADD COLUMN IF NOT EXISTS contact_phone TEXT;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS contact_email TEXT;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS business_name TEXT; -- Legal name
ALTER TABLE stores ADD COLUMN IF NOT EXISTS dba_name TEXT; -- Doing Business As

-- Additional metadata
ALTER TABLE stores ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;
```

**Metadata fields (flexible JSONB):**
- `ein` - Employer Identification Number
- `state_registration_number`
- `regulatory_agency` - e.g., "California DCC"
- `business_type` - e.g., "Manufacturer", "Distributor", "Retailer"
- `certifications` - Array of certifications

### 2. Create `coa_requests` Table

Track COA requests from submission to completion:

```sql
CREATE TABLE coa_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  product_id UUID REFERENCES products(id) ON DELETE SET NULL,

  -- Request details
  request_number TEXT UNIQUE NOT NULL, -- e.g., "REQ-2024-001"
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN (
    'draft',           -- Being filled out
    'submitted',       -- Sent to lab
    'in_progress',     -- Lab is testing
    'completed',       -- COA received
    'cancelled',       -- Request cancelled
    'failed'           -- Testing failed
  )),

  -- Sample information
  product_name TEXT NOT NULL,
  batch_number TEXT,
  strain_name TEXT,
  sample_type TEXT, -- 'Flower', 'Concentrate', 'Vape', 'Edible', etc.

  -- Test types requested (array)
  test_types TEXT[] DEFAULT ARRAY[]::TEXT[], -- e.g., ['potency', 'pesticides', 'heavy_metals', 'terpenes']

  -- Priority
  priority TEXT DEFAULT 'standard' CHECK (priority IN ('rush', 'standard', 'routine')),
  rush_fee_approved BOOLEAN DEFAULT false,

  -- Lab information
  lab_name TEXT,
  lab_id TEXT, -- External lab's ID for this sample
  estimated_completion_date DATE,
  actual_completion_date DATE,

  -- Results
  result_document_id UUID REFERENCES store_documents(id) ON DELETE SET NULL,
  result_file_url TEXT, -- URL to COA PDF when completed

  -- Metadata
  sample_received_date DATE,
  sample_weight_grams DECIMAL(10, 3),
  notes TEXT,
  internal_notes TEXT, -- Private notes not shared with lab
  metadata JSONB DEFAULT '{}'::jsonb,

  -- Timestamps
  submitted_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_by UUID REFERENCES platform_users(id),

  -- Indexes
  CONSTRAINT unique_request_number UNIQUE (request_number)
);

CREATE INDEX idx_coa_requests_store_id ON coa_requests(store_id);
CREATE INDEX idx_coa_requests_status ON coa_requests(status);
CREATE INDEX idx_coa_requests_product_id ON coa_requests(product_id) WHERE product_id IS NOT NULL;
CREATE INDEX idx_coa_requests_created_at ON coa_requests(created_at DESC);
```

### 3. Create `request_status_history` Table

Track status changes over time:

```sql
CREATE TABLE request_status_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  request_id UUID NOT NULL REFERENCES coa_requests(id) ON DELETE CASCADE,

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

### 4. Add Request Link to `store_documents`

Track which request generated a COA:

```sql
ALTER TABLE store_documents ADD COLUMN IF NOT EXISTS request_id UUID REFERENCES coa_requests(id) ON DELETE SET NULL;
CREATE INDEX idx_store_documents_request_id ON store_documents(request_id) WHERE request_id IS NOT NULL;
```

## User Interface Components

### 1. Store Settings Page (`/dashboard/settings`)

**Route:** `/app/dashboard/settings/page.tsx`

**Sections:**

#### A. Account Information
```
Store Name: [input]
Legal Business Name: [input]
DBA Name: [input]
```

#### B. License Information
```
License Number: [input] *Required*
License Type: [dropdown: Manufacturer, Distributor, Retailer, Testing Lab]
State: [dropdown: CA, CO, OR, WA, etc.]
Expiration Date: [date picker]
```

#### C. Business Address
```
Street Address: [input]
City: [input]
State: [dropdown]
ZIP Code: [input]
Country: [input, default: USA]
```

#### D. Contact Information
```
Contact Email: [input]
Contact Phone: [input with formatting: (555) 555-5555]
```

#### E. Additional Details (Optional)
```
EIN: [input]
State Registration Number: [input]
Regulatory Agency: [input]
Business Type: [dropdown]
```

**Validation:**
- License Number required before submitting COA requests
- Email validation
- Phone number formatting
- ZIP code validation

### 2. Request COA Button (Dashboard)

Add to `/app/dashboard/page.tsx`:

**Location:** Sticky header next to "Sign Out" button

```tsx
<button className="btn-primary">
  <Plus className="w-5 h-5" />
  Request COA
</button>
```

**Opens:** Modal or slide-over panel with request form

### 3. COA Request Form Component

**Component:** `/app/components/COARequestForm.tsx`

**Form Fields:**

#### Step 1: Product Information
```
Product Name: [input] *Required*
Batch Number: [input]
Strain Name: [input] (if applicable)
Sample Type: [dropdown: Flower, Concentrate, Vape, Edible, etc.]
Sample Weight: [number input] grams
```

#### Step 2: Test Types
```
☐ Potency Analysis (Cannabinoids)
☐ Terpene Profile
☐ Pesticides
☐ Heavy Metals
☐ Residual Solvents
☐ Microbials
☐ Mycotoxins
☐ Water Activity
☐ Moisture Content
☐ Foreign Material
```

#### Step 3: Priority & Notes
```
Priority:
  ○ Routine (7-10 days)
  ○ Standard (3-5 days)
  ○ Rush (24-48 hours) +$50

Notes: [textarea]
```

#### Step 4: Review & Submit
```
[Summary card showing all details]

Store Information:
- Business Name: [from store settings]
- License: [from store settings]
- Address: [from store settings]

[Warning if store settings incomplete]

[Save as Draft] [Submit Request]
```

### 4. COA Requests Page (`/dashboard/requests`)

**Route:** `/app/dashboard/requests/page.tsx`

**Layout:**

#### Header
```
COA Requests (24)     [+ New Request]
```

#### Filter Bar
```
Status: [All | Draft | Submitted | In Progress | Completed | Cancelled]
Date Range: [Last 30 days ▼]
Search: [Search by product, batch, request #]
```

#### Request List (Table View)

| Request # | Product | Batch | Status | Tests | Submitted | Est. Completion | Actions |
|-----------|---------|-------|--------|-------|-----------|----------------|---------|
| REQ-2024-001 | Blue Razz THCA | BT-5521 | ✅ Completed | 5 tests | Jan 15 | Jan 22 | [View COA] |
| REQ-2024-002 | Sour Diesel | BT-5522 | 🔄 In Progress | 3 tests | Jan 20 | Jan 25 | [View Status] |
| REQ-2024-003 | King Louis | BT-5523 | 📝 Draft | 4 tests | - | - | [Continue] [Delete] |

**Status Icons:**
- 📝 Draft - Yellow
- 📤 Submitted - Blue
- 🔄 In Progress - Purple
- ✅ Completed - Green
- ❌ Cancelled - Gray
- ⚠️ Failed - Red

**Click Row → Opens detail modal**

### 5. Request Detail Modal

**Shows:**
- Request number & status timeline
- Product information
- Test types requested
- Lab information
- Status history (with timestamps)
- Notes
- COA file (if completed)

**Actions:**
- [Download COA] (if completed)
- [Add to Dashboard] (link to store_documents)
- [Cancel Request] (if not completed)
- [Contact Lab]

## API Routes

### 1. Store Settings API

**GET `/api/stores/[storeId]/settings`**
- Returns store account details
- Auth: Must own store

**PUT `/api/stores/[storeId]/settings`**
- Updates store account details
- Validates license number, email, phone
- Auth: Must own store

### 2. COA Requests API

**GET `/api/coa-requests`**
- List all requests for user's stores
- Query params: `?status=submitted&store_id=xxx`
- Auth: User must own store

**POST `/api/coa-requests`**
- Create new request (draft or submitted)
- Body: Request details
- Returns: Created request object
- Auth: User must own store

**GET `/api/coa-requests/[requestId]`**
- Get single request details
- Includes status history
- Auth: User must own store

**PATCH `/api/coa-requests/[requestId]`**
- Update request (status, notes, etc.)
- Body: Fields to update
- Auth: User must own store

**DELETE `/api/coa-requests/[requestId]`**
- Cancel/delete request
- Only if status is 'draft' or 'submitted'
- Auth: User must own store

**POST `/api/coa-requests/[requestId]/submit`**
- Change status from 'draft' to 'submitted'
- Validates store settings are complete
- Creates status history entry
- Auth: User must own store

### 3. Request Number Generation

**Function:** `generate_request_number(store_id UUID) RETURNS TEXT`

```sql
CREATE OR REPLACE FUNCTION generate_request_number(store_id_param UUID)
RETURNS TEXT AS $$
DECLARE
  year_part TEXT;
  sequence_num INTEGER;
  request_num TEXT;
BEGIN
  year_part := TO_CHAR(NOW(), 'YYYY');

  -- Get next sequence number for this store/year
  SELECT COALESCE(MAX(
    CAST(SPLIT_PART(request_number, '-', 3) AS INTEGER)
  ), 0) + 1
  INTO sequence_num
  FROM coa_requests
  WHERE store_id = store_id_param
  AND request_number LIKE 'REQ-' || year_part || '-%';

  -- Format: REQ-2024-001
  request_num := 'REQ-' || year_part || '-' || LPAD(sequence_num::TEXT, 3, '0');

  RETURN request_num;
END;
$$ LANGUAGE plpgsql;
```

## User Flows

### Flow 1: First-Time Setup

1. User logs into dashboard
2. Clicks "Request COA" button
3. **Blocked** → Modal shows: "Complete your store settings first"
4. Redirected to `/dashboard/settings`
5. Fills out license, address, contact info
6. Saves settings
7. Success message: "Settings saved! You can now request COAs"
8. Returns to dashboard

### Flow 2: Submit COA Request

1. User clicks "Request COA" button
2. Request form modal opens
3. Fills out product details (Step 1)
4. Selects test types (Step 2)
5. Chooses priority & adds notes (Step 3)
6. Reviews summary (Step 4)
   - Store info auto-populated from settings
7. Clicks "Save as Draft" OR "Submit Request"
8. If submitted:
   - Request number generated: REQ-2024-001
   - Status set to 'submitted'
   - Status history entry created
   - Email notification sent (future)
9. Success message: "Request submitted! Track it in the Requests page"
10. Redirected to `/dashboard/requests`

### Flow 3: Track Request Status

1. User navigates to `/dashboard/requests`
2. Sees list of all requests
3. Filters by status: "In Progress"
4. Clicks on request row
5. Detail modal opens showing:
   - Status timeline
   - Sample information
   - Test types
   - Estimated completion: Jan 25
6. (Later) Lab updates status to 'completed'
7. User receives notification (future)
8. COA PDF available for download
9. User clicks "Add to Dashboard"
10. COA appears in main dashboard under appropriate category

### Flow 4: Complete Request (Admin/Lab Integration)

**Future Enhancement:**
1. Lab integration webhook receives test completion
2. POST `/api/webhooks/lab-results`
3. Updates request status to 'completed'
4. Uploads COA PDF to Supabase Storage
5. Creates `store_documents` entry
6. Links document to request
7. Auto-categorizes COA
8. Sends notification to user

## Validation Rules

### Store Settings:
- License Number: Required before submitting requests
- License State: Must match business address state
- Email: Valid email format
- Phone: Valid US phone format (optional)

### COA Requests:
- Product Name: Required, max 200 chars
- Sample Type: Required, must match predefined list
- Test Types: At least 1 test type required
- Batch Number: Optional but recommended
- Rush requests: Requires explicit approval checkbox

## Dashboard Integration

### Add to Main Dashboard:

1. **Request COA button** in header
2. **Pending Requests badge** (count of submitted/in-progress)
3. **Settings link** in dropdown menu
4. **Requests page** in navigation

Example header update:
```tsx
<div className="flex items-center gap-4">
  <button onClick={() => setShowRequestForm(true)}>
    <Plus className="w-5 h-5" />
    Request COA
  </button>

  {pendingRequestsCount > 0 && (
    <Link href="/dashboard/requests">
      <span className="badge">{pendingRequestsCount} pending</span>
    </Link>
  )}

  <DropdownMenu>
    <Link href="/dashboard/settings">Settings</Link>
    <Link href="/dashboard/requests">Requests</Link>
    <button onClick={handleLogout}>Sign Out</button>
  </DropdownMenu>
</div>
```

## Future Enhancements

1. **Lab Integration**
   - Webhook endpoints for status updates
   - Automatic COA upload
   - Real-time status tracking

2. **Notifications**
   - Email when request status changes
   - In-app notifications
   - SMS alerts for rush requests

3. **Analytics**
   - Average turnaround time
   - Cost tracking
   - Test type frequency

4. **Batch Requests**
   - Submit multiple samples at once
   - Bulk pricing

5. **Lab Selection**
   - Choose from multiple lab partners
   - Compare pricing and turnaround times

6. **Compliance Features**
   - Automatic license expiration warnings
   - Required test frequency tracking
   - Regulatory reporting

## Implementation Priority

### Phase 1 (MVP):
1. ✅ Database migrations (stores fields + coa_requests table)
2. ✅ Store Settings page
3. ✅ COA Request form component
4. ✅ API routes for CRUD operations
5. ✅ Requests listing page
6. ✅ Dashboard integration (button + navigation)

### Phase 2 (Enhanced):
1. Status update workflow
2. Email notifications
3. Request detail modal
4. Advanced filtering/search
5. Request analytics

### Phase 3 (Advanced):
1. Lab integration webhooks
2. Multiple lab support
3. Batch requests
4. Cost tracking
5. Compliance features

## Technical Stack

- **Frontend:** Next.js 14, React, TypeScript, Tailwind CSS
- **Backend:** Next.js API Routes
- **Database:** PostgreSQL (Supabase)
- **Storage:** Supabase Storage (for COA PDFs)
- **Auth:** Supabase Auth
- **Forms:** React Hook Form + Zod validation
- **UI Components:** Radix UI or shadcn/ui

## Summary

This design provides:
1. **Complete store profile management** with all fields needed for COA submissions
2. **Full request lifecycle** from draft → submitted → in progress → completed
3. **Request tracking system** with status history
4. **Clean UI integration** with existing dashboard
5. **Future-proof architecture** for lab integrations and advanced features

The system maintains separation of concerns:
- Store account details live in `stores` table
- Request workflow in dedicated `coa_requests` table
- Completed COAs link back to `store_documents`
- Auto-categorization continues to work on new COAs

Ready to start implementation?
