import fs from 'fs'
import path from 'path'

// Nano Banana image generation
async function generateImage() {
  const prompt = 'Professional analytical chemistry laboratory interior, modern HPLC and LC-MS equipment on clean white countertops, stainless steel surfaces, bright professional lighting, scientist in white lab coat analyzing samples, state-of-the-art testing facility, pharmaceutical grade laboratory, photorealistic, high detail, 16:9 aspect ratio'

  console.log('🍌 Generating About hero image with Nano Banana...\n')

  try {
    const response = await fetch('https://api.nanobana.com/v1/generate', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer AIzaSyBg-S9Tkp3OdwdXpK0kmgu8ObIIOJbRI_k'
      },
      body: JSON.stringify({
        prompt: prompt,
        width: 1920,
        height: 1080,
        num_images: 1
      })
    })

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${await response.text()}`)
    }

    const data = await response.json()

    if (data.images && data.images[0]) {
      const imageData = data.images[0]
      const buffer = Buffer.from(imageData, 'base64')

      const outputPath = path.join(process.cwd(), 'public', 'images', 'about-hero.png')
      fs.writeFileSync(outputPath, buffer)

      console.log(`✓ Saved: about-hero.png (${(buffer.length / 1024).toFixed(1)} KB)`)
    } else {
      console.error('No image data returned')
    }
  } catch (error: any) {
    console.error('Error:', error.message)
  }
}

generateImage()
