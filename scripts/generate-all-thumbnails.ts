import { createClient } from '@supabase/supabase-js'
import * as dotenv from 'dotenv'
import * as path from 'path'
import { exec } from 'child_process'
import { promisify } from 'util'
import fs from 'fs'

const execAsync = promisify(exec)

dotenv.config({ path: path.resolve(process.cwd(), '.env.local') })

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!
const supabase = createClient(supabaseUrl, supabaseServiceKey)

async function generateThumbnails() {
  console.log('🖼️  Generating thumbnails for all PDFs...\n')

  // Get all documents without thumbnails
  const { data: docs, error } = await supabase
    .from('store_documents')
    .select('id, file_url, document_name, store_id')
    .is('thumbnail_url', null)
    .eq('is_active', true)
    .limit(200)

  if (error || !docs) {
    console.error('Error fetching documents:', error)
    return
  }

  console.log(`Found ${docs.length} documents needing thumbnails\n`)

  for (const doc of docs) {
    try {
      console.log(`📄 Processing: ${doc.document_name}`)

      // Download PDF
      const pdfResponse = await fetch(doc.file_url)
      const pdfBuffer = await pdfResponse.arrayBuffer()
      const tempPdfPath = `/tmp/${doc.id}.pdf`
      const tempJpgPath = `/tmp/${doc.id}.jpg`

      fs.writeFileSync(tempPdfPath, Buffer.from(pdfBuffer))

      // Convert first page to JPG using ImageMagick v7
      await execAsync(`magick -density 150 "${tempPdfPath}[0]" -quality 85 -resize 400x "${tempJpgPath}"`)

      // Upload to Supabase Storage
      const jpgBuffer = fs.readFileSync(tempJpgPath)
      const { data: uploadData, error: uploadError } = await supabase.storage
        .from('vendor-coas')
        .upload(`${doc.store_id}/thumbnails/${doc.id}.jpg`, jpgBuffer, {
          contentType: 'image/jpeg',
          upsert: true
        })

      if (uploadError) {
        console.error(`  ❌ Upload failed:`, uploadError.message)
        continue
      }

      // Get public URL
      const { data: publicUrlData } = supabase.storage
        .from('vendor-coas')
        .getPublicUrl(`${doc.store_id}/thumbnails/${doc.id}.jpg`)

      // Update document with thumbnail URL
      await supabase
        .from('store_documents')
        .update({ thumbnail_url: publicUrlData.publicUrl })
        .eq('id', doc.id)

      console.log(`  ✅ Generated and uploaded thumbnail`)

      // Cleanup
      fs.unlinkSync(tempPdfPath)
      fs.unlinkSync(tempJpgPath)

    } catch (err: any) {
      console.error(`  ❌ Error: ${err.message}`)
    }
  }

  console.log('\n✨ Done!')
}

generateThumbnails()
