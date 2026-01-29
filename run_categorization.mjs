import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://uaednwpxursknmwdeejn.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVhZWRud3B4dXJza25td2RlZWpuIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MDk5NzIzMywiZXhwIjoyMDc2NTczMjMzfQ.l0NvBbS2JQWPObtWeVD2M2LD866A2tgLmModARYNnbI'
)

console.log('Running auto-categorization for all stores...\n')

const { data, error } = await supabase.rpc('auto_categorize_documents')

if (error) {
  console.error('Error:', error)
  process.exit(1)
}

console.log('Results:')
console.log('═══════════════════════════════════════════════════')
data.forEach(row => {
  console.log(`${row.store_name}`)
  console.log(`  Total: ${row.total_docs} | Categorized: ${row.categorized} | Success: ${row.success_rate}%`)
})
console.log('═══════════════════════════════════════════════════')
