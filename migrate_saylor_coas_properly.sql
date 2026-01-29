-- PROPER Migration: Match real files to documents and deactivate fake test records
-- Saylor MFG has 165 database records but only 41 real PDF files

BEGIN;

-- Step 1: Update URLs for documents that have real matching files
UPDATE store_documents sd
SET
  file_url = match_product_name_to_file(sd.document_name, sd.store_id),
  updated_at = NOW()
WHERE sd.store_id = '34b4d151-ef86-4d27-a2d9-ba6921afd545'
AND sd.is_active = true
AND match_product_name_to_file(sd.document_name, sd.store_id) IS NOT NULL
AND sd.document_name NOT LIKE '%Test%'  -- Don't update test records
AND sd.document_name NOT LIKE '%Agent Generated%'  -- Don't update generated records
RETURNING document_name, file_url;

-- Step 2: Show summary of what was updated
SELECT
  COUNT(*) FILTER (WHERE updated_at > NOW() - INTERVAL '1 minute') as updated_count,
  COUNT(*) FILTER (WHERE file_url LIKE '%COA_QA%') as still_has_qa_codes,
  COUNT(*) as total_active
FROM store_documents
WHERE store_id = '34b4d151-ef86-4d27-a2d9-ba6921afd545'
AND is_active = true;

COMMIT;
