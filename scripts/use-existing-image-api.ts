import fs from 'fs'
import path from 'path'

// You already have the API working - let's use it the same way you did before
const API_KEY = 'AIzaSyBg-S9Tkp3OdwdXpK0kmgu8ObIIOJbRI_k'
const PROJECT_ID = 'quantix-analytics' // Adjust if different

const prompts = [
  {
    file: 'lab-equipment-modern',
    prompt: 'Modern analytical chemistry laboratory with HPLC chromatography equipment, LC-MS mass spectrometer, clean white surfaces, professional scientist in lab coat, bright lighting, photorealistic, high detail, 16:9 aspect ratio'
  },
  {
    file: 'cannabis-testing-pro',
    prompt: 'Professional cannabis flower samples on laboratory testing bench with analytical equipment, HPLC system in background, clean modern lab, green plant material, scientific precision tools, photorealistic, 16:9'
  },
  {
    file: 'peptide-research-lab',
    prompt: 'Advanced peptide research laboratory with mass spectrometry equipment, scientist analyzing samples on computer screen showing chromatography data, modern sterile environment, blue accent lighting, photorealistic, 16:9'
  },
  {
    file: 'digital-coa-tablet',
    prompt: 'Modern tablet device displaying professional Certificate of Analysis with QR code and test results, clean white background, product photography style, high resolution corporate branding, photorealistic, 16:9'
  },
  {
    file: 'compliance-documents',
    prompt: 'Professional regulatory compliance certification documents on modern desk, quality assurance stamps and official laboratory certificates, organized business workspace, photorealistic, 16:9'
  },
  {
    file: 'lab-technician-support',
    prompt: 'Friendly laboratory scientist at modern computer workstation ready to help, clean contemporary lab environment with equipment visible, professional customer support setting, natural lighting, photorealistic, 16:9'
  }
]

async function generateWithVertex(prompt: string, filename: string) {
  try {
    console.log(`\nGenerating: ${filename}`)
    console.log(`Prompt: ${prompt.substring(0, 80)}...`)

    const url = `https://us-central1-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/us-central1/publishers/google/models/imagegeneration@006:predict`

    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${API_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        instances: [{
          prompt: prompt
        }],
        parameters: {
          sampleCount: 1
        }
      })
    })

    if (!response.ok) {
      const error = await response.text()
      console.error(`Error: ${response.status} - ${error}`)
      return false
    }

    const data = await response.json()

    if (data.predictions && data.predictions[0]?.bytesBase64Encoded) {
      const imageData = data.predictions[0].bytesBase64Encoded
      const buffer = Buffer.from(imageData, 'base64')

      const outputPath = path.join(process.cwd(), 'public', 'images', `${filename}.png`)
      fs.writeFileSync(outputPath, buffer)

      console.log(`✓ Saved: ${filename}.png (${(buffer.length / 1024).toFixed(1)} KB)`)
      return true
    } else {
      console.error('No image data in response')
      return false
    }
  } catch (error: any) {
    console.error(`Error: ${error.message}`)
    return false
  }
}

async function main() {
  console.log('🎨 Generating professional images for Quantix Analytics\n')

  const imagesDir = path.join(process.cwd(), 'public', 'images')
  if (!fs.existsSync(imagesDir)) {
    fs.mkdirSync(imagesDir, { recursive: true })
  }

  let success = 0
  let failed = 0

  for (const { file, prompt } of prompts) {
    const result = await generateWithVertex(prompt, file)
    if (result) success++
    else failed++

    // Wait between requests to respect rate limits
    await new Promise(resolve => setTimeout(resolve, 2000))
  }

  console.log(`\n✨ Complete! Success: ${success}, Failed: ${failed}`)
}

main()
