'use client'

export default function FAQ() {
  const faqs = [
    {
      question: 'What is the turnaround time?',
      answer: '24-48 hours for cannabis testing, 48-72 hours for peptide analysis. Rush options available.'
    },
    {
      question: 'How do I submit samples?',
      answer: 'Ship samples to our lab or request pickup. We provide submission forms and sample bags.'
    },
    {
      question: 'What states do you serve?',
      answer: 'We provide cannabis testing for all legal markets and meet state-specific requirements.'
    },
    {
      question: 'How do I access my results?',
      answer: 'Results are available instantly through our client portal with downloadable COAs and QR codes.'
    },
    {
      question: 'What payment methods do you accept?',
      answer: 'We accept credit cards, ACH transfers, and can set up billing accounts for regular clients.'
    },
    {
      question: 'Do you offer volume discounts?',
      answer: 'Yes, contact us for pricing on bulk testing or monthly contracts.'
    }
  ]

  return (
    <section className="relative py-32 md:py-40 px-8 lg:px-12 bg-background">
      <div className="max-w-4xl mx-auto">
        <div className="text-center mb-20">
          <div className="inline-block">
            <h2 className="text-5xl md:text-6xl font-bold mb-4">
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-white to-white/80">
                Common Questions
              </span>
            </h2>
            <div className="h-1 w-28 bg-gradient-to-r from-quantix-accent via-quantix-accent to-transparent mx-auto"></div>
          </div>
          <p className="text-xl text-white/60 mt-6">
            Everything you need to know
          </p>
        </div>

        <div className="space-y-6">
          {faqs.map((faq, index) => (
            <div
              key={index}
              className="glass-effect p-8 rounded-3xl hover:bg-white/[0.08] transition-all duration-300 group depth-1"
            >
              <h3 className="text-xl font-bold text-white mb-3">
                {faq.question}
              </h3>
              <p className="text-base text-white/60 leading-relaxed">
                {faq.answer}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
