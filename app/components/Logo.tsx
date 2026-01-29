'use client'

import Image from 'next/image'
import Link from 'next/link'

interface LogoProps {
  size?: 'sm' | 'md' | 'lg'
  showText?: boolean
  href?: string
}

export default function Logo({ size = 'md', showText = true, href = '/' }: LogoProps) {
  const sizes = {
    sm: { box: 'w-8 h-8', text: 'text-base', subtext: 'text-xs' },
    md: { box: 'w-10 h-10', text: 'text-lg', subtext: 'text-xs' },
    lg: { box: 'w-16 h-16', text: 'text-2xl', subtext: 'text-sm' },
  }

  const { box, text, subtext } = sizes[size]

  // Quantix logo URL from Supabase storage
  const logoUrl = 'https://uaednwpxursknmwdeejn.supabase.co/storage/v1/object/public/vendor-logos/bb73275b-edeb-4d1f-9c51-ddc57fa3a19b/quantixlogo.png'

  const logoContent = (
    <div className="flex items-center space-x-3 group cursor-pointer">
      <div className={`${box} flex items-center justify-center group-hover:scale-105 transition-all duration-300 relative drop-shadow-lg group-hover:drop-shadow-xl`}>
        <div className="relative w-full h-full">
          <Image
            src={logoUrl}
            alt="Quantix Analytics"
            fill
            className="object-contain"
            onError={(e) => {
              // Fallback to letter Q if image fails to load
              const target = e.target as HTMLImageElement
              target.style.display = 'none'
              const parent = target.parentElement
              if (parent) {
                parent.innerHTML = '<span class="text-white font-bold text-xl">Q</span>'
                parent.classList.add('flex', 'items-center', 'justify-center')
              }
            }}
          />
        </div>
      </div>
      {showText && (
        <div className="flex flex-col justify-center">
          <span className={`text-white font-bold ${text} leading-tight tracking-tight`}>Quantix</span>
          <span className={`text-white ${subtext} leading-tight font-medium`}>Analytics</span>
        </div>
      )}
    </div>
  )

  if (href) {
    return <Link href={href}>{logoContent}</Link>
  }

  return logoContent
}
