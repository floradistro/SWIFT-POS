-- Test keyword matching for a specific COA to debug why it's not matching
-- Test case: "THCA Badder - Grape Ape" should match "Concentrates" category

-- 1. Check what categories exist for Saylor MFG store
SELECT
  c.id,
  c.name,
  c.slug,
  c.is_active,
  c.source_template_id IS NOT NULL as from_template,
  c.metadata->>'category_keywords' as keywords,
  c.metadata->>'matrix_types' as matrix_types
FROM categories c
JOIN stores s ON s.id = c.store_id
WHERE s.store_name = 'Saylor MFG'
AND c.is_active = true
ORDER BY
  CASE WHEN c.source_template_id IS NOT NULL THEN 0 ELSE 1 END,
  c.display_order;

-- 2. Check the specific COA details
SELECT
  sd.id,
  sd.document_name,
  sd.product_type,
  sd.data->>'sampleType' as sample_type,
  sd.product_id,
  s.store_name
FROM store_documents sd
JOIN stores s ON s.id = sd.store_id
WHERE sd.document_name = 'THCA Badder - Grape Ape'
LIMIT 1;

-- 3. Test if keyword "badder" would match against "THCA Badder - Grape Ape"
SELECT
  'THCA Badder - Grape Ape' as document_name,
  'Badder' as product_type,
  LOWER('THCA Badder - Grape Ape') LIKE '%' || LOWER('badder') || '%' as name_match,
  LOWER('Badder') LIKE '%' || LOWER('badder') || '%' as product_type_match;

-- 4. Test all keywords from Concentrates category against the document
WITH keywords AS (
  SELECT jsonb_array_elements_text(c.metadata->'category_keywords') as keyword
  FROM categories c
  JOIN stores s ON s.id = c.store_id
  WHERE s.store_name = 'Saylor MFG'
  AND c.name = 'Concentrates'
  AND c.is_active = true
  LIMIT 1
)
SELECT
  keyword,
  LOWER('THCA Badder - Grape Ape') LIKE '%' || LOWER(keyword) || '%' as matches_name,
  LOWER('Badder') LIKE '%' || LOWER(keyword) || '%' as matches_product_type
FROM keywords;
