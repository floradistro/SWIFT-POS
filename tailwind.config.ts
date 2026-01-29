import type { Config } from 'tailwindcss'

const config: Config = {
  content: [
    './pages/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
    './app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        'quantix': {
          dark: '#1a1a1a',
          gray: '#2a2a2a',
          'slate': '#0a0a0a',
          accent: '#3b82f6',
          'accent-hover': '#2563eb',
          'accent-light': '#60a5fa',
        },
        background: '#505050',
        surface: '#606060',
        'surface-light': '#707070',
      },
      fontFamily: {
        sans: ['-apple-system', 'BlinkMacSystemFont', 'SF Pro Display', 'Inter', 'Segoe UI', 'Helvetica Neue', 'Arial', 'sans-serif'],
      },
      fontSize: {
        'xs': ['13px', { lineHeight: '1.5', letterSpacing: '-0.003em' }],
        'sm': ['14px', { lineHeight: '1.5', letterSpacing: '-0.006em' }],
        'base': ['16px', { lineHeight: '1.6', letterSpacing: '-0.011em' }],
        'lg': ['18px', { lineHeight: '1.6', letterSpacing: '-0.011em' }],
        'xl': ['20px', { lineHeight: '1.5', letterSpacing: '-0.014em' }],
        '2xl': ['24px', { lineHeight: '1.4', letterSpacing: '-0.017em' }],
        '3xl': ['30px', { lineHeight: '1.3', letterSpacing: '-0.019em' }],
        '4xl': ['36px', { lineHeight: '1.2', letterSpacing: '-0.021em' }],
        '5xl': ['48px', { lineHeight: '1.1', letterSpacing: '-0.024em' }],
        '6xl': ['60px', { lineHeight: '1.05', letterSpacing: '-0.026em' }],
        '7xl': ['72px', { lineHeight: '1.05', letterSpacing: '-0.028em' }],
        '8xl': ['96px', { lineHeight: '1.05', letterSpacing: '-0.031em' }],
      },
      spacing: {
        '18': '4.5rem',
        '88': '22rem',
        '100': '25rem',
        '112': '28rem',
        '128': '32rem',
      },
      boxShadow: {
        'soft': '0 2px 16px -4px rgba(0, 0, 0, 0.3), 0 1px 4px -2px rgba(0, 0, 0, 0.25)',
        'soft-lg': '0 12px 48px -8px rgba(0, 0, 0, 0.4), 0 4px 12px -4px rgba(0, 0, 0, 0.3)',
        'glow': '0 4px 20px rgba(16, 185, 129, 0.4), 0 1px 4px rgba(16, 185, 129, 0.25)',
        'glow-lg': '0 8px 32px rgba(16, 185, 129, 0.5), 0 2px 8px rgba(16, 185, 129, 0.35)',
      },
      animation: {
        'fade-in': 'fadeIn 0.8s cubic-bezier(0.16, 1, 0.3, 1)',
        'slide-up': 'slideUp 0.8s cubic-bezier(0.16, 1, 0.3, 1)',
        'float': 'float 3s ease-in-out infinite',
      },
      keyframes: {
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        slideUp: {
          '0%': { opacity: '0', transform: 'translateY(24px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        float: {
          '0%, 100%': { transform: 'translateY(0px)' },
          '50%': { transform: 'translateY(-10px)' },
        },
      },
    },
  },
  plugins: [],
}
export default config
