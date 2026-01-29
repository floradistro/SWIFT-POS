'use client'

import { ArrowRight } from 'lucide-react'
import Link from 'next/link'
import Logo from '../components/Logo'

const cannabisTests = [
  {
    name: 'Full Compliance Panel',
    price: '$150',
    turnaround: '24-48 hours',
    description: 'Complete state-compliant testing package',
    includes: [
      'Potency - Full cannabinoid panel (THC, CBD, CBG, CBN, THCV, CBC)',
      'Terpenes - 30+ terpene analysis',
      'Pesticides - Full pesticide screening',
      'Heavy Metals - Lead, arsenic, mercury, cadmium',
      'Microbials - E.coli, salmonella, mold, yeast',
      'Mycotoxins - Aflatoxins, ochratoxin',
      'Residual Solvents - Butane, propane, ethanol, etc.',
      'Moisture Content & Water Activity'
    ],
    popular: true
  },
  {
    name: 'Potency Only',
    price: '$75',
    turnaround: '24 hours',
    description: 'Cannabinoid analysis only',
    includes: [
      'THC, THCA, CBD, CBDA',
      'CBG, CBN, CBC, THCV',
      'Total THC & Total CBD calculations'
    ]
  },
  {
    name: 'Potency + Terpenes',
    price: '$100',
    turnaround: '24-48 hours',
    description: 'Potency and terpene profile',
    includes: [
      'Full cannabinoid panel',
      '30+ terpene analysis',
      'Detailed terpene report'
    ]
  },
  {
    name: 'Safety Screening',
    price: '$125',
    turnaround: '48 hours',
    description: 'Contaminant testing only',
    includes: [
      'Pesticide screening',
      'Heavy metals analysis',
      'Microbial testing',
      'Mycotoxin testing'
    ]
  }
]

const peptideTests = [
  {
    name: 'Standard Purity Analysis',
    price: '$200',
    turnaround: '48-72 hours',
    description: 'HPLC purity verification',
    includes: [
      'HPLC purity percentage',
      'Chromatogram with peak integration',
      'Identity confirmation',
      'Detailed COA'
    ],
    popular: true
  },
  {
    name: 'Full Characterization',
    price: '$350',
    turnaround: '5-7 days',
    description: 'Complete peptide analysis',
    includes: [
      'HPLC purity analysis',
      'Mass spectrometry confirmation',
      'Amino acid analysis',
      'Impurity identification',
      'Peptide sequence verification',
      'Comprehensive analytical report'
    ]
  },
  {
    name: 'Bulk Testing (10+ peptides)',
    price: '$175 ea',
    turnaround: '48-72 hours',
    description: 'Volume discount pricing',
    includes: [
      'Standard HPLC analysis per peptide',
      'Individual COAs',
      'Bulk reporting available'
    ]
  }
]

