-- Check a specific uncategorized COA to debug why it's not matching
SELECT 
  sd.id,
  sd.document_name,
  sd.product_type,
  sd.data->>'sampleType' as sample_type,
  -- Check what categories exist for this store
  (SELECT json_agg(json_build_object(
    'name', c.name,
    'keywords', c.metadata->'category_keywords',
    'matrix_types', c.metadata->'matrix_types'
  ))
  FROM categories c 
  WHERE c.store_id = sd.store_id 
  AND c.is_active = true
  AND c.source_template_id IS NOT NULL
  ) as available_categories
FROM store_documents sd
WHERE sd.document_name = 'THCA Badder - Grape Ape'
AND sd.is_active = true
LIMIT 1;
