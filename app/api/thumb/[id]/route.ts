import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function GET(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  const docId = params.id

  try {
    // Get document
    const { data: doc, error } = await supabase
      .from('store_documents')
      .select('file_url, thumbnail_url')
      .eq('id', docId)
      .single()

    if (error || !doc) {
      return NextResponse.json({ error: 'Document not found' }, { status: 404 })
    }

    // If thumbnail exists and is an image, serve it
    if (doc.thumbnail_url && /\.(jpg|jpeg|png|webp)$/i.test(doc.thumbnail_url)) {
      return NextResponse.redirect(doc.thumbnail_url)
    }

    // Use v2.convertapi.com to generate thumbnail on-the-fly
    const apiSecret = 'secret_hnfxzrVHXNLOJBg5'
    const response = await fetch('https://v2.convertapi.com/convert/pdf/to/png', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        Parameters: [
          {
            Name: 'File',
            FileValue: {
              Url: doc.file_url
            }
          },
          {
            Name: 'PageRange',
            Value: '1'
          },
          {
            Name: 'ScaleImage',
            Value: 'true'
          },
          {
            Name: 'ScaleProportions',
            Value: 'true'
          },
          {
            Name: 'ImageHeight',
            Value: '800'
          }
        ]
      })
    })

    const result = await response.json()

    if (result.Files && result.Files[0]) {
      const thumbnailUrl = result.Files[0].Url

      // Cache the thumbnail URL
      await supabase
        .from('store_documents')
        .update({ thumbnail_url: thumbnailUrl })
        .eq('id', docId)

      return NextResponse.redirect(thumbnailUrl)
    }

    // Fallback to original PDF
    return NextResponse.redirect(doc.file_url)

  } catch (error) {
    console.error('Thumbnail generation error:', error)
    return NextResponse.json({ error: 'Failed to generate thumbnail' }, { status: 500 })
  }
}
