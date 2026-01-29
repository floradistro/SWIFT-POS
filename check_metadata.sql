SELECT 
  s.store_name,
  c.name as category_name,
  c.slug,
  c.metadata->>'category_keywords' as keywords,
  c.metadata->>'matrix_types' as matrix_types,
  c.source_template_id IS NOT NULL as is_from_template
FROM categories c
JOIN stores s ON s.id = c.store_id
WHERE c.store_id IN (
  SELECT DISTINCT store_id FROM store_documents WHERE is_active = true
)
AND c.is_active = true
ORDER BY s.store_name, c.display_order
LIMIT 50;
