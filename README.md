# Quantix Analytics - Cannabis Testing Laboratory

A professional, Apple-inspired website for Quantix Analytics, providing comprehensive cannabinoid potency analysis and compliance testing services.

## Features

### Current Implementation

- **Modern Homepage** - Clean, minimalist design with hero section, features showcase, and professional footer
- **Client Login Portal** - Secure authentication using Supabase Auth
- **Client Dashboard** - View and download Certificates of Analysis (COAs)
- **Semi-Dark Theme** - Dove gray color scheme inspired by Apple's design language
- **Responsive Design** - Mobile-first, fully responsive across all devices
- **Glass Morphism UI** - Modern glass effects and smooth transitions

### Design System

**Colors:**
- Background: `#0f0f1a`
- Surface: `#1a1a2e`
- Accent Green: `#16a34a`
- Dove Gray: `#6B6D76`
- Text Gray: `#8B8D98`

**Typography:**
- Font Family: Inter (Google Fonts)
- Clean, modern sans-serif

## Tech Stack

- **Framework:** Next.js 14 (App Router)
- **Language:** TypeScript
- **Styling:** Tailwind CSS
- **Authentication:** Supabase Auth
- **Database:** Supabase (PostgreSQL)
- **Icons:** Lucide React
- **Deployment Ready:** Vercel, Netlify, or any Node.js host

## Getting Started

### Prerequisites

- Node.js 18+
- npm or yarn
- Supabase account

### Environment Variables

Create a `.env.local` file with:

```env
NEXT_PUBLIC_SUPABASE_URL=your_supabase_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
QUANTIX_STORE_ID=bb73275b-edeb-4d1f-9c51-ddc57fa3a19b
```

### Installation

```bash
# Install dependencies
npm install

# Run development server
npm run dev

# Build for production
npm run build

# Start production server
npm start
```

### Access the Site

- Homepage: http://localhost:3002
- Login Portal: http://localhost:3002/login
- Dashboard: http://localhost:3002/dashboard (requires authentication)

## Project Structure

```
quantix-analytics/
├── app/
│   ├── components/
│   │   ├── Navigation.tsx    # Main navigation bar
│   │   ├── Hero.tsx          # Homepage hero section
│   │   ├── Features.tsx      # Features showcase
│   │   ├── Footer.tsx        # Site footer
│   │   └── Logo.tsx          # Quantix logo component
│   ├── login/
│   │   └── page.tsx          # Login page
│   ├── dashboard/
│   │   └── page.tsx          # Client dashboard
│   ├── layout.tsx            # Root layout
│   ├── page.tsx              # Homepage
│   └── globals.css           # Global styles
├── lib/
│   └── supabase.ts           # Supabase client config
├── .env.local                # Environment variables
├── next.config.js            # Next.js configuration
├── tailwind.config.ts        # Tailwind configuration
└── tsconfig.json             # TypeScript configuration
```

## Database Schema

### Key Tables

- `store_documents` - Stores COA documents
- `stores` - Store configuration (Quantix Analytics)
- `users` - User authentication (Supabase Auth)

## Next Steps

1. **Testing Services Page** - Create catalog of available tests
2. **COA Database** - Public searchable COA archive
3. **Contact Form** - Lead generation for new clients
4. **About Page** - Company information and credentials
5. **Product Integration** - Connect with actual testing service products

## Support

For questions or support:
- Email: fahad@cwscommercial.com
- Phone: (919) 555-0147
- Address: 4321 Innovation Drive, Suite 200, Raleigh, NC 27606

## License

Copyright © 2026 Quantix Analytics. All rights reserved.
