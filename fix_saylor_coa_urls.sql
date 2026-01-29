-- Properly fix Saylor MFG COA URLs by matching actual files to document names
-- Step 1: Create a mapping function that intelligently matches product names

CREATE OR REPLACE FUNCTION match_product_name_to_file(
  doc_name TEXT,
  store_id_param UUID
) RETURNS TEXT AS $$
DECLARE
  matched_file TEXT;
  base_url TEXT := 'https://uaednwpxursknmwdeejn.supabase.co/storage/v1/object/public/vendor-coas/';
BEGIN
  -- Extract key product identifiers from document name
  -- Examples:
  -- "THCA Live Resin Blend Disposable - Blue Razz" -> "Blue_Razz_THCA_Live_Resin_Blend.pdf"
  -- "Cart - 2G - THCA Live Resin Blend - Sour Diesel" -> "Sour_Diesel_THCA_Live_Resin_Blend.pdf"
  -- "THCA Badder - Grape Ape" -> "Grape_Ape_THCA.pdf"
  -- "Delta-9 Gummy - 20mg" -> "Delta_9_Gummy.pdf"

  -- Try to find exact match in storage
  SELECT name INTO matched_file
  FROM storage.objects
  WHERE bucket_id = 'vendor-coas'
  AND name LIKE store_id_param::TEXT || '/%'
  AND name LIKE '%.pdf'
  AND name NOT LIKE '%thumbnail%'
  AND (
    -- Match by extracting strain/product name after the dash
    LOWER(name) LIKE '%' || LOWER(REPLACE(REPLACE(SPLIT_PART(doc_name, ' - ', 2), ' ', '_'), '-', '_')) || '%'
    OR
    -- Match Delta products
    (doc_name ILIKE '%Delta-9%' AND LOWER(name) LIKE '%delta_9%')
    OR
    (doc_name ILIKE '%Delta-8%' AND LOWER(name) LIKE '%delta_8%')
    OR
    -- Match by product type keywords
    (doc_name ILIKE '%Diamonds%' AND LOWER(name) LIKE '%diamonds%')
    OR
    (doc_name ILIKE '%Badder%Grape%Ape%' AND LOWER(name) LIKE '%grape_ape%')
    OR
    (doc_name ILIKE '%Badder%White%Widow%' AND LOWER(name) LIKE '%white_widow%')
  )
  LIMIT 1;

  IF matched_file IS NOT NULL THEN
    RETURN base_url || matched_file;
  END IF;

  -- If no match, return NULL (keep original URL)
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Step 2: Show what would be updated (DRY RUN)
SELECT
  sd.document_name,
  SUBSTRING(sd.file_url FROM '[^/]+\.pdf$') as current_file,
  SUBSTRING(match_product_name_to_file(sd.document_name, sd.store_id) FROM '[^/]+\.pdf$') as matched_file,
  CASE
    WHEN match_product_name_to_file(sd.document_name, sd.store_id) IS NOT NULL THEN 'WILL UPDATE'
    ELSE 'NO MATCH - KEEP ORIGINAL'
  END as action
FROM store_documents sd
WHERE sd.store_id = '34b4d151-ef86-4d27-a2d9-ba6921afd545'
AND sd.is_active = true
ORDER BY action DESC, sd.document_name
LIMIT 50;
