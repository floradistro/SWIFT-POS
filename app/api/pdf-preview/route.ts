import { NextRequest, NextResponse } from 'next/server'
import * as pdfjsLib from 'pdfjs-dist/legacy/build/pdf.mjs'
import sharp from 'sharp'

// Initialize PDF.js worker
pdfjsLib.GlobalWorkerOptions.workerSrc = `//cdnjs.cloudflare.com/ajax/libs/pdf.js/${pdfjsLib.version}/pdf.worker.min.js`

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams
  const pdfUrl = searchParams.get('url')
  const width = parseInt(searchParams.get('width') || '400')

  if (!pdfUrl) {
    return NextResponse.json({ error: 'PDF URL required' }, { status: 400 })
  }

  try {
    // Fetch the PDF
    const pdfResponse = await fetch(pdfUrl)
    if (!pdfResponse.ok) {
      throw new Error('Failed to fetch PDF')
    }

    const pdfBuffer = await pdfResponse.arrayBuffer()

    // Load PDF document
    const loadingTask = pdfjsLib.getDocument({ data: pdfBuffer })
    const pdf = await loadingTask.promise

    // Get first page
    const page = await pdf.getPage(1)

    // Set viewport scale
    const viewport = page.getViewport({ scale: 2.0 })

    // Create canvas
    const canvas = {
      width: viewport.width,
      height: viewport.height,
      getContext: () => ({
        canvas: { width: viewport.width, height: viewport.height },
        fillStyle: '#ffffff',
        fillRect: () => {},
        save: () => {},
        restore: () => {},
        translate: () => {},
        scale: () => {},
        transform: () => {},
        setTransform: () => {},
        drawImage: () => {},
      })
    }

    // Render page
    const renderContext = {
      canvasContext: canvas.getContext(),
      viewport: viewport,
    }

    await page.render(renderContext).promise

    // For now, return a simple response - we need a proper canvas implementation
    // Using a thumbnail service instead
    return NextResponse.json({
      message: 'Thumbnail generation in progress',
      originalUrl: pdfUrl
    })

  } catch (error) {
    console.error('PDF preview error:', error)
    return NextResponse.json({ error: 'Failed to generate preview' }, { status: 500 })
  }
}
