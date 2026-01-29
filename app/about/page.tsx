'use client'

import Logo from '../components/Logo'
import Link from 'next/link'

export default function AboutPage() {
  return (
    <main className="min-h-screen">
      {/* Hero Section */}
      <section className="relative min-h-[80vh] flex items-center justify-center overflow-hidden">
        {/* Background Image */}
        <div className="absolute inset-0 z-0">
          <img
            src="/images/hero-bg.png"
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
              About
            </h1>

            <p
              className="text-2xl md:text-3xl text-white/90 max-w-3xl mx-auto"
              style={{ textShadow: '0 2px 20px rgba(0,0,0,0.5)' }}
            >
              Professional testing you can trust
            </p>

            <p
              className="text-lg md:text-xl text-white/70 max-w-2xl mx-auto"
              style={{ textShadow: '0 2px 12px rgba(0,0,0,0.4)' }}
            >
              Accurate results • Fast turnaround • Expert support
            </p>
          </div>
        </div>
      </section>

      {/* Stats Section */}
      <section className="relative py-32 px-8 lg:px-12 bg-black">
        <div className="max-w-7xl mx-auto">
          <div className="grid md:grid-cols-3 gap-16 text-center">
            <div className="space-y-4">
              <div className="text-7xl font-bold text-[#0071e3]">10+</div>
              <div className="text-2xl text-white font-medium">Years Experience</div>
              <div className="text-white/60">Cannabis and peptide testing</div>
            </div>
            <div className="space-y-4">
              <div className="text-7xl font-bold text-[#0071e3]">NC</div>
              <div className="text-2xl text-white font-medium">Based in North Carolina</div>
              <div className="text-white/60">Serving clients nationwide</div>
            </div>
            <div className="space-y-4">
              <div className="text-7xl font-bold text-[#0071e3]">24-48h</div>
              <div className="text-2xl text-white font-medium">Fast Turnaround</div>
              <div className="text-white/60">Results when you need them</div>
            </div>
          </div>
        </div>
      </section>

      {/* Cannabis Section */}
      <section className="relative py-32 px-8 lg:px-12 bg-background">
        <div className="max-w-6xl mx-auto grid md:grid-cols-2 gap-16 items-center">
          <div className="space-y-8">
            <h2 className="text-5xl md:text-6xl font-bold text-white">
              Cannabis Testing
            </h2>
            <p className="text-xl text-white/70 leading-relaxed">
              Full compliance panels with potency, terpenes, pesticides, heavy metals, and microbial testing. We understand multi-state regulations for medical, recreational, and hemp markets.
            </p>
            <p className="text-xl text-white/70 leading-relaxed">
              10 years serving cultivators, processors, and dispensaries with fast 24-48 hour turnaround.
            </p>
          </div>
          <div className="relative">
            <img
              src="/images/cannabis-lab.png"
              alt="Laboratory"
              className="rounded-3xl shadow-2xl"
            />
          </div>
        </div>
      </section>

      {/* Peptide Section */}
      <section className="relative py-32 px-8 lg:px-12 bg-surface">
        <div className="max-w-6xl mx-auto grid md:grid-cols-2 gap-16 items-center">
          <div className="relative order-2 md:order-1">
            <img
              src="/images/peptide-lab.png"
              alt="Laboratory Equipment"
              className="rounded-3xl shadow-2xl"
            />
          </div>
          <div className="space-y-8 order-1 md:order-2">
            <h2 className="text-5xl md:text-6xl font-bold text-white">
              Peptide Analysis
            </h2>
            <p className="text-xl text-white/70 leading-relaxed">
              HPLC purity verification with mass spectrometry confirmation. We provide detailed certificates of analysis for manufacturers and research facilities.
            </p>
            <p className="text-xl text-white/70 leading-relaxed">
              Standard testing in 48-72 hours, or full characterization with amino acid analysis and sequence verification.
            </p>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="relative py-32 md:py-40 px-8 lg:px-12 bg-background">
        <div className="max-w-4xl mx-auto text-center">
          <h2 className="text-5xl font-bold text-white mb-6">
            Ready to Work Together?
          </h2>
          <p className="text-xl text-white/70 mb-10">
            Contact us to discuss your testing needs
          </p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <a href="mailto:support@quantixanalytics.com" className="bg-[#0071e3] hover:bg-[#0077ed] text-white px-6 py-3 rounded-lg font-medium transition-all duration-200 ease-out text-[17px]">
              Contact Us
            </a>
            <Link href="/services" className="bg-transparent hover:bg-white/5 text-[#0071e3] px-6 py-3 rounded-lg font-medium transition-all duration-200 text-[17px]">
              View Services
            </Link>
          </div>
        </div>
      </section>
    </main>
  )
}
