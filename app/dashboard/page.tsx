'use client'

import { useEffect, useState, useRef } from 'react'
import { useRouter } from 'next/navigation'
import { FileText, Download, Calendar, Search, Filter, LogOut } from 'lucide-react'
import { supabase, QUANTIX_STORE_ID } from '@/lib/supabase'
import Logo from '@/app/components/Logo'

// PDF Preview Component with lazy iframe loading
function PDFPreview({ pdfUrl, title }: { pdfUrl: string; title: string }) {
  const [isVisible, setIsVisible] = useState(false)
  const [isLoaded, setIsLoaded] = useState(false)
  const containerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!containerRef.current) return

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            setIsVisible(true)
          }
        })
      },
      {
        rootMargin: '200px', // Start loading earlier
        threshold: 0.01
      }
    )

    observer.observe(containerRef.current)
    return () => observer.disconnect()
  }, [])

  return (
    <div ref={containerRef} className="w-full h-full relative bg-gradient-to-br from-gray-50 to-gray-100">
      <div className="absolute inset-0 flex items-center justify-center">
        <FileText className={`w-12 h-12 text-gray-300 ${isVisible && !isLoaded ? 'animate-pulse' : ''}`} />
      </div>
      {isVisible && (
        <iframe
          src={`${pdfUrl}#view=FitH&toolbar=0&navpanes=0&scrollbar=0&page=1`}
          className="w-full h-full absolute inset-0"
          style={{
            filter: 'brightness(0.95)',
            pointerEvents: 'none',
            opacity: isLoaded ? 1 : 0,
            transition: 'opacity 0.4s ease-in-out'
          }}
          onLoad={() => setIsLoaded(true)}
        />
      )}
    </div>
  )
}

interface COA {
  id: string
  document_name: string
  file_url: string
  created_at: string
  store_id: string
  thumbnail_url?: string
  product_id?: string
  product?: {
    primary_category_id?: string
    primary_category?: {
      id: string
      name: string
      slug: string
      icon: string
    }
  }
  metadata?: {
    sample_id?: string
    test_type?: string
    status?: string
  }
}

interface Store {
  id: string
  store_name: string
  slug: string
}

