import fs from 'fs'
import path from 'path'

const responseFiles = [
  { file: 'cannabis_hero_response.json', output: 'hero-cannabis.png' },
  { file: 'cannabis_lab_response.json', output: 'cannabis-lab.png' },
  { file: 'hero_bg_response.json', output: 'hero-bg.png' },
  { file: 'peptide_hero_response.json', output: 'hero-peptide.png' },
  { file: 'peptide_lab_response.json', output: 'peptide-lab.png' },
  { file: 'retailer_hero_response.json', output: 'hero-retailer.png' },
]

async function extractImages() {
  console.log('📦 Extracting images from response files...\n')

  const imagesDir = path.join(process.cwd(), 'public', 'images')
  if (!fs.existsSync(imagesDir)) {
    fs.mkdirSync(imagesDir, { recursive: true })
  }

  for (const { file, output } of responseFiles) {
    try {
      const jsonPath = path.join(process.cwd(), file)
      const data = JSON.parse(fs.readFileSync(jsonPath, 'utf8'))

      if (data.predictions && data.predictions[0]?.bytesBase64Encoded) {
        const imageData = data.predictions[0].bytesBase64Encoded
        const buffer = Buffer.from(imageData, 'base64')

        const outputPath = path.join(imagesDir, output)
        fs.writeFileSync(outputPath, buffer)

        console.log(`✓ Extracted: ${output} (${(buffer.length / 1024).toFixed(1)} KB)`)
      } else {
        console.log(`✗ No image data in: ${file}`)
      }
    } catch (error: any) {
      console.log(`✗ Error with ${file}: ${error.message}`)
    }
  }

  console.log('\n✨ Done!')
}

extractImages()
