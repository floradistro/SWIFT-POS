import { NextRequest, NextResponse } from 'next/server'

export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams
  const pdfUrl = searchParams.get('url')

  if (!pdfUrl) {
    return NextResponse.json({ error: 'PDF URL required' }, { status: 400 })
  }

  try {
    // Use a PDF thumbnail service (we'll use pdf.co or similar)
    // For now, return a placeholder that shows the PDF is loading
    const response = await fetch(
      `https://api.pdf.co/v1/pdf/convert/to/png?url=${encodeURIComponent(pdfUrl)}&pages=1`,
      {
        headers: {
          'x-api-key': process.env.PDFCO_API_KEY || '',
        },
      }
    )

    if (!response.ok) {
      throw new Error('Failed to generate thumbnail')
    }

    const data = await response.json()

    return NextResponse.json({ thumbnailUrl: data.urls[0] })
  } catch (error) {
    console.error('Thumbnail generation error:', error)
    return NextResponse.json({ error: 'Failed to generate thumbnail' }, { status: 500 })
  }
}
