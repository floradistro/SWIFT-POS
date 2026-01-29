import { NextResponse } from 'next/server'

const GEMINI_API_KEY = 'AIzaSyBg-S9Tkp3OdwdXpK0kmgu8ObIIOJbRI_k'

export async function POST(request: Request) {
  try {
    const { prompt } = await request.json()

    // Using Gemini's Imagen model for image generation
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-001:generateImages?key=${GEMINI_API_KEY}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          prompt: prompt,
          number_of_images: 1,
          aspect_ratio: '16:9',
          safety_filter_level: 'block_some',
          person_generation: 'allow_adult',
        }),
      }
    )

    const data = await response.json()

    if (!response.ok) {
      throw new Error(data.error?.message || 'Failed to generate image')
    }

    // The response contains generated images
    return NextResponse.json({
      success: true,
      images: data.generated_images || [],
    })
  } catch (error: any) {
    console.error('Image generation error:', error)
    return NextResponse.json(
      { success: false, error: error.message },
      { status: 500 }
    )
  }
}
