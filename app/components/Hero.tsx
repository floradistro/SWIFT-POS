'use client'

import { useState, useEffect } from 'react'
import Link from 'next/link'
import { ArrowRight, FlaskConical, ChevronLeft, ChevronRight } from 'lucide-react'
import Logo from './Logo'

const slides = [
  {
    id: 'cannabis',
    image: '/images/hero-cannabis.png',
    title: 'Cannabis',
    industry: 'Industry Client',
    subtitle: 'Growers • Manufacturers • Processors',
    description: 'Full compliance testing for your harvest',
    cta: 'Test Your Product'
  },
  {
    id: 'retailer',
    image: '/images/hero-retailer.png',
    title: 'Cannabis',
    industry: 'Industry Client',
    subtitle: 'Retailers • Dispensaries • Distributors',
    description: 'COA verification and product compliance',
    cta: 'Verify Your Inventory'
  },
  {
    id: 'peptide',
    image: '/images/hero-peptide.png',
    title: 'Peptides',
    industry: 'Industry Client',
    subtitle: 'Manufacturers • Research • Production',
    description: 'HPLC purity verification and quality assurance',
    cta: 'Verify Purity'
  }
]

export default function Hero() {
  const [currentSlide, setCurrentSlide] = useState(0)
  const [isTransitioning, setIsTransitioning] = useState(false)

  useEffect(() => {
    const timer = setInterval(() => {
      if (!isTransitioning) {
        setIsTransitioning(true)
        setCurrentSlide((prev) => (prev + 1) % slides.length)
        setTimeout(() => setIsTransitioning(false), 1000)
      }
    }, 6000) // Auto-advance every 6 seconds
    return () => clearInterval(timer)
  }, [isTransitioning, currentSlide])

  const nextSlide = () => {
    if (isTransitioning) return
    setIsTransitioning(true)
    setCurrentSlide((prev) => (prev + 1) % slides.length)
    setTimeout(() => setIsTransitioning(false), 1000)
  }

  const prevSlide = () => {
    if (isTransitioning) return
    setIsTransitioning(true)
    setCurrentSlide((prev) => (prev - 1 + slides.length) % slides.length)
    setTimeout(() => setIsTransitioning(false), 1000)
  }

  const slide = slides[currentSlide]

  return (
    <section className="relative min-h-screen flex items-center justify-center overflow-hidden">
      {/* Background Image Slider with Effects */}
      <div className="absolute inset-0 z-0">
        {slides.map((s, index) => (
          <div
            key={s.id}
            className={`absolute inset-0 transition-all duration-1000 ease-in-out ${
              index === currentSlide
                ? 'opacity-100 scale-100'
                : 'opacity-0 scale-105'
            }`}
          >
            <img
              src={s.image}
              alt={s.title}
              className="w-full h-full object-cover animate-ken-burns"
              loading={index === 0 ? 'eager' : 'lazy'}
              fetchpriority={index === 0 ? 'high' : 'auto'}
            />
            {/* Balanced gradient overlay */}
            <div className="absolute inset-0 bg-gradient-to-b from-black/40 via-black/50 to-black/60"></div>
            {/* Subtle center vignette */}
            <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,transparent_40%,rgba(0,0,0,0.3)_100%)]"></div>
          </div>
        ))}
      </div>

      {/* Navigation Arrows */}
      <button
        onClick={prevSlide}
        disabled={isTransitioning}
        className="absolute left-8 z-20 p-3 rounded-full glass-effect hover:bg-white/10 transition-all duration-200 disabled:opacity-50"
        aria-label="Previous slide"
      >
        <ChevronLeft className="w-6 h-6 text-white" />
      </button>
      <button
        onClick={nextSlide}
        disabled={isTransitioning}
        className="absolute right-8 z-20 p-3 rounded-full glass-effect hover:bg-white/10 transition-all duration-200 disabled:opacity-50"
        aria-label="Next slide"
      >
        <ChevronRight className="w-6 h-6 text-white" />
      </button>

      {/* Slide Indicators */}
      <div className="absolute bottom-8 left-1/2 -translate-x-1/2 z-20 flex gap-3">
        {slides.map((_, index) => (
          <button
            key={index}
            onClick={() => {
              if (!isTransitioning) {
                setIsTransitioning(true)
                setCurrentSlide(index)
                setTimeout(() => setIsTransitioning(false), 1000)
              }
            }}
            className={`h-1.5 rounded-full transition-all duration-300 ${
              index === currentSlide
                ? 'w-12 bg-quantix-accent'
                : 'w-1.5 bg-white/40 hover:bg-white/60'
            }`}
            aria-label={`Go to slide ${index + 1}`}
          />
        ))}
      </div>

      {/* Content with enhanced backdrop */}
      <div className="relative z-10 max-w-7xl mx-auto px-8 lg:px-12 py-40 md:py-48">
        <div className="text-center space-y-10 max-w-5xl mx-auto">
          <div className="relative">
            {/* Logo */}
            <div
              key={`logo-${currentSlide}`}
              className="inline-flex items-center justify-center animate-fade-in mb-8"
            >
              <div className="scale-[3] transform">
                <Logo size="lg" showText={false} href={null} />
              </div>
            </div>

            {/* Main heading with text stroke effect */}
            <h1
              key={`title-${currentSlide}`}
              className="text-6xl md:text-7xl lg:text-8xl font-bold text-white animate-slide-up mt-8"
              style={{
                textShadow: '0 2px 40px rgba(0,0,0,0.5), 0 4px 12px rgba(0,0,0,0.3)'
              }}
            >
              {slide.title}
            </h1>

            {/* Subtitle with client types */}
            <p
              key={`subtitle-${currentSlide}`}
              className="text-xl md:text-2xl text-white/90 font-medium mt-6 animate-slide-up"
              style={{
                textShadow: '0 2px 20px rgba(0,0,0,0.5)',
                animationDelay: '0.05s'
              }}
            >
              {slide.subtitle}
            </p>

            {/* Description */}
            <div
              key={`desc-${currentSlide}`}
              className="space-y-5 animate-slide-up mt-8"
              style={{ animationDelay: '0.1s' }}
            >
              <p className="text-lg md:text-xl text-white/80 max-w-3xl mx-auto"
                 style={{ textShadow: '0 2px 20px rgba(0,0,0,0.5)' }}>
                {slide.description}
              </p>
              <p className="text-base md:text-lg text-white/70 max-w-2xl mx-auto"
                 style={{ textShadow: '0 2px 12px rgba(0,0,0,0.4)' }}>
                Fast Results • Detailed Reports • Full Compliance
              </p>
            </div>

            {/* CTA Buttons */}
            <div
              className="flex flex-col sm:flex-row items-center justify-center gap-4 pt-10 animate-slide-up"
              style={{ animationDelay: '0.2s' }}
            >
              <Link href="/testing" className="bg-[#0071e3] hover:bg-[#0077ed] text-white px-6 py-3 rounded-lg font-medium transition-all duration-200 ease-out text-[17px] shadow-sm">
                {slide.cta}
              </Link>
              <Link href="/login" className="bg-transparent hover:bg-white/5 text-[#0071e3] px-6 py-3 rounded-lg font-medium transition-all duration-200 text-[17px]">
                Client Portal
              </Link>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
