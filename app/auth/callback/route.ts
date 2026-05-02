import { createClient } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'

// Supabase redirects here after the user clicks the confirmation email link.
// We exchange the one-time code for a session, then send the user to the dashboard.
export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url)
  const code = searchParams.get('code')
  const next = searchParams.get('next') ?? '/dashboard'

  if (code) {
    const supabase = await createClient()
    const { error } = await supabase.auth.exchangeCodeForSession(code)
    if (!error) {
      return NextResponse.redirect(`${origin}${next}`)
    }
  }

  // Something went wrong — send to login with an error hint
  return NextResponse.redirect(`${origin}/login?error=confirmation_failed`)
}