export default function ServicesPage() {
  return (
    <main className="min-h-screen">
      {/* Hero Section */}
      <section className="relative min-h-[80vh] flex items-center justify-center overflow-hidden">
        {/* Background Image */}
        <div className="absolute inset-0 z-0">
          <img
            src="/images/cannabis-lab.png"
            alt="Laboratory"
            className="w-full h-full object-cover"
          />
          {/* Gradient overlay */}
          <div className="absolute inset-0 bg-gradient-to-b from-black/50 via-black/60 to-black/70"></div>
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,transparent_40%,rgba(0,0,0,0.4)_100%)]"></div>
        </div>

        {/* Content */}
        <div className="relative z-10 max-w-7xl mx-auto px-8 lg:px-12 py-40 text-center">
          <div className="space-y-8">
            {/* Logo */}
            <div className="inline-flex items-center justify-center animate-fade-in mb-8">
              <div className="scale-[3] transform">
                <Logo size="lg" showText={false} href={null} />
              </div>
            </div>

            <h1
              className="text-6xl md:text-7xl lg:text-8xl font-bold text-white"
              style={{
                textShadow: '0 2px 40px rgba(0,0,0,0.5), 0 4px 12px rgba(0,0,0,0.3)'
              }}
            >
              Testing Services
            </h1>
            <p
              className="text-2xl md:text-3xl text-white/90 max-w-3xl mx-auto"
              style={{ textShadow: '0 2px 20px rgba(0,0,0,0.5)' }}
            >
              Professional laboratory testing for cannabis and peptides
            </p>
            <p
              className="text-lg md:text-xl text-white/70 max-w-2xl mx-auto"
              style={{ textShadow: '0 2px 12px rgba(0,0,0,0.4)' }}
            >
              State-compliant testing • HPLC analysis • Fast results
            </p>
          </div>
        </div>
      </section>

      {/* Cannabis Testing */}
      <section className="relative py-24 px-8 lg:px-12 bg-surface">
        <div className="max-w-7xl mx-auto">
          <div className="mb-16">
            <h2 className="text-5xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-white to-white/80 mb-4">
              Cannabis Testing
            </h2>
            <div className="h-1 w-24 bg-gradient-to-r from-quantix-accent to-transparent mb-6"></div>
            <p className="text-xl text-white/70">
              State-compliant testing for cultivators, processors, and dispensaries
            </p>
          </div>

          <div className="grid md:grid-cols-2 gap-8">
            {cannabisTests.map((test, index) => (
              <div
                key={index}
                className={`glass-effect p-10 rounded-3xl depth-2 hover:bg-white/[0.08] transition-all duration-300 ${
                  test.popular ? 'ring-2 ring-quantix-accent/40' : ''
                }`}
              >
                {test.popular && (
                  <div className="inline-block px-4 py-1 rounded-full bg-quantix-accent/20 border border-quantix-accent/40 text-sm font-semibold text-white mb-4">
                    Most Popular
                  </div>
                )}
                <h3 className="text-3xl font-bold text-white mb-3">
                  {test.name}
                </h3>
                <div className="flex items-baseline gap-2 mb-4">
                  <span className="text-5xl font-bold text-white">{test.price}</span>
                  <span className="text-white/60">per sample</span>
                </div>
                <p className="text-white/60 mb-2">{test.turnaround}</p>
                <p className="text-lg text-white/80 mb-6">{test.description}</p>

                <div className="space-y-3 mb-8">
                  {test.includes.map((item, i) => (
                    <div key={i} className="flex items-start gap-3">
                      <div className="w-1.5 h-1.5 rounded-full bg-quantix-accent mt-2 flex-shrink-0"></div>
                      <p className="text-white/70">{item}</p>
                    </div>
                  ))}
                </div>

                <Link href="/contact" className="bg-[#0071e3] hover:bg-[#0077ed] text-white px-6 py-3 rounded-lg font-medium transition-all duration-200 ease-out text-[17px] block text-center">
                  Request Quote
                </Link>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Peptide Testing */}
      <section className="relative py-24 px-8 lg:px-12 bg-background">
        <div className="max-w-7xl mx-auto">
          <div className="mb-16">
            <h2 className="text-5xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-white to-white/80 mb-4">
              Peptide Testing
            </h2>
            <div className="h-1 w-24 bg-gradient-to-r from-quantix-accent to-transparent mb-6"></div>
            <p className="text-xl text-white/70">
              HPLC purity analysis for manufacturers and research facilities
            </p>
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
            {peptideTests.map((test, index) => (
              <div
                key={index}
                className={`glass-effect p-10 rounded-3xl depth-2 hover:bg-white/[0.08] transition-all duration-300 ${
                  test.popular ? 'ring-2 ring-quantix-accent/40' : ''
                }`}
              >
                {test.popular && (
                  <div className="inline-block px-4 py-1 rounded-full bg-quantix-accent/20 border border-quantix-accent/40 text-sm font-semibold text-white mb-4">
                    Most Popular
                  </div>
                )}
                <h3 className="text-3xl font-bold text-white mb-3">
                  {test.name}
                </h3>
                <div className="flex items-baseline gap-2 mb-4">
                  <span className="text-5xl font-bold text-white">{test.price}</span>
                </div>
                <p className="text-white/60 mb-2">{test.turnaround}</p>
                <p className="text-lg text-white/80 mb-6">{test.description}</p>

                <div className="space-y-3 mb-8">
                  {test.includes.map((item, i) => (
                    <div key={i} className="flex items-start gap-3">
                      <div className="w-1.5 h-1.5 rounded-full bg-quantix-accent mt-2 flex-shrink-0"></div>
                      <p className="text-white/70">{item}</p>
                    </div>
                  ))}
                </div>

                <Link href="/contact" className="bg-[#0071e3] hover:bg-[#0077ed] text-white px-6 py-3 rounded-lg font-medium transition-all duration-200 ease-out text-[17px] block text-center">
                  Request Quote
                </Link>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="relative py-32 px-8 lg:px-12 bg-surface">
        <div className="max-w-4xl mx-auto text-center">
          <h2 className="text-5xl font-bold text-white mb-6">
            Need Custom Testing?
          </h2>
          <p className="text-xl text-white/70 mb-10">
            We offer custom testing panels and research services. Contact us to discuss your specific needs.
          </p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <a href="mailto:support@quantixanalytics.com" className="bg-[#0071e3] hover:bg-[#0077ed] text-white px-6 py-3 rounded-lg font-medium transition-all duration-200 ease-out text-[17px]">
              Contact Sales
            </a>
            <Link href="/login" className="bg-transparent hover:bg-white/5 text-[#0071e3] px-6 py-3 rounded-lg font-medium transition-all duration-200 text-[17px]">
              Client Portal
            </Link>
          </div>
        </div>
      </section>
    </main>
  )
}
