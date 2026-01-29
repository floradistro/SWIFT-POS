# General-Purpose Document Categorization System

## Overview
A flexible, platform-level categorization system that works for **any document type** (COAs, invoices, contracts, reports, etc.), not just COAs.

## Key Features

### ✅ **General Purpose**
- Works with any `document_type` (coa, invoice, contract, report, etc.)
- Not hardcoded to COAs only
- Extensible to any use case

### ✅ **Multiple Matching Methods**
The system tries 3 methods in order:

1. **Matrix Type Matching** (for COAs)
   - Uses parsed `data->>'sampleType'` from COA
   - Category has `metadata->>'matrix_types'` array
   - Example: COA with sampleType="Flower - Cured" → Flower category

2. **Keyword Matching** (general purpose)
   - Category has `metadata->>'category_keywords'` array
   - Matches against document_name or product_type
   - Example: Document "Invoice-2024" with keywords `['invoice']` → Invoices category

3. **Document Type Matching** (by file type)
   - Category has `metadata->>'document_types'` array
   - Matches document_type field directly
   - Example: document_type="invoice" → Invoices category

### ✅ **Platform-Level Templates**
- **Quantix COA Matrix Types** catalog (`is_template: true`)
- Stores install template, get their own category copies
- Quantix updates template, stores inherit changes
- Each store can customize after installation

## Database Schema

```sql
catalogs (Platform Templates)
├── id: a176de12-6efd-4ed0-bb90-d2b015791e81
├── name: "Quantix COA Matrix Types"
├── is_template: true
├── is_public: true
└── categories (Template Categories)
    ├── Flower
    │   └── metadata: {
    │         "matrix_types": ["Flower", "Flower - Cured", ...],
    │         "category_keywords": ["flower", "bud", "trim"],
    │         "document_types": ["coa"],
    │         "description": "..."
    │       }
    ├── Concentrates
    ├── Vape Products
    ├── Edibles
    ├── Pre-Rolls
    └── Tinctures & Oils

stores (Individual Store Instances)
└── categories (Store-Specific Copies)
    ├── source_template_id → points to Quantix catalog
    ├── source_template_category_id → points to template category
    └── metadata (inherited from template, can be customized)

store_documents
├── document_type: 'coa' | 'invoice' | 'contract' | etc.
├── data: jsonb (parsed fields like sampleType, matrix, etc.)
├── product_type: text (fallback categorization)
└── product_id → products → primary_category_id → categories
```

## API Functions

### 1. Install Catalog for Store
```sql
SELECT install_quantix_catalog_for_store('store-uuid');
```
Creates store-specific copies of all template categories.

### 2. Auto-Categorize Documents
```sql
-- Categorize all documents for a store
SELECT * FROM auto_categorize_documents('store-uuid');

-- Categorize specific document type
SELECT * FROM auto_categorize_documents('store-uuid', 'coa');

-- Categorize all stores, all document types
SELECT * FROM auto_categorize_documents();
```

## Extending to Other Document Types

### Example: Adding Invoice Categories

```sql
-- 1. Create an "Invoices" catalog template
INSERT INTO catalogs (name, slug, is_template, is_public, vertical)
VALUES ('Business Documents', 'business-documents', true, true, 'general');

-- 2. Add categories
INSERT INTO categories (catalog_id, name, slug, metadata) VALUES
((SELECT id FROM catalogs WHERE slug='business-documents'),
 'Invoices',
 'invoices',
 jsonb_build_object(
   'document_types', ARRAY['invoice', 'bill'],
   'category_keywords', ARRAY['invoice', 'bill', 'payment'],
   'description', 'Customer invoices and bills'
 )),
((SELECT id FROM catalogs WHERE slug='business-documents'),
 'Contracts',
 'contracts',
 jsonb_build_object(
   'document_types', ARRAY['contract', 'agreement'],
   'category_keywords', ARRAY['contract', 'agreement', 'terms'],
   'description', 'Legal contracts and agreements'
 ));

-- 3. Install for a store
SELECT install_quantix_catalog_for_store('store-uuid');

-- 4. Upload documents with document_type='invoice'
-- They will auto-categorize into Invoices category
```

## Use Cases

### 1. **Cannabis Testing Labs** (Current)
- Categories: Flower, Concentrates, Vapes, Edibles, etc.
- Document type: `coa`
- Match by: matrix_types (sampleType field)

### 2. **E-commerce Stores**
- Categories: Product COAs, Compliance Docs, Licenses
- Document types: `coa`, `license`, `compliance`
- Match by: document_types + keywords

### 3. **Accounting Firms**
- Categories: Invoices, Receipts, Tax Documents
- Document types: `invoice`, `receipt`, `tax_form`
- Match by: document_types + keywords

### 4. **Legal Services**
- Categories: Contracts, NDAs, Court Filings
- Document types: `contract`, `nda`, `filing`
- Match by: keywords + document_types

## Benefits

✅ **Not hardcoded** - Fully metadata-driven
✅ **Multi-tenant** - Each store has own categories
✅ **Extensible** - Add new document types without code changes
✅ **Smart matching** - Multiple fallback methods
✅ **Template system** - Share category structures across stores
✅ **Platform maintained** - Quantix controls standards
✅ **Store customizable** - Stores can override/extend

## Current Status

- ✅ Quantix COA catalog created
- ✅ 6 cannabis matrix categories defined
- ✅ Installed for Flora Distro and Saylor MFG
- ✅ Auto-categorization function working
- ✅ Dashboard integration ready
- 🔄 Can be extended to other document types
