'use client'

export default function ContactPage() {
  return (
    <main className="min-h-screen pt-[72px]">
      {/* Hero Section */}
      <section className="relative py-32 md:py-40 px-8 lg:px-12 bg-background overflow-hidden">
        <div className="absolute inset-0 opacity-10">
          <div className="absolute top-1/3 left-1/3 w-96 h-96 bg-quantix-accent rounded-full blur-[128px]"></div>
        </div>

        <div className="max-w-4xl mx-auto relative text-center">
          <div className="inline-block mb-6">
            <h1 className="text-6xl md:text-7xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-white via-white to-white/70 mb-4">
              Contact Us
            </h1>
            <div className="h-1 w-32 bg-gradient-to-r from-transparent via-quantix-accent to-transparent mx-auto"></div>
          </div>
          <p className="text-2xl text-white/70 max-w-3xl mx-auto">
            Get in touch with our team
          </p>
        </div>
      </section>

      {/* Contact Info & Form */}
      <section className="relative py-24 md:py-32 px-8 lg:px-12 bg-surface">
        <div className="max-w-6xl mx-auto">
          <div className="grid lg:grid-cols-2 gap-16">
            {/* Contact Information */}
            <div className="space-y-12">
              <div>
                <h2 className="text-4xl md:text-5xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-white to-white/80 mb-4">
                  Get Started
                </h2>
                <div className="h-1 w-20 bg-gradient-to-r from-quantix-accent to-transparent mb-6"></div>
                <p className="text-xl text-white/70">
                  Ready to submit samples or have questions about our testing services? Contact us today.
                </p>
              </div>

              <div className="space-y-8">
                <div className="glass-effect p-8 rounded-3xl depth-1">
                  <h3 className="text-2xl font-bold text-white mb-3">Email</h3>
                  <a href="mailto:support@quantixanalytics.com" className="text-xl text-white/70 hover:text-white transition-colors">
                    support@quantixanalytics.com
                  </a>
                </div>

                <div className="glass-effect p-8 rounded-3xl depth-1">
                  <h3 className="text-2xl font-bold text-white mb-3">Phone</h3>
                  <a href="tel:+19195550147" className="text-xl text-white/70 hover:text-white transition-colors">
                    (919) 555-0147
                  </a>
                </div>

                <div className="glass-effect p-8 rounded-3xl depth-1">
                  <h3 className="text-2xl font-bold text-white mb-3">Hours</h3>
                  <p className="text-xl text-white/70">
                    Monday - Friday: 9am - 6pm EST<br />
                    Saturday: 10am - 4pm EST<br />
                    Sunday: Closed
                  </p>
                </div>
              </div>
            </div>

            {/* Contact Form */}
            <div className="glass-effect p-10 rounded-3xl depth-2">
              <h3 className="text-3xl font-bold text-white mb-8">Send a Message</h3>

              <form className="space-y-6">
                <div>
                  <label htmlFor="name" className="block text-sm font-semibold text-white mb-2">
                    Name
                  </label>
                  <input
                    type="text"
                    id="name"
                    name="name"
                    className="w-full px-5 py-4 bg-white/5 border border-white/10 rounded-2xl text-white placeholder-white/40 focus:outline-none focus:border-quantix-accent transition-colors"
                    placeholder="Your name"
                  />
                </div>

                <div>
                  <label htmlFor="email" className="block text-sm font-semibold text-white mb-2">
                    Email
                  </label>
                  <input
                    type="email"
                    id="email"
                    name="email"
                    className="w-full px-5 py-4 bg-white/5 border border-white/10 rounded-2xl text-white placeholder-white/40 focus:outline-none focus:border-quantix-accent transition-colors"
                    placeholder="your@email.com"
                  />
                </div>

                <div>
                  <label htmlFor="company" className="block text-sm font-semibold text-white mb-2">
                    Company
                  </label>
                  <input
                    type="text"
                    id="company"
                    name="company"
                    className="w-full px-5 py-4 bg-white/5 border border-white/10 rounded-2xl text-white placeholder-white/40 focus:outline-none focus:border-quantix-accent transition-colors"
                    placeholder="Your company name"
                  />
                </div>

                <div>
                  <label htmlFor="service" className="block text-sm font-semibold text-white mb-2">
                    Service Interest
                  </label>
                  <select
                    id="service"
                    name="service"
                    className="w-full px-5 py-4 bg-white/5 border border-white/10 rounded-2xl text-white focus:outline-none focus:border-quantix-accent transition-colors"
                  >
                    <option value="">Select a service</option>
                    <option value="cannabis">Cannabis Testing</option>
                    <option value="peptide">Peptide Testing</option>
                    <option value="both">Both Services</option>
                    <option value="other">Other</option>
                  </select>
                </div>

                <div>
                  <label htmlFor="message" className="block text-sm font-semibold text-white mb-2">
                    Message
                  </label>
                  <textarea
                    id="message"
                    name="message"
                    rows={5}
                    className="w-full px-5 py-4 bg-white/5 border border-white/10 rounded-2xl text-white placeholder-white/40 focus:outline-none focus:border-quantix-accent transition-colors resize-none"
                    placeholder="Tell us about your testing needs..."
                  ></textarea>
                </div>

                <button
                  type="submit"
                  className="w-full bg-quantix-accent text-white px-8 py-4 rounded-full font-semibold transition-all duration-200 ease-out hover:bg-quantix-accent-hover hover:shadow-glow-lg hover:scale-105 active:scale-100 text-[15px] shadow-glow"
                >
                  Send Message
                </button>
              </form>
            </div>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="relative py-32 md:py-40 px-8 lg:px-12 bg-background">
        <div className="max-w-4xl mx-auto text-center">
          <h2 className="text-5xl font-bold text-white mb-6">
            Prefer to Email Directly?
          </h2>
          <p className="text-xl text-white/70 mb-10">
            Send sample submission inquiries or questions anytime
          </p>
          <a href="mailto:support@quantixanalytics.com" className="inline-block bg-quantix-accent text-white px-8 py-4 rounded-full font-semibold transition-all duration-200 ease-out hover:bg-quantix-accent-hover hover:shadow-glow-lg hover:scale-105 active:scale-100 text-[15px] shadow-glow">
            Email Support
          </a>
        </div>
      </section>
    </main>
  )
}
