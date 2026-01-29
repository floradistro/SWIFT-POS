import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!

export const supabase = createClient(supabaseUrl, supabaseAnonKey)

// Store ID from environment
export const QUANTIX_STORE_ID = process.env.QUANTIX_STORE_ID || 'bb73275b-edeb-4d1f-9c51-ddc57fa3a19b'
