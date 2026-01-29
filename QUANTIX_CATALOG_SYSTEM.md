# Quantix Platform COA Catalog System

## Overview
A platform-level catalog system where Quantix provides **standardized categories based on COA matrix types** that all stores can use.

## Architecture

### 1. **Quantix Platform Catalog** (Template)
- **Catalog**: `Quantix COA Matrix Types` (ID: `a176de12-6efd-4ed0-bb90-d2b015791e81`)
- **is_template**: `true` - This is a reusable template
- **is_public**: `true` - All stores can access it
- **vertical**: `cannabis` - Industry-specific

### 2. **Standard Matrix Type Categories**
Based on actual COA `sampleType` / `matrix` fields:

| Category | Slug | Matrix Types Covered |
|----------|------|---------------------|
| **Flower** | `matrix-flower` | Flower, Flower - Cured, Flower - Fresh, Trim |
| **Concentrates** | `matrix-concentrates` | Cannabis Badder, Concentrate, Wax, Shatter, Diamonds, Live Resin, Rosin |
| **Vape Products** | `matrix-vapes` | Vape Cartridge, Disposable Vape, Vape Oil |
| **Edibles** | `matrix-edibles` | Cannabis Edible, Edible, Gummy, Chocolate, Beverage |
| **Pre-Rolls** | `matrix-pre-rolls` | Pre-Roll, Infused Pre-Roll |
| **Tinctures & Oils** | `matrix-tinctures` | Tincture, Oil, RSO |

## How It Works

### For Each Store:
1. **Install Quantix Catalog** → Creates store-specific copies of categories
2. **Auto-categorize COAs** → Maps COAs to categories based on:
   - Parsed COA `data->>'sampleType'`
   - Parsed COA `data->>'matrix'`
   - Fallback to `product_type` field
   - Document name parsing (last resort)

### Benefits:
✅ **Consistent across all stores** - Same category structure
✅ **Matrix-driven** - Categories based on actual COA testing matrix
✅ **Auto-categorization** - No manual work needed
✅ **Store customizable** - Stores can add their own categories
✅ **Platform maintainable** - Quantix controls the standard

## Database Schema

```sql
catalogs
├── id: a176de12-6efd-4ed0-bb90-d2b015791e81
├── name: "Quantix COA Matrix Types"
├── is_template: true
├── is_public: true
└── categories
    ├── Flower (metadata: {matrix_types: ['Flower', 'Flower - Cured', ...]})
    ├── Concentrates
    ├── Vape Products
    ├── Edibles
    ├── Pre-Rolls
    └── Tinctures & Oils

stores (Flora Distro, Saylor MFG, etc.)
└── store_catalogs → links to Quantix catalog
    └── categories (store-specific copies with same slugs)
        └── products
            └── store_documents (COAs)
```

## Implementation Status

### ✅ Completed:
1. Created Quantix Platform Catalog
2. Created 6 standard matrix type categories
3. Added metadata mapping for matrix types

### 🔄 Next Steps:
1. Create function to install catalog for all stores
2. Update auto-categorization to use matrix metadata
3. Update dashboard to show "Powered by Quantix" badge
4. Add admin UI for stores to install/customize catalog

## Usage

### Install for a Store:
```sql
-- This will copy Quantix categories to Flora Distro
SELECT install_quantix_catalog('cd2e1122-d511-4edb-be5d-98ef274b4baf');
```

### Auto-categorize COAs:
```sql
-- Maps COAs to categories based on matrix type
SELECT auto_categorize_coas_by_matrix('cd2e1122-d511-4edb-be5d-98ef274b4baf');
```

## Future Enhancements
- **Multi-catalog support** - Stores can have multiple catalogs (cannabis + accessories)
- **Matrix type validation** - Ensure COAs use standard matrix types
- **Category analytics** - Show which matrix types are most common
- **Auto-install on signup** - New stores get Quantix catalog automatically
