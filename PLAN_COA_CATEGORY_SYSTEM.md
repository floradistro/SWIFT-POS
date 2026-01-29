# Plan: COA Category System for Dashboard

## Problem
- Dashboard showing "Other" (295 COAs) which shouldn't be an option
- Categories are guessed from document names, not configured properly
- Need backend category configuration like e-commerce sites
- Need to parse actual matrix/sample_type from COA data

## Current Database Schema

### Existing Tables:
1. **`categories`** - Main category table with:
   - `store_id` - links to store
   - `name`, `slug`, `icon`
   - `display_order` - for sorting
   - `parent_id` - for hierarchical categories
   - `is_active`, `featured`
   - `product_count` - auto-updated

2. **`store_documents`** - COA documents with:
   - `product_id` - can link to products table
   - `data` jsonb - contains parsed COA data
   - `data->>'sampleType'` - actual product type from COA

3. **`products`** - Product catalog with:
   - `primary_category_id` - links to categories
   - `store_id`

4. **`product_categories`** - Many-to-many relationship

## Solution Architecture

### Step 1: Create Cannabis Product Categories for Flora Distro
Based on actual COA data patterns, create these categories:
- **Flower** (Flower - Cured, Flower samples)
- **Concentrates** (Badder, Live Resin, Diamonds, Wax, Shatter)
- **Vape Products** (Cartridges, Disposables)
- **Edibles** (Gummies, Cannabis Edibles)
- **Pre-Rolls**

### Step 2: Update store_documents to Link to Categories
- Add `category_id` column to `store_documents` OR
- Create products from documents and link via `product_id`

### Step 3: Populate Categories from Parsed COA Data
- Extract `data->>'sampleType'` from parsed COAs
- Map sample types to categories:
  - "Flower - Cured" → Flower category
  - "Cannabis Badder" → Concentrates category
  - Parse document names for products without parsed data
  - Disposable/Cart in name → Vape Products category

### Step 4: Update Dashboard Logic
- Query categories with COA counts from database
- Filter: `WHERE category_id = ?` instead of `WHERE product_type = ?`
- Remove "Other" - only show configured categories
- If COA has no category, don't show it OR create "Uncategorized" admin-only view

### Step 5: Admin Interface (Future)
- Store owners can create/edit categories
- Drag & drop to reorder
- Set icons, colors, descriptions
- Auto-categorization rules (e.g., "if name contains 'cart' → Vape Products")

## Implementation Steps

1. **Create categories table entries** for Flora Distro store
2. **Add category mapping logic** - either via:
   - Option A: Add `category_id` to `store_documents`
   - Option B: Create `products` from COAs and use existing `product_categories`
3. **Populate category assignments** from parsed COA data
4. **Update dashboard queries** to use categories table
5. **Remove "Other" fallback** from UI

## Database Changes Needed

```sql
-- Option A: Direct category link (simpler)
ALTER TABLE store_documents
ADD COLUMN category_id UUID REFERENCES categories(id);

CREATE INDEX idx_store_documents_category ON store_documents(category_id);

-- Option B: Use existing product system (more robust)
-- Create products from COAs, then use product_categories join table
```

## Benefits
- ✅ Store owners control their own categories
- ✅ Multi-store support (each store has own categories)
- ✅ Hierarchical categories (Concentrates > Badder, Concentrates > Diamonds)
- ✅ Easy to add new categories without code changes
- ✅ Consistent with existing ecommerce product system
- ✅ No more "Other" category
- ✅ Proper category counts and filtering
