import { createClient } from '@supabase/supabase-js'
import * as dotenv from 'dotenv'
import * as path from 'path'

// Load environment variables
dotenv.config({ path: path.resolve(process.cwd(), '.env.local') })

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!

if (!supabaseUrl || !supabaseServiceKey) {
  console.error('❌ Missing Supabase credentials')
  console.error('NEXT_PUBLIC_SUPABASE_URL:', !!supabaseUrl)
  console.error('SUPABASE_SERVICE_ROLE_KEY:', !!supabaseServiceKey)
  process.exit(1)
}

const supabase = createClient(supabaseUrl, supabaseServiceKey)

async function setupUserStore() {
  const email = 'fahad@cwscommercial.com'

  console.log('🔍 Looking up user:', email)

  // Get auth user
  const { data: { users }, error: authError } = await supabase.auth.admin.listUsers()

  console.log('📋 Found auth users:', users?.length || 0)
  if (users && users.length > 0) {
    console.log('Users:')
    users.forEach(u => console.log(`  - ${u.email} (${u.id})`))
  }

  const authUser = users.find(u => u.email === email)

  if (!authUser) {
    console.error('❌ Auth user not found with email:', email)
    return
  }

  console.log('✅ Found auth user:', authUser.id)

  // Check for platform_users record
  const { data: platformUser, error: platformError } = await supabase
    .from('platform_users')
    .select('*')
    .eq('auth_id', authUser.id)
    .single()

  if (platformError) {
    console.error('❌ Platform user error:', platformError)

    // Create platform_users record if it doesn't exist
    console.log('📝 Creating platform_users record...')
    const { data: newPlatformUser, error: createError } = await supabase
      .from('platform_users')
      .insert({
        auth_id: authUser.id,
        email: authUser.email,
        created_at: new Date().toISOString()
      })
      .select()
      .single()

    if (createError) {
      console.error('❌ Failed to create platform_users:', createError)
      return
    }

    console.log('✅ Created platform_users:', newPlatformUser.id)
    return newPlatformUser
  }

  console.log('✅ Found platform user:', platformUser.id)

  // Check for stores
  const { data: stores, error: storesError } = await supabase
    .from('stores')
    .select('*')
    .eq('owner_user_id', platformUser.id)

  if (storesError) {
    console.error('❌ Stores query error:', storesError)
    return
  }

  console.log('📦 Found stores:', stores?.length || 0)

  if (!stores || stores.length === 0) {
    console.log('📝 Creating test store...')

    const { data: newStore, error: storeError } = await supabase
      .from('stores')
      .insert({
        owner_user_id: platformUser.id,
        name: 'CWS Commercial',
        slug: 'cws-commercial',
        created_at: new Date().toISOString()
      })
      .select()
      .single()

    if (storeError) {
      console.error('❌ Failed to create store:', storeError)
      return
    }

    console.log('✅ Created store:', newStore.id, newStore.name)
  } else {
    console.log('✅ User already has stores:')
    stores.forEach(store => {
      console.log(`  - ${store.name} (${store.id})`)
    })
  }
}

setupUserStore()
