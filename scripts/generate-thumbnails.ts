import { createClient } from '@supabase/supabase-js'
import * as dotenv from 'dotenv'
import * as path from 'path'

dotenv.config({ path: path.resolve(process.cwd(), '.env.local') })

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!

const supabase = createClient(supabaseUrl, supabaseServiceKey)

async function generateThumbnails() {
  console.log('🖼️  Generating PDF thumbnails...')

  // Get all documents without thumbnails
  const { data: documents, error } = await supabase
    .from('store_documents')
    .select('id, file_url, document_name')
    .is('thumbnail_url', null)
    .eq('is_active', true)
    .limit(10)

  if (error) {
    console.error('Error fetching documents:', error)
    return
  }

  console.log(`Found ${documents?.length || 0} documents without thumbnails`)

  for (const doc of documents || []) {
    console.log(`\n📄 Processing: ${doc.document_name}`)

    try {
      // Use pdf.co API to generate thumbnail
      const response = await fetch('https://api.pdf.co/v1/pdf/convert/to/png', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': process.env.PDFCO_API_KEY || ''
        },
        body: JSON.stringify({
          url: doc.file_url,
          pages: '0', // First page only
          async: false
        })
      })

      const result = await response.json()

      if (result.url) {
        // Update document with thumbnail URL
        await supabase
          .from('store_documents')
          .update({ thumbnail_url: result.url })
          .eq('id', doc.id)

        console.log(`✅ Generated thumbnail for ${doc.document_name}`)
      } else {
        console.log(`⚠️  No thumbnail URL returned for ${doc.document_name}`)
      }
    } catch (err) {
      console.error(`❌ Error processing ${doc.document_name}:`, err)
    }

    // Rate limiting
    await new Promise(resolve => setTimeout(resolve, 1000))
  }

  console.log('\n✨ Thumbnail generation complete!')
}

generateThumbnails()
