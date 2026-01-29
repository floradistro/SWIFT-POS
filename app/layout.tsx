import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Quantix Analytics - Precision Testing. Trusted Results.',
  description: 'Cannabis Testing Laboratory providing comprehensive cannabinoid potency analysis, compliance testing, and Certificates of Analysis',
  keywords: 'cannabis testing, cannabinoid analysis, COA, laboratory, potency testing',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className="font-sans">{children}</body>
    </html>
  )
}
