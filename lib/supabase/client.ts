import { createBrowserClient } from '@supabase/ssr'
import type { Database } from '@/lib/types'

// Browser-side Supabase client. Use this in Client Components ('use client').
// The publishable key is intentionally public — RLS policies enforce access control.
export function createClient() {
  return createBrowserClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!
  )
}
