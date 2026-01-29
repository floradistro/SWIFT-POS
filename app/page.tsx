import Navigation from './components/Navigation'
import Hero from './components/Hero'
import Features from './components/Features'
import HowItWorks from './components/HowItWorks'
import Services from './components/Services'
import Trust from './components/Trust'
import FAQ from './components/FAQ'
import Footer from './components/Footer'

export default function Home() {
  return (
    <main className="min-h-screen antialiased">
      <Navigation />
      <Hero />
      <Features />
      <HowItWorks />
      <Services />
      <Trust />
      <FAQ />
      <Footer />
    </main>
  )
}