export default function DashboardPage() {
  const router = useRouter()
  const [loading, setLoading] = useState(true)
  const [user, setUser] = useState<any>(null)
  const [stores, setStores] = useState<Store[]>([])
  const [selectedStore, setSelectedStore] = useState<string>('all')
  const [coas, setCoas] = useState<COA[]>([])
  const [searchTerm, setSearchTerm] = useState('')
  const [filterType, setFilterType] = useState<string>('all')
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null)
  const [page, setPage] = useState(1)
  const [hasMore, setHasMore] = useState(true)
  const [isLoadingMore, setIsLoadingMore] = useState(false)
  const ITEMS_PER_PAGE = 50

  useEffect(() => {
    checkUser()
  }, [])

  useEffect(() => {
    if (user) {
      loadStoresAndCOAs()
    }
  }, [user])

  useEffect(() => {
    if (user && selectedStore && selectedStore !== 'all') {
      setPage(1)
      loadCOAsForStore(selectedStore, 1)
    }
  }, [selectedStore, user])

  const checkUser = async () => {
    const { data: { session } } = await supabase.auth.getSession()

    console.log('🔐 Session check:', { hasSession: !!session, user: session?.user })

    if (!session) {
      router.push('/login')
      return
    }

    console.log('👤 User email:', session.user.email)
    console.log('🆔 User ID:', session.user.id)

    setUser(session.user)
    setLoading(false)
  }

  const loadStoresAndCOAs = async () => {
    try {
      console.log('🔍 Starting loadStoresAndCOAs')
      console.log('📧 User object:', user)
      console.log('🆔 User ID:', user?.id)

      if (!user || !user.id) {
        console.error('❌ No user or user.id found')
        return
      }

      // Get user's platform user record
      const { data: platformUser, error: userError } = await supabase
        .from('platform_users')
        .select('id')
        .eq('auth_id', user.id)
        .single()

      console.log('📦 Platform user response:', { platformUser, userError })

      if (userError) {
        console.error('❌ Platform user error:', userError)
        throw userError
      }

      if (!platformUser) {
        console.error('❌ No platform user found')
        return
      }

      console.log('✅ Platform user:', platformUser)

      // Get all stores the user owns or has access to
      const { data: userStores, error: storesError } = await supabase
        .from('stores')
        .select('id, store_name, slug')
        .eq('owner_user_id', platformUser.id)

      console.log('🏪 Stores response:', { userStores, storesError })

      if (storesError) {
        console.error('❌ Stores error:', storesError)
        throw storesError
      }

      console.log('🏪 User stores found:', userStores?.length || 0)
      console.log('🏪 Stores data:', userStores)

      setStores(userStores || [])
      console.log('✅ Stores state updated with', userStores?.length || 0, 'stores')

      // Set first store as default if available
      if (userStores && userStores.length > 0) {
        setSelectedStore(userStores[0].id)
      }
    } catch (err) {
      console.error('❌ Error loading data:', err)
    }
  }

  const loadCOAsForStore = async (storeId: string, pageNum: number = 1) => {
    try {
      console.log('🔍 Loading COAs for store:', storeId, 'page:', pageNum)
      setIsLoadingMore(true)

      const from = (pageNum - 1) * ITEMS_PER_PAGE
      const to = from + ITEMS_PER_PAGE - 1

      const { data: storeCoas, error: coasError, count } = await supabase
        .from('store_documents')
        .select(`
          id,
          document_name,
          file_url,
          created_at,
          store_id,
          metadata,
          document_type,
          thumbnail_url,
          product_id,
          products!inner(
            primary_category_id,
            categories!products_primary_category_id_fkey(
              id,
              name,
              slug,
              icon
            )
          )
        `, { count: 'exact' })
        .eq('store_id', storeId)
        .eq('is_active', true)
        .not('product_id', 'is', null)
        .order('created_at', { ascending: false })
        .range(from, to)

      if (coasError) {
        console.error('❌ Error loading COAs:', coasError)
        setIsLoadingMore(false)
        return
      }

      console.log('📄 Loaded', storeCoas?.length || 0, 'COAs for store (total:', count, ')')

      if (pageNum === 1) {
        setCoas(storeCoas || [])
      } else {
        setCoas(prev => [...prev, ...(storeCoas || [])])
      }

      setHasMore((count || 0) > pageNum * ITEMS_PER_PAGE)
      setIsLoadingMore(false)
    } catch (err) {
      console.error('❌ Error loading COAs:', err)
      setIsLoadingMore(false)
    }
  }

  const handleLogout = async () => {
    await supabase.auth.signOut()
    router.push('/')
  }

  // Get categories from actual database categories (not guessed from names)
  const categoryMap = new Map<string, {id: string, name: string, slug: string, icon: string, count: number}>()

  coas.forEach(coa => {
    const category = (coa.products as any)?.categories
    if (category && (selectedStore === 'all' || coa.store_id === selectedStore)) {
      const existing = categoryMap.get(category.id) || { ...category, count: 0 }
      existing.count++
      categoryMap.set(category.id, existing)
    }
  })

  const categories = Array.from(categoryMap.values()).sort((a, b) => b.count - a.count)

  const filteredCOAs = coas.filter(coa => {
    const category = (coa.products as any)?.categories
    const matchesCategory = !selectedCategory || category?.id === selectedCategory

    const matchesSearch = coa.document_name?.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         coa.metadata?.sample_id?.toLowerCase().includes(searchTerm.toLowerCase())

    const matchesFilter = filterType === 'all' || coa.metadata?.test_type === filterType

    // No need to filter by store since we're only loading one store's COAs
    return matchesCategory && matchesSearch && matchesFilter
  })

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <div className="text-center space-y-4">
          <div className="w-16 h-16 border-4 border-[#0071e3] border-t-transparent rounded-full animate-spin mx-auto"></div>
          <p className="text-white">Loading...</p>
        </div>
      </div>
    )
  }

  return (
    <main className="min-h-screen bg-background">
      {/* Header - Edge to Edge */}
      <div className="bg-background border-b border-white/10">
        <div className="px-4 sm:px-6 py-6 flex items-center justify-between">
          <div className="flex items-center gap-4">
            <Logo size="sm" showText={false} href="/" />
            <div>
              <h1 className="text-2xl font-bold text-white">Dashboard</h1>
              <p className="text-sm text-white/60">{user?.email}</p>
            </div>
          </div>
          <button
            onClick={handleLogout}
            className="flex items-center gap-2 text-white/60 hover:text-white transition-colors"
          >
            <LogOut className="w-5 h-5" />
            <span className="hidden sm:inline text-sm">Sign Out</span>
          </button>
        </div>
      </div>

      {/* Store Selector - Always Visible */}
      {stores.length > 0 && (
        <div className="bg-surface/50 border-b border-white/10">
          <div className="px-4 sm:px-6 py-4">
            <select
              value={selectedStore}
              onChange={(e) => {
                const newStoreId = e.target.value
                setSelectedStore(newStoreId)
                setSelectedCategory(null) // Reset category when store changes
                setPage(1) // Reset pagination
                if (newStoreId !== 'all') {
                  loadCOAsForStore(newStoreId, 1)
                }
              }}
              className="bg-white/5 border border-white/10 rounded-lg pl-4 pr-10 py-2.5 text-white appearance-none cursor-pointer focus:outline-none focus:border-[#0071e3]/50 transition-colors w-full sm:w-auto min-w-[200px]"
            >
              {stores.map(store => (
                <option key={store.id} value={store.id}>
                  {store.store_name}
                </option>
              ))}
            </select>
          </div>
        </div>
      )}

      {/* Category Selection or Filters */}
      {!selectedCategory ? (
        <div className="px-4 sm:px-6 py-12">
          <h2 className="text-2xl font-bold text-white mb-8 text-center">Select Product Category</h2>
          <div className="max-w-2xl mx-auto">
            {categories.map((category) => (
              <button
                key={category.id}
                onClick={() => setSelectedCategory(category.id)}
                className="group w-full bg-white/5 hover:bg-white/10 border border-white/10 hover:border-[#0071e3]/50 rounded-lg p-4 mb-3 transition-all duration-200 hover:translate-x-1 flex items-center justify-between"
              >
                <div className="flex items-center gap-4">
                  <div className="w-2 h-2 rounded-full bg-[#0071e3] group-hover:scale-125 transition-transform"></div>
                  <h3 className="text-white font-medium text-lg group-hover:text-[#0071e3] transition-colors">
                    {category.name}
                  </h3>
                </div>
                <div className="flex items-center gap-3">
                  <span className="text-white/60 text-sm">
                    {category.count} {category.count === 1 ? 'certificate' : 'certificates'}
                  </span>
                  <span className="text-white/40 group-hover:text-[#0071e3] transition-colors">→</span>
                </div>
              </button>
            ))}
          </div>
        </div>
      ) : (
        <>
          {/* Filters - Sticky */}
          <div className="bg-surface/50 border-b border-white/10 sticky top-0 z-10 backdrop-blur-xl">
            <div className="px-4 sm:px-6 py-4 flex flex-col sm:flex-row gap-3 items-center">
              {/* Back Button */}
              <button
                onClick={() => setSelectedCategory(null)}
                className="flex items-center gap-2 text-white/60 hover:text-white transition-colors"
              >
                <span>←</span>
                <span className="text-sm">Back to Categories</span>
              </button>

              <div className="flex-1" />

              {/* Search */}
              <div className="flex-1 relative min-w-[200px]">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-white/40" />
                <input
                  type="text"
                  placeholder="Search..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="w-full bg-white/5 border border-white/10 rounded-lg pl-10 pr-4 py-2.5 text-white placeholder-white/40 focus:outline-none focus:border-[#0071e3]/50 transition-colors"
                />
              </div>

              {/* Test Type Filter */}
              <div className="relative">
                <Filter className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-white/40 pointer-events-none" />
                <select
                  value={filterType}
                  onChange={(e) => setFilterType(e.target.value)}
                  className="bg-white/5 border border-white/10 rounded-lg pl-10 pr-10 py-2.5 text-white appearance-none cursor-pointer focus:outline-none focus:border-[#0071e3]/50 transition-colors w-full sm:w-auto"
                >
                  <option value="all">All Tests</option>
                  <option value="cannabis">Cannabis</option>
                  <option value="peptide">Peptide</option>
                  <option value="potency">Potency</option>
                  <option value="safety">Safety</option>
                </select>
              </div>
            </div>
          </div>

          {/* COA Grid */}
          <div className="px-4 sm:px-6 py-6">
            {/* Category Header */}
            <div className="mb-6">
              <h2 className="text-2xl font-bold text-white mb-1">
                {categories.find(c => c.id === selectedCategory)?.name || 'Products'}
              </h2>
              <p className="text-white/60 text-sm">
                Showing {filteredCOAs.length} {filteredCOAs.length === 1 ? 'certificate' : 'certificates'}
              </p>
            </div>

            {filteredCOAs.length === 0 ? (
          <div className="text-center py-20">
            <FileText className="w-16 h-16 text-white/20 mx-auto mb-4" />
            <h3 className="text-xl font-semibold text-white mb-2">
              {searchTerm || filterType !== 'all' ? 'No results found' : 'No COAs yet'}
            </h3>
            <p className="text-white/60">
              {searchTerm || filterType !== 'all'
                ? 'Try adjusting your filters'
                : 'Your certificates will appear here once testing is complete'}
            </p>
          </div>
        ) : (
          <>
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-6">
              {filteredCOAs.map((coa) => (
                <a
                  key={coa.id}
                  href={coa.file_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="group block transition-all duration-200"
                >
                  {/* Preview Card */}
                  <div className="aspect-[8.5/11] bg-white rounded-lg shadow-2xl overflow-hidden mb-3 group-hover:shadow-[0_20px_60px_-15px_rgba(0,0,0,0.5)] transition-all duration-200 relative group-hover:scale-[1.02]">
                    <PDFPreview pdfUrl={coa.file_url} title={coa.document_name} />

                    {/* Hover brightness overlay */}
                    <div className="absolute inset-0 bg-black/5 group-hover:bg-black/10 transition-all duration-200 pointer-events-none"></div>
                  </div>

                  {/* Info Below */}
                  <div className="px-1">
                    <h3 className="text-white text-sm font-medium truncate mb-1 group-hover:text-[#0071e3] transition-colors">
                      {coa.document_name || `COA #${coa.id.slice(0, 8)}`}
                    </h3>
                    <div className="flex items-center gap-2 text-xs text-white/50">
                      <span>{new Date(coa.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}</span>
                    </div>
                  </div>
                </a>
              ))}
            </div>

            {/* Load More Button */}
            {hasMore && (
              <div className="flex justify-center mt-12">
                <button
                  onClick={() => {
                    const nextPage = page + 1
                    setPage(nextPage)
                    loadCOAsForStore(selectedStore, nextPage)
                  }}
                  disabled={isLoadingMore}
                  className="px-8 py-3 bg-white/10 hover:bg-[#0071e3] border border-white/20 hover:border-[#0071e3] rounded-lg text-white font-medium transition-all duration-200 hover:scale-105 disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100"
                >
                  {isLoadingMore ? (
                    <span className="flex items-center gap-2">
                      <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin"></div>
                      Loading...
                    </span>
                  ) : (
                    'Load More'
                  )}
                </button>
              </div>
            )}
          </>
        )}
          </div>
        </>
      )}
    </main>
  )
}
