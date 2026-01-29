'use client'

export default function HowItWorks() {
  const steps = [
    {
      number: '1',
      title: 'Submit Samples',
      description: 'Ship your samples to our lab or schedule a pickup. We provide sample bags and submission forms.'
    },
    {
      number: '2',
      title: 'We Test',
      description: 'Our team runs your samples through our equipment. Results ready in 24-48 hours for cannabis, 48-72 for peptides.'
    },
    {
      number: '3',
      title: 'Get Results',
      description: 'Access your COA instantly through our client portal. Download, print, or share with QR codes.'
    }
  ]

  return (
    <section className="relative py-32 md:py-40 px-8 lg:px-12 bg-background overflow-hidden">
      {/* Background decoration */}
      <div className="absolute inset-0 opacity-10">
        <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-quantix-accent rounded-full blur-[128px]"></div>
        <div className="absolute bottom-1/4 right-1/4 w-96 h-96 bg-quantix-accent rounded-full blur-[128px]"></div>
      </div>

      <div className="max-w-7xl mx-auto relative">
        <div className="text-center mb-24">
          <div className="inline-block">
            <h2 className="text-5xl md:text-6xl font-bold mb-4">
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-white to-white/80">
                How It Works
              </span>
            </h2>
            <div className="h-1 w-24 bg-gradient-to-r from-quantix-accent via-quantix-accent to-transparent mx-auto"></div>
          </div>
          <p className="text-2xl text-white/60 mt-6">
            Simple process, fast results
          </p>
        </div>

        <div className="relative">
          {/* Connection line */}
          <div className="hidden md:block absolute top-24 left-0 right-0 h-0.5 bg-gradient-to-r from-transparent via-white/20 to-transparent"></div>

          <div className="grid md:grid-cols-3 gap-16 max-w-6xl mx-auto">
            {steps.map((step, index) => (
              <div key={index} className="relative">
                {/* Connecting dots */}
                <div className="hidden md:block absolute top-24 left-1/2 w-3 h-3 rounded-full bg-quantix-accent -translate-x-1/2 -translate-y-1/2"></div>

                <div className="glass-effect p-10 rounded-3xl hover:bg-white/[0.08] transition-all duration-300 group relative overflow-hidden depth-2 hover:depth-3">
                  {/* Number badge */}
                  <div className="w-20 h-20 rounded-2xl bg-gradient-to-br from-quantix-accent/20 to-quantix-accent/5 flex items-center justify-center mx-auto mb-6 group-hover:scale-110 transition-transform duration-300">
                    <span className="text-4xl font-bold text-white">
                      {step.number}
                    </span>
                  </div>

                  <h3 className="text-2xl font-bold text-white mb-4 text-center">
                    {step.title}
                  </h3>
                  <p className="text-base text-white/60 leading-relaxed text-center">
                    {step.description}
                  </p>

                  {/* Glow effect on hover */}
                  <div className="absolute inset-0 bg-gradient-to-br from-quantix-accent/10 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300 rounded-3xl"></div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  )
}
