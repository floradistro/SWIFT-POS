'use client'

export default function Trust() {
  return (
    <section className="relative py-32 md:py-40 px-8 lg:px-12 bg-surface overflow-hidden">
      {/* Background gradient orbs */}
      <div className="absolute inset-0 opacity-5">
        <div className="absolute top-0 left-1/4 w-[500px] h-[500px] bg-white rounded-full blur-[100px]"></div>
        <div className="absolute bottom-0 right-1/4 w-[500px] h-[500px] bg-white rounded-full blur-[100px]"></div>
      </div>

      <div className="max-w-6xl mx-auto relative">
        <div className="text-center space-y-8 mb-20">
          <div className="inline-block">
            <h2 className="text-5xl md:text-6xl font-bold leading-tight mb-4">
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-white via-white to-white/70">
                Trusted by Industry Leaders
              </span>
            </h2>
            <div className="h-1 w-32 bg-gradient-to-r from-transparent via-quantix-accent to-transparent mx-auto"></div>
          </div>
          <p className="text-xl text-white/60 leading-relaxed max-w-3xl mx-auto">
            ISO-compliant lab standards meeting all state regulatory requirements across legal cannabis markets
          </p>
        </div>

        <div className="grid md:grid-cols-3 gap-8">
          <div className="glass-effect p-12 rounded-3xl text-center group hover:bg-white/[0.08] transition-all duration-300 depth-2">
            <div className="w-24 h-24 rounded-2xl bg-gradient-to-br from-quantix-accent/20 to-quantix-accent/5 flex items-center justify-center mx-auto mb-6 group-hover:scale-110 transition-transform duration-300">
              <p className="text-4xl font-bold text-white">ISO</p>
            </div>
            <p className="text-lg text-white/70">Compliant laboratory processes</p>
          </div>

          <div className="glass-effect p-12 rounded-3xl text-center group hover:bg-white/[0.08] transition-all duration-300 depth-2">
            <div className="w-24 h-24 rounded-2xl bg-gradient-to-br from-quantix-accent/20 to-quantix-accent/5 flex items-center justify-center mx-auto mb-6 group-hover:scale-110 transition-transform duration-300">
              <p className="text-4xl font-bold text-white">50</p>
            </div>
            <p className="text-lg text-white/70">States served nationwide</p>
          </div>

          <div className="glass-effect p-12 rounded-3xl text-center group hover:bg-white/[0.08] transition-all duration-300 depth-2">
            <div className="w-24 h-24 rounded-2xl bg-gradient-to-br from-quantix-accent/20 to-quantix-accent/5 flex items-center justify-center mx-auto mb-6 group-hover:scale-110 transition-transform duration-300">
              <p className="text-4xl font-bold text-white">24/7</p>
            </div>
            <p className="text-lg text-white/70">Digital COA access</p>
          </div>
        </div>
      </div>
    </section>
  )
}
