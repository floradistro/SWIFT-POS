'use client'

import Link from 'next/link'
import Logo from '../components/Logo'

const features = [
  {
    title: 'Automatic Updates',
    description: 'Test results appear in your system automatically when they\'re ready. No manual entry or delays.',
  },
  {
    title: 'Complete Information',
    description: 'Get full test results, certificates, and compliance data directly in your software.',
  },
  {
    title: 'Always Available',
    description: 'Reliable connection with secure access. We handle the technical details so you don\'t have to.',
  },
]

const integrations = [
  'POS Systems',
  'E-commerce Platforms',
  'Inventory Management',
  'Compliance Software',
  'CRM Systems',
  'Custom Applications',
]

export default function APIPage() {
  return (
    <main className="min-h-screen">
      {/* Hero Section */}
      <section className="relative min-h-screen flex items-center justify-center overflow-hidden">
        {/* Background */}
        <div className="absolute inset-0 z-0">
          <img
            src="/images/peptide-lab.png"
            alt="Laboratory"
            className="w-full h-full object-cover"
          />
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
              API
            </h1>

            <p
              className="text-2xl md:text-3xl text-white/90 max-w-3xl mx-auto"
              style={{ textShadow: '0 2px 20px rgba(0,0,0,0.5)' }}
            >
              Integrate lab results into your platform
            </p>

            <p
              className="text-lg md:text-xl text-white/70 max-w-2xl mx-auto"
              style={{ textShadow: '0 2px 12px rgba(0,0,0,0.4)' }}
            >
              Real-time results • Secure • Simple
            </p>

            {/* CTA Buttons */}
            <div className="flex flex-col sm:flex-row items-center justify-center gap-4 pt-8">
              <Link href="/contact" className="bg-[#0071e3] hover:bg-[#0077ed] text-white px-6 py-3 rounded-lg font-medium transition-all duration-200 ease-out text-[17px]">
                Get API Access
              </Link>
              <a href="mailto:api@quantixanalytics.com" className="bg-transparent hover:bg-white/5 text-[#0071e3] px-6 py-3 rounded-lg font-medium transition-all duration-200 text-[17px]">
                Email API Team
              </a>
            </div>
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section className="relative py-32 px-8 lg:px-12 bg-background">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-20">
            <h2 className="text-5xl md:text-6xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-white via-white to-white/70 mb-4">
              How It Works
            </h2>
            <div className="h-1 w-32 bg-gradient-to-r from-transparent via-[#0071e3] to-transparent mx-auto"></div>
          </div>

          <div className="grid md:grid-cols-3 gap-8 mb-20">
            {features.map((feature, index) => (
              <div
                key={index}
                className="glass-effect p-10 rounded-3xl space-y-4 group hover:bg-white/[0.08] transition-all duration-300 depth-1"
              >
                <div className="w-16 h-1 bg-gradient-to-r from-transparent via-[#0071e3] to-transparent group-hover:scale-x-150 transition-transform duration-300"></div>
                <h3 className="text-2xl font-bold text-white">
                  {feature.title}
                </h3>
                <p className="text-base text-white/70 leading-relaxed">
                  {feature.description}
                </p>
              </div>
            ))}
          </div>

          {/* Simple Explanation */}
          <div className="max-w-3xl mx-auto">
            <div className="glass-effect p-10 rounded-3xl depth-2 text-center">
              <p className="text-xl text-white/80 leading-relaxed mb-6">
                Connect your software once, and all future test results flow directly to you.
                No more manual data entry or switching between systems.
              </p>
              <p className="text-lg text-white/60">
                Perfect for dispensaries, cultivators, and anyone who needs lab results in their existing tools.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Integration Section */}
      <section className="relative py-32 px-8 lg:px-12 bg-surface">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-5xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-white to-white/80 mb-4">
              Works With Your Stack
            </h2>
            <div className="h-1 w-24 bg-gradient-to-r from-transparent via-[#0071e3] to-transparent mx-auto mb-6"></div>
            <p className="text-xl text-white/70">
              Integrate lab results into any platform
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-6 max-w-4xl mx-auto">
            {integrations.map((integration, index) => (
              <div
                key={index}
                className="glass-effect p-6 rounded-2xl text-center group hover:bg-white/[0.08] transition-all duration-300"
              >
                <div className="w-2 h-2 rounded-full bg-[#0071e3] mx-auto mb-3 group-hover:scale-150 transition-transform"></div>
                <span className="text-white font-medium">{integration}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="relative py-32 px-8 lg:px-12 bg-surface">
        <div className="max-w-4xl mx-auto text-center">
          <h2 className="text-5xl md:text-6xl font-bold text-white mb-6">
            Ready to integrate?
          </h2>
          <p className="text-xl text-white/70 mb-12">
            Contact us to get started
          </p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <Link href="/contact" className="bg-[#0071e3] hover:bg-[#0077ed] text-white px-6 py-3 rounded-lg font-medium transition-all duration-200 ease-out text-[17px]">
              Contact Sales
            </Link>
            <a href="mailto:api@quantixanalytics.com" className="bg-transparent hover:bg-white/5 text-[#0071e3] px-6 py-3 rounded-lg font-medium transition-all duration-200 text-[17px]">
              Email API Team
            </a>
          </div>
        </div>
      </section>
    </main>
  )
}
