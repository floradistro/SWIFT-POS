import { createClient } from '@supabase/supabase-js'
import { NextResponse } from 'next/server'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const SQL = `
CREATE OR REPLACE FUNCTION auto_categorize_documents(
  target_store_id UUID DEFAULT NULL,
  target_document_type TEXT DEFAULT NULL
)
RETURNS TABLE (
  store_name TEXT,
  total_docs BIGINT,
  categorized BIGINT,
  success_rate NUMERIC
) AS $$
DECLARE
  doc RECORD;
  category_rec RECORD;
  matched BOOLEAN;
  new_product_id UUID;
  product_slug TEXT;
  category_to_use UUID;
  docs_processed INT := 0;
  docs_categorized INT := 0;
  slug_suffix INT;
BEGIN
  FOR doc IN
    SELECT sd.*, s.store_name
    FROM store_documents sd
    JOIN stores s ON s.id = sd.store_id
    WHERE sd.is_active = true
    AND sd.product_id IS NULL
    AND (target_store_id IS NULL OR sd.store_id = target_store_id)
    AND (target_document_type IS NULL OR sd.document_type = target_document_type)
    ORDER BY sd.created_at DESC
  LOOP
    docs_processed := docs_processed + 1;
    matched := false;
    category_to_use := NULL;

    FOR category_rec IN
      SELECT c.*
      FROM categories c
      WHERE c.store_id = doc.store_id
      AND c.is_active = true
      ORDER BY
        CASE WHEN c.source_template_id IS NOT NULL THEN 0 ELSE 1 END,
        c.display_order
    LOOP
      -- Method 1: Keyword matching
      IF category_rec.metadata ? 'category_keywords' THEN
        IF EXISTS (
          SELECT 1
          FROM jsonb_array_elements_text(category_rec.metadata->'category_keywords') keyword
          WHERE LOWER(doc.document_name) LIKE '%' || LOWER(keyword) || '%'
             OR LOWER(COALESCE(doc.product_type, '')) LIKE '%' || LOWER(keyword) || '%'
        ) THEN
          matched := true;
          category_to_use := category_rec.id;
          EXIT;
        END IF;
      END IF;

      -- Method 2: Matrix type matching
      IF doc.data ? 'sampleType' AND category_rec.metadata ? 'matrix_types' THEN
        IF EXISTS (
          SELECT 1
          FROM jsonb_array_elements_text(category_rec.metadata->'matrix_types') matrix_type
          WHERE LOWER(doc.data->>'sampleType') = LOWER(matrix_type)
             OR LOWER(doc.data->>'sampleType') LIKE '%' || LOWER(matrix_type) || '%'
        ) THEN
          matched := true;
          category_to_use := category_rec.id;
          EXIT;
        END IF;
      END IF;

      -- Method 3: Document type matching
      IF category_rec.metadata ? 'document_types' THEN
        IF EXISTS (
          SELECT 1
          FROM jsonb_array_elements_text(category_rec.metadata->'document_types') doc_type
          WHERE doc.document_type = doc_type
        ) THEN
          matched := true;
          category_to_use := category_rec.id;
          EXIT;
        END IF;
      END IF;
    END LOOP;

    IF matched AND category_to_use IS NOT NULL THEN
      BEGIN
        -- Generate base slug
        product_slug := LOWER(REGEXP_REPLACE(
          doc.document_name || '-' || SUBSTRING(doc.id::TEXT, 1, 8),
          '[^a-z0-9]+', '-', 'g'
        ));

        -- Make slug unique by adding suffix if needed
        slug_suffix := 0;
        WHILE EXISTS (SELECT 1 FROM products WHERE slug = product_slug || CASE WHEN slug_suffix > 0 THEN '-' || slug_suffix::TEXT ELSE '' END) LOOP
          slug_suffix := slug_suffix + 1;
        END LOOP;

        IF slug_suffix > 0 THEN
          product_slug := product_slug || '-' || slug_suffix::TEXT;
        END IF;

        -- Create product
        INSERT INTO products (
          store_id, name, slug, sku, primary_category_id,
          inventory_quantity, manage_inventory, is_active,
          visibility, type
        ) VALUES (
          doc.store_id,
          doc.document_name,
          product_slug,
          'DOC-' || SUBSTRING(doc.id::TEXT, 1, 8) || CASE WHEN slug_suffix > 0 THEN '-' || slug_suffix::TEXT ELSE '' END,
          category_to_use,
          1, false, true,
          'public', 'physical'
        )
        RETURNING id INTO new_product_id;

        -- Link document to product
        UPDATE store_documents
        SET product_id = new_product_id,
            updated_at = NOW()
        WHERE id = doc.id;

        -- Add to product_categories junction table
        INSERT INTO product_categories (product_id, category_id, is_primary)
        VALUES (new_product_id, category_to_use, true)
        ON CONFLICT (product_id, category_id) DO NOTHING;

        docs_categorized := docs_categorized + 1;

      EXCEPTION
        WHEN OTHERS THEN
          RAISE WARNING 'Error categorizing % (ID: %): %', doc.document_name, doc.id, SQLERRM;
          CONTINUE;
      END;
    END IF;
  END LOOP;

  RETURN QUERY
  SELECT
    s.store_name,
    COUNT(sd.id) as total_docs,
    COUNT(sd.product_id) as categorized,
    ROUND((COUNT(sd.product_id)::NUMERIC / NULLIF(COUNT(sd.id), 0) * 100), 1) as success_rate
  FROM stores s
  JOIN store_documents sd ON sd.store_id = s.id
  WHERE sd.is_active = true
    AND (target_store_id IS NULL OR s.id = target_store_id)
    AND (target_document_type IS NULL OR sd.document_type = target_document_type)
  GROUP BY s.id, s.store_name
  ORDER BY s.store_name;
END;
$$ LANGUAGE plpgsql;
`

export async function POST() {
  try {
    console.log('Updating auto_categorize_documents function...')

    const { error } = await supabase.rpc('exec_sql', { sql: SQL })

    if (error) {
      console.error('Error updating function:', error)
      return NextResponse.json({ error: error.message }, { status: 500 })
    }

    return NextResponse.json({
      success: true,
      message: 'Function updated successfully'
    })
  } catch (error: any) {
    console.error('Unexpected error:', error)
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
