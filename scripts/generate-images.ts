import fs from 'fs'
import path from 'path'

const GEMINI_API_KEY = 'AIzaSyBg-S9Tkp3OdwdXpK0kmgu8ObIIOJbRI_k'

const imagePrompts = [
  {
    name: 'hero-cannabis-lab',
    prompt: 'Professional modern cannabis testing laboratory, state-of-the-art HPLC equipment, clean white surfaces, green accent lighting, scientists in lab coats, bright and professional atmosphere, photorealistic, high quality, 16:9 aspect ratio',
  },
  {
    name: 'hero-peptide-research',
    prompt: 'Advanced peptide research facility, mass spectrometry equipment, modern laboratory setting, blue accent lighting, sterile environment, high-tech analytical instruments, professional scientists, photorealistic, high quality, 16:9 aspect ratio',
  },
  {
    name: 'cannabis-testing-detail',
    prompt: 'Close-up of cannabis flower sample being tested in modern laboratory, HPLC machine in background, professional lab technician, green plant material, scientific precision, photorealistic, high quality, 16:9 aspect ratio',
  },
  {
    name: 'peptide-analysis',
    prompt: 'Peptide vials and analytical chemistry equipment, chromatography results on screen, clean modern laboratory, blue and white color scheme, precise scientific instruments, photorealistic, high quality, 16:9 aspect ratio',
  },
  {
    name: 'lab-equipment-setup',
    prompt: 'Modern analytical laboratory setup with HPLC, LC-MS, and GC-MS equipment, clean white laboratory surfaces, professional scientific instruments, well-lit workspace, photorealistic, high quality, 16:9 aspect ratio',
  },
  {
    name: 'certificate-analysis',
    prompt: 'Digital certificate of analysis displayed on modern tablet device, laboratory background with testing equipment, professional and clean aesthetic, data visualization charts, photorealistic, high quality, 16:9 aspect ratio',
  },
]

async function generateImage(prompt: string, filename: string) {
  try {
    console.log(`Generating image: ${filename}...`)

    // Try the vertex AI endpoint for Imagen
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/imagegeneration@006:predict?key=${GEMINI_API_KEY}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          instances: [
            {
              prompt: prompt,
            },
          ],
          parameters: {
            sampleCount: 1,
            aspectRatio: '16:9',
          },
        }),
      }
    )

    const data = await response.json()

    if (!response.ok) {
      throw new Error(data.error?.message || 'Failed to generate image')
    }

    if (data.predictions && data.predictions.length > 0) {
      // The image is returned as base64 in predictions array
      const imageData = data.predictions[0].bytesBase64Encoded
      const buffer = Buffer.from(imageData, 'base64')

      // Save to public/images
      const outputPath = path.join(process.cwd(), 'public', 'images', `${filename}.png`)
      fs.writeFileSync(outputPath, buffer)

      console.log(`✓ Saved: ${filename}.png`)
      return true
    } else {
      console.error(`✗ No images generated for: ${filename}`)
      console.error('Response:', JSON.stringify(data).substring(0, 500))
      return false
    }
  } catch (error: any) {
    console.error(`✗ Error generating ${filename}:`, error.message)
    return false
  }
}

async function main() {
  console.log('Starting image generation...\n')

  // Ensure images directory exists
  const imagesDir = path.join(process.cwd(), 'public', 'images')
  if (!fs.existsSync(imagesDir)) {
    fs.mkdirSync(imagesDir, { recursive: true })
  }

  for (const { name, prompt } of imagePrompts) {
    await generateImage(prompt, name)
    // Wait a bit between requests to avoid rate limits
    await new Promise(resolve => setTimeout(resolve, 2000))
  }

  console.log('\nImage generation complete!')
}

main()
