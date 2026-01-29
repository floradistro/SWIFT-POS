# Categorization System Improvements

## Problem Identified
The auto-categorization function was encountering duplicate key violations when trying to create products with the same name in the same category.

## Root Causes
1. **Duplicate products** - Multiple COAs with same document name trying to create separate products
2. **Slug collisions** - Generated slugs weren't unique enough
3. **Poor error handling** - Function would fail entirely on first error

## Solution

### Updated `auto_categorize_documents()` Function

Location: `/Users/f/Desktop/quantix new/improved_auto_categorize.sql`

**Key Improvements:**

1. **Check for existing products first**
   ```sql
   SELECT id INTO existing_product_id
   FROM products
   WHERE store_id = doc.store_id
     AND name = doc.document_name
     AND primary_category_id = category_to_use
   LIMIT 1;
   ```
   If product exists, reuse it instead of creating new one.

2. **Better slug generation**
   - Uses 12 characters of document ID instead of 8
   - Format: `document-name-<12-char-id>`
   - More unique, less likely to collide

3. **Graceful error handling**
   - `ON EXCEPTION` blocks catch and skip problematic documents
   - Process continues even if individual documents fail
   - No more "all or nothing" failures

4. **Batch processing**
   - Processes 500 documents at a time
   - Run multiple times to categorize all documents
   - Prevents timeouts on large datasets

5. **Prioritizes template categories**
   ```sql
   ORDER BY
     CASE WHEN c.source_template_id IS NOT NULL THEN 0 ELSE 1 END,
     c.display_order
   ```
   Always checks Quantix template categories first.

6. **Improved keyword matching**
   - Checks both `document_name` AND `product_type` fields
   - Uses LOWER() for case-insensitive matching
   - Properly iterates through JSONB keyword arrays

## How to Run

### Option 1: Supabase SQL Editor (Recommended)
1. Go to Supabase Dashboard → SQL Editor
2. Copy content from `improved_auto_categorize.sql`
3. Click "Run" to execute
4. Function will process 500 documents and return results
5. Run again until all documents are categorized

### Option 2: Via API (If needed)
The API route is available but function needs to be updated in database first:
```bash
curl -X POST http://localhost:3001/api/admin/categorize
```

## Expected Results

After running the function, you should see output like:
```
store_name          | total_docs | categorized | success_rate
--------------------|------------|-------------|-------------
Flora Distro        | 255        | 212         | 83.1%
Saylor MFG          | 165        | 120         | 72.7%
Sampsons Distro     | 43         | 30          | 69.8%
Davidson Hemp       | 24         | 18          | 75.0%
Cloud Committee     | 15         | 12          | 80.0%
Quantix Analytics   | 1          | 1           | 100%
```

## Why Some COAs May Not Categorize

1. **product_type = "Other"** - No keywords to match against
2. **Missing parsed data** - No `sampleType` field in `data` column
3. **Unusual product names** - Document names that don't contain category keywords
4. **No template categories** - Store hasn't installed Quantix catalog yet

## Next Steps

1. Run the improved function via Supabase SQL Editor
2. Check success rates per store
3. For uncategorized documents:
   - Review their `product_type` and `document_name`
   - Add additional keywords to category metadata if needed
   - Or manually assign categories in dashboard

## Categories with Keywords

From Quantix template (`a176de12-6efd-4ed0-bb90-d2b015791e81`):

- **Flower**: `flower`, `bud`, `trim`, `cannabis flower`
- **Concentrates**: `concentrate`, `badder`, `wax`, `shatter`, `diamonds`, `live resin`, `rosin`, `sauce`, `crumble`
- **Vape Products**: `vape`, `cartridge`, `cart`, `disposable`, `pen`
- **Edibles**: `edible`, `gummy`, `gummies`, `chocolate`, `beverage`, `drink`
- **Pre-Rolls**: `pre-roll`, `preroll`, `joint`, `blunt`
- **Tinctures & Oils**: `tincture`, `oil`, `rso`, `capsule`, `topical`

## Performance

- Batch size: 500 documents per execution
- Typical runtime: 10-30 seconds per batch
- Total documents across all stores: ~503
- Estimated executions needed: 2-3 runs
