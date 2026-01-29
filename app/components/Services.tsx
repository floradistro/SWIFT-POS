'use client'

import { ArrowRight } from 'lucide-react'
import Link from 'next/link'

export default function Services() {
  return (
    <section className="relative py-24 md:py-32 px-8 lg:px-12 bg-surface">
      <div className="max-w-7xl mx-auto">
        {/* Cannabis Testing */}
        <div className="grid lg:grid-cols-2 gap-16 items-center mb-32">
          <div className="space-y-8">
            <div>
              <h2 className="text-5xl md:text-6xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-white to-white/80 mb-4">
                Cannabis Testing
              </h2>
              <div className="h-1 w-20 bg-gradient-to-r from-quantix-accent to-transparent"></div>
            </div>
            <p className="text-xl text-white/70 leading-relaxed">
              Full compliance panel for growers, processors, and dispensaries. Get your harvest certified.
            </p>
            <div className="space-y-3">
              <p className="text-lg text-white">Potency testing - THC, CBD, CBG, CBN, full cannabinoid panel</p>
              <p className="text-lg text-white">Terpene analysis - Myrcene, limonene, pinene + 30 more</p>
              <p className="text-lg text-white">Safety screening - Pesticides, heavy metals, mold, bacteria</p>
              <p className="text-lg text-white">Moisture & water activity included</p>
            </div>
            <div className="pt-4">
              <Link href="/testing" className="inline-flex items-center gap-2 bg-quantix-accent text-white px-8 py-4 rounded-full font-semibold transition-all duration-200 ease-out hover:bg-quantix-accent-hover hover:shadow-glow-lg hover:scale-105 active:scale-100 text-[15px] shadow-glow">
                <span>View Testing</span>
                <ArrowRight className="w-4 h-4" />
              </Link>
            </div>
          </div>
          <div className="space-y-6">
            <div className="aspect-video rounded-2xl overflow-hidden shadow-2xl border border-white/5">
              <img
                src="/images/cannabis-lab.png"
                alt="Cannabis Testing"
                className="w-full h-full object-cover"
                loading="lazy"
              />
            </div>
            <div className="text-center glass-effect p-8 rounded-2xl">
              <p className="text-white/60 text-sm mb-2">Full Panel</p>
              <p className="text-6xl font-bold text-white mb-2">$150</p>
              <p className="text-white/60">24-48 hour results</p>
            </div>
          </div>
        </div>

        {/* Peptide Testing */}
        <div className="grid lg:grid-cols-2 gap-16 items-center mb-32">
          <div className="space-y-6 lg:order-2">
            <div>
              <h2 className="text-5xl md:text-6xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-white to-white/80 mb-4">
                Peptide Testing
              </h2>
              <div className="h-1 w-20 bg-gradient-to-r from-quantix-accent to-transparent"></div>
            </div>
            <p className="text-xl text-white/70 leading-relaxed">
              HPLC purity verification for manufacturers and research facilities.
            </p>
            <div className="space-y-3">
              <p className="text-lg text-white">HPLC purity percentage with chromatogram</p>
              <p className="text-lg text-white">Mass spec identity verification</p>
              <p className="text-lg text-white">Impurity detection and quantification</p>
              <p className="text-lg text-white">Detailed COA with methodology</p>
            </div>
            <div className="pt-4">
              <Link href="/testing" className="inline-flex items-center gap-2 bg-quantix-accent text-white px-8 py-4 rounded-full font-semibold transition-all duration-200 ease-out hover:bg-quantix-accent-hover hover:shadow-glow-lg hover:scale-105 active:scale-100 text-[15px] shadow-glow">
                <span>View Testing</span>
                <ArrowRight className="w-4 h-4" />
              </Link>
            </div>
          </div>
          <div className="space-y-6 lg:order-1">
            <div className="aspect-video rounded-2xl overflow-hidden shadow-2xl border border-white/5">
              <img
                src="/images/peptide-lab.png"
                alt="Peptide Testing"
                className="w-full h-full object-cover"
                loading="lazy"
              />
            </div>
            <div className="text-center glass-effect p-8 rounded-2xl">
              <p className="text-white/60 text-sm mb-2">Per Peptide</p>
              <p className="text-6xl font-bold text-white mb-2">$200</p>
              <p className="text-white/60">48-72 hour results</p>
            </div>
          </div>
        </div>

        {/* CTA Section */}
        <div className="text-center max-w-3xl mx-auto">
          <div className="inline-block">
            <h3 className="text-4xl md:text-5xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-white via-white to-white/70 mb-4">
              Ready to Test?
            </h3>
            <div className="h-1 w-24 bg-gradient-to-r from-transparent via-quantix-accent to-transparent mx-auto mb-6"></div>
          </div>
          <p className="text-xl text-white/60 mb-10">
            Get pricing or submit samples
          </p>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <a href="mailto:support@quantixanalytics.com" className="bg-[#0071e3] hover:bg-[#0077ed] text-white px-6 py-3 rounded-lg font-medium transition-all duration-200 ease-out text-[17px]">
              Get a Quote
            </a>
            <a href="/login" className="bg-transparent hover:bg-white/5 text-[#0071e3] px-6 py-3 rounded-lg font-medium transition-all duration-200 text-[17px]">
              Client Login
            </a>
          </div>
        </div>
      </div>
    </section>
  )
}
