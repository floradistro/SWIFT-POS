'use client'

import Link from 'next/link'
import { Mail, Phone, Clock } from 'lucide-react'
import Logo from './Logo'

export default function Footer() {
  return (
    <footer className="relative border-t border-white/[0.08] py-16 px-8 lg:px-12 bg-background">
      <div className="max-w-7xl mx-auto">
        <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-12 mb-12">
          {/* Company Info */}
          <div className="space-y-4">
            <Logo showText={true} href="/" />
            <p className="text-[15px] text-white/60 leading-relaxed">
              Fast, accurate testing for cannabis and peptides.
            </p>
          </div>

          {/* Testing Services */}
          <div className="space-y-4">
            <h4 className="text-white font-semibold text-[15px]">Testing Services</h4>
            <ul className="space-y-2">
              <li>
                <Link href="/testing" className="text-[15px] text-white/60 hover:text-quantix-accent transition-colors duration-200">
                  Cannabis Testing
                </Link>
              </li>
              <li>
                <Link href="/testing" className="text-[15px] text-white/60 hover:text-quantix-accent transition-colors duration-200">
                  Peptide Analysis
                </Link>
              </li>
              <li>
                <Link href="/coa" className="text-[15px] text-white/60 hover:text-quantix-accent transition-colors duration-200">
                  Verify COA
                </Link>
              </li>
              <li>
                <Link href="/login" className="text-[15px] text-white/60 hover:text-quantix-accent transition-colors duration-200">
                  Client Portal
                </Link>
              </li>
            </ul>
          </div>

          {/* Support */}
          <div className="space-y-4">
            <h4 className="text-white font-semibold text-[15px]">Support</h4>
            <ul className="space-y-2">
              <li>
                <Link href="/about" className="text-[15px] text-white/60 hover:text-quantix-accent transition-colors duration-200">
                  About
                </Link>
              </li>
              <li>
                <Link href="/contact" className="text-[15px] text-white/60 hover:text-quantix-accent transition-colors duration-200">
                  Contact Us
                </Link>
              </li>
              <li>
                <Link href="/pricing" className="text-[15px] text-white/60 hover:text-quantix-accent transition-colors duration-200">
                  Pricing
                </Link>
              </li>
              <li>
                <a href="mailto:support@quantixanalytics.com" className="text-[15px] text-white/60 hover:text-quantix-accent transition-colors duration-200">
                  Email Support
                </a>
              </li>
            </ul>
          </div>

          {/* Contact */}
          <div className="space-y-4">
            <h4 className="text-white font-semibold text-[15px]">Get in Touch</h4>
            <ul className="space-y-3">
              <li className="flex items-center gap-3">
                <Phone className="w-4 h-4 text-quantix-accent flex-shrink-0" />
                <a href="tel:+19195550147" className="text-[15px] text-white/60 hover:text-white transition-colors duration-200">
                  (919) 555-0147
                </a>
              </li>
              <li className="flex items-center gap-3">
                <Mail className="w-4 h-4 text-quantix-accent flex-shrink-0" />
                <a href="mailto:support@quantixanalytics.com" className="text-[15px] text-white/60 hover:text-white transition-colors duration-200 break-all">
                  support@quantixanalytics.com
                </a>
              </li>
              <li className="flex items-start gap-3">
                <Clock className="w-4 h-4 text-quantix-accent flex-shrink-0 mt-0.5" />
                <span className="text-[15px] text-white/60 leading-relaxed">
                  Mon-Fri: 9AM-6PM EST
                </span>
              </li>
            </ul>
          </div>
        </div>

        {/* Bottom Bar */}
        <div className="pt-8 border-t border-white/[0.08] flex flex-col md:flex-row items-center justify-between gap-4">
          <p className="text-[13px] text-white/50">
            © 2026 Quantix Analytics. All rights reserved.
          </p>
          <div className="flex items-center gap-6">
            <Link href="/privacy" className="text-[13px] text-white/50 hover:text-white/70 transition-colors duration-200">
              Privacy
            </Link>
            <Link href="/terms" className="text-[13px] text-white/50 hover:text-white/70 transition-colors duration-200">
              Terms
            </Link>
          </div>
        </div>
      </div>
    </footer>
  )
}
