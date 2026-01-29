import fs from 'fs'
import path from 'path'

const GEMINI_API_KEY = 'AIzaSyBg-S9Tkp3OdwdXpK0kmgu8ObIIOJbRI_k'

// Professional prompts for real business images
const imagePrompts = [
  {
    name: 'features-fast-testing',
    prompt: 'Professional modern analytical chemistry laboratory, HPLC chromatography system with digital display showing peak analysis, clean white countertops, scientist in lab coat analyzing samples, bright professional lighting, pharmaceutical grade equipment, photorealistic, high detail, corporate laboratory setting',
  },
  {
    name: 'features-pricing',
    prompt: 'Modern minimalist business desk with laptop showing analytical report dashboard, calculator and documents, professional office setting, clean aesthetic, soft natural lighting, business analytics visualization on screen, photorealistic, corporate environment',
  },
  {
    name: 'features-compliance',
    prompt: 'Regulatory compliance documentation and certificates on modern desk, official laboratory certification documents, quality assurance stamps, professional business environment, clean organized workspace, photorealistic detail, corporate setting',
  },
  {
    name: 'features-digital-coas',
    prompt: 'Modern tablet device displaying professional Certificate of Analysis with QR code, laboratory test results and data charts visible on screen, clean white background, professional product photography, high resolution, corporate branding aesthetic',
  },
  {
    name: 'features-equipment',
    prompt: 'State-of-the-art analytical laboratory equipment lineup: HPLC system, LC-MS/MS mass spectrometer, and GC-MS chromatograph, modern scientific instruments in professional lab setting, clean white surfaces, blue accent lighting, photorealistic, high-tech laboratory environment',
  },
  {
    name: 'features-support',
    prompt: 'Professional customer support team in modern office, friendly scientists and support staff at computers ready to help, clean contemporary workspace, natural lighting, collaborative environment, photorealistic, corporate setting with laboratory equipment visible in background',
  },
]

async function generateImage(prompt: string, filename: string): Promise<boolean> {
  try {
    console.log(`Generating: ${filename}...`)

    const response = await fetch(
      `https://us-central1-aiplatform.googleapis.com/v1/projects/YOUR_PROJECT_ID/locations/us-central1/publishers/google/models/imagegeneration@006:predict`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${GEMINI_API_KEY}`,
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
          },
        }),
      }
    )

    if (!response.ok) {
      const errorText = await response.text()
      console.error(`HTTP Error ${response.status}:`, errorText)
      return false
    }

    const data = await response.json()

    if (data.predictions && data.predictions.length > 0) {
      const imageData = data.predictions[0].bytesBase64Encoded
      const buffer = Buffer.from(imageData, 'base64')

      const outputPath = path.join(process.cwd(), 'public', 'images', `${filename}.png`)
      fs.writeFileSync(outputPath, buffer)

      console.log(`✓ Saved: ${filename}.png`)
      return true
    } else {
      console.error(`✗ No predictions returned for: ${filename}`)
      return false
    }
  } catch (error: any) {
    console.error(`✗ Error generating ${filename}:`, error.message)
    return false
  }
}

async function main() {
  console.log('🎨 Starting professional image generation for Quantix Analytics...\n')

  const imagesDir = path.join(process.cwd(), 'public', 'images')
  if (!fs.existsSync(imagesDir)) {
    fs.mkdirSync(imagesDir, { recursive: true })
  }

  for (const { name, prompt } of imagePrompts) {
    await generateImage(prompt, name)
    // Wait between requests
    await new Promise(resolve => setTimeout(resolve, 3000))
  }

  console.log('\n✨ Image generation complete!')
}

main()
