'use client'

import { useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { Mail, Lock, ArrowLeft, AlertCircle } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import Logo from '@/app/components/Logo'

export default function LoginPage() {
  const router = useRouter()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError('')

    try {
      const { data, error: signInError } = await supabase.auth.signInWithPassword({
        email,
        password,
      })

      if (signInError) throw signInError

      // Redirect to dashboard on success
      router.push('/dashboard')
    } catch (err: any) {
      setError(err.message || 'An error occurred during login')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center px-6 lg:px-8 bg-background">
      {/* Login Card */}
      <div className="relative w-full max-w-md">
        {/* Back to Home */}
        <Link
          href="/"
          className="inline-flex items-center space-x-2 text-white hover:opacity-80 transition-opacity mb-8"
        >
          <ArrowLeft className="w-4 h-4" />
          <span className="text-sm">Back to home</span>
        </Link>

        {/* Card */}
        <div className="glass-effect p-8 rounded-2xl space-y-8 shadow-soft-lg animate-fade-in">
          {/* Header */}
          <div className="text-center space-y-2">
            <div className="flex justify-center mb-4">
              <Logo size="lg" showText={false} href="/" />
            </div>
            <h1 className="text-3xl font-bold text-white">Client Portal</h1>
            <p className="text-white">
              Access your test results and certificates of analysis
            </p>
          </div>

          {/* Error Message */}
          {error && (
            <div className="bg-red-500/10 border border-red-500/20 rounded-lg p-4 flex items-start space-x-3">
              <AlertCircle className="w-5 h-5 text-red-400 flex-shrink-0 mt-0.5" />
              <p className="text-sm text-red-400">{error}</p>
            </div>
          )}

          {/* Form */}
          <form onSubmit={handleLogin} className="space-y-6">
            {/* Email Field */}
            <div className="space-y-2">
              <label htmlFor="email" className="text-sm font-medium text-white">
                Email Address
              </label>
              <div className="relative">
                <Mail className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-white/50" />
                <input
                  id="email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="you@company.com"
                  required
                  className="w-full pl-12 pr-4 py-3 bg-surface-light border border-white/10 rounded-lg text-white placeholder-white/50 focus:outline-none focus:border-quantix-accent focus:shadow-glow transition-all duration-300"
                />
              </div>
            </div>

            {/* Password Field */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <label htmlFor="password" className="text-sm font-medium text-white">
                  Password
                </label>
                <Link
                  href="/forgot-password"
                  className="text-sm text-quantix-accent hover:text-quantix-accent-hover transition-colors"
                >
                  Forgot password?
                </Link>
              </div>
              <div className="relative">
                <Lock className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-white/50" />
                <input
                  id="password"
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="••••••••"
                  required
                  className="w-full pl-12 pr-4 py-3 bg-surface-light border border-white/10 rounded-lg text-white placeholder-white/50 focus:outline-none focus:border-quantix-accent focus:shadow-glow transition-all duration-300"
                />
              </div>
            </div>

            {/* Submit Button */}
            <button
              type="submit"
              disabled={loading}
              className="w-full btn-primary py-4 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {loading ? 'Signing in...' : 'Sign In'}
            </button>
          </form>

          {/* Divider */}
          <div className="relative">
            <div className="absolute inset-0 flex items-center">
              <div className="w-full border-t border-white/10"></div>
            </div>
            <div className="relative flex justify-center text-sm">
              <span className="px-4 bg-surface text-white">New client?</span>
            </div>
          </div>

          {/* Contact CTA */}
          <div className="text-center space-y-4">
            <p className="text-sm text-white">
              Don't have an account yet? Contact us to get started with testing services.
            </p>
            <Link href="/contact" className="btn-secondary inline-block">
              Contact Sales
            </Link>
          </div>
        </div>

        {/* Footer Note */}
        <p className="text-center text-sm text-white mt-8">
          By signing in, you agree to our{' '}
          <Link href="/terms" className="text-quantix-accent hover:underline">
            Terms of Service
          </Link>
          {' '}and{' '}
          <Link href="/privacy" className="text-quantix-accent hover:underline">
            Privacy Policy
          </Link>
        </p>
      </div>
    </div>
  )
}
