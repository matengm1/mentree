/**
 * Dev-only script to create a confirmed Supabase user directly via the Admin API.
 * Bypasses email confirmation entirely — useful for local testing.
 *
 * Only works against a local Supabase instance (127.0.0.1:54321).
 * Intentionally refuses to run against any other URL so it can't be
 * accidentally used against staging or production.
 *
 * Usage:
 *   npm run create-dev-user -- --email you@example.com
 *   npm run create-dev-user -- --email you@example.com --password mypassword
 *
 * Default password if omitted: devpassword123
 */

import { createClient } from '@supabase/supabase-js'

// These are the well-known fixed credentials for every local Supabase instance.
// They are not secrets — they only work on localhost.
const LOCAL_URL = 'http://127.0.0.1:54321'
const LOCAL_SERVICE_ROLE_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hj04zWl196z2-SBc0'

function parseArgs(argv: string[]): Record<string, string> {
  const result: Record<string, string> = {}
  for (let i = 0; i < argv.length - 1; i++) {
    if (argv[i].startsWith('--')) {
      result[argv[i].slice(2)] = argv[i + 1]
    }
  }
  return result
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  const email = args['email']
  const password = args['password'] ?? 'devpassword123'

  if (!email) {
    console.error('Usage: npm run create-dev-user -- --email you@example.com [--password yourpassword]')
    process.exit(1)
  }

  const supabase = createClient(LOCAL_URL, LOCAL_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

  // Verify we're actually talking to local Supabase before doing anything
  const { error: healthError } = await supabase.from('schools').select('id').limit(1)
  if (healthError) {
    console.error('Cannot reach local Supabase at', LOCAL_URL)
    console.error('Make sure `supabase start` is running, then try again.')
    process.exit(1)
  }

  // Create the auth user with email_confirm: true so it's immediately usable
  const { data, error } = await supabase.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  })

  if (error) {
    if (error.message.includes('already registered')) {
      console.error(`A user with email ${email} already exists.`)
      console.error('To reset their password, run this in Studio (http://localhost:54323):')
      console.error(`  UPDATE auth.users SET encrypted_password = crypt('${password}', gen_salt('bf')) WHERE email = '${email}';`)
    } else {
      console.error('Error creating user:', error.message)
    }
    process.exit(1)
  }

  console.log()
  console.log('✓ User created')
  console.log('  Email   :', data.user.email)
  console.log('  Password:', password)
  console.log('  User ID :', data.user.id)
  console.log()
  console.log('You can now sign in at http://localhost:3000/login')
  console.log()
  console.log('To grant staff access, run in Studio (http://localhost:54323 → SQL Editor):')
  console.log(`  UPDATE public.users SET is_staff = true WHERE id = '${data.user.id}';`)
}

main()
