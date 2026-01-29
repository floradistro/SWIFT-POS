'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import Logo from './Logo'

export default function Navigation() {
  const pathname = usePathname()

  const isActive = (path: string) => pathname === path

  return (
    <nav className="fixed top-0 left-0 right-0 z-50 bg-transparent backdrop-blur-xl">
      <div className="max-w-7xl mx-auto px-8 lg:px-12">
        <div className="flex items-center justify-between h-[72px]">
          {/* Logo */}
          <Logo />

          {/* Navigation Links */}
          <div className="hidden md:flex items-center gap-10">
            <Link
              href="/"
              className={`text-[15px] font-medium transition-all duration-200 ${
                isActive('/') ? 'text-white' : 'text-white/70 hover:text-white'
              }`}
            >
              Home
            </Link>
            <Link
              href="/services"
              className={`text-[15px] font-medium transition-all duration-200 ${
                isActive('/services') ? 'text-white' : 'text-white/70 hover:text-white'
              }`}
            >
              Services
            </Link>
            <Link
              href="/api"
              className={`text-[15px] font-medium transition-all duration-200 ${
                isActive('/api') ? 'text-white' : 'text-white/70 hover:text-white'
              }`}
            >
              API
            </Link>
            <Link
              href="/about"
              className={`text-[15px] font-medium transition-all duration-200 ${
                isActive('/about') ? 'text-white' : 'text-white/70 hover:text-white'
              }`}
            >
              About
            </Link>
          </div>

          {/* CTA Button */}
          <Link href="/login" className="bg-[#0071e3] hover:bg-[#0077ed] text-white px-5 py-2.5 rounded-lg font-medium transition-all duration-200 ease-out text-[15px]">
            Client Login
          </Link>
        </div>
      </div>
    </nav>
  )
}
