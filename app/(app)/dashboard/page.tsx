import { createClient } from '@/lib/supabase/server'
import type { Organization, Profile } from '@/lib/types'

// Fetches all organizations the current user belongs to, across all their profiles.
async function getUserOrganizations(userId: string): Promise<
  Array<{ org: Organization; profile: Profile; role: string }>
> {
  const supabase = await createClient()

  const { data, error } = await supabase
    .from('memberships')
    .select(`
      role,
      profile:profiles!memberships_profile_id_fkey (
        id,
        display_name,
        graduation_year,
        school_id
      ),
      org:organizations!memberships_org_id_fkey (
        id,
        name,
        org_type,
        description,
        school_id,
        is_public,
        created_at
      )
    `)
    .eq('profiles.user_id', userId)

  if (error || !data) return []

  return data
    .filter((row) => row.profile && row.org)
    .map((row) => ({
      org: row.org as Organization,
      profile: row.profile as Profile,
      role: row.role,
    }))
}

const orgTypeLabels: Record<string, string> = {
  hell_family: 'Hell Families',
  fraternity: 'Fraternity',
  sorority: 'Sorority',
  club: 'Club',
  other: 'Organization',
}

export default async function DashboardPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  // user is guaranteed non-null here — the layout redirects if not authenticated
  const memberships = await getUserOrganizations(user!.id)

  return (
    <div>
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-gray-900">Your Organizations</h1>
        <a
          href="/orgs/new"
          className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500"
        >
          New organization
        </a>
      </div>

      {memberships.length === 0 ? (
        <div className="mt-12 text-center">
          <p className="text-gray-500">You&apos;re not a member of any organizations yet.</p>
          <p className="mt-1 text-sm text-gray-400">
            Create one or ask an admin to invite you.
          </p>
        </div>
      ) : (
        <ul className="mt-6 grid gap-4 sm:grid-cols-2">
          {memberships.map(({ org, role }) => (
            <li key={org.id}>
              <a
                href={`/orgs/${org.id}`}
                className="block rounded-xl border border-gray-200 bg-white p-5 shadow-sm transition hover:border-indigo-300 hover:shadow-md"
              >
                <div className="flex items-start justify-between">
                  <div>
                    <p className="font-semibold text-gray-900">{org.name}</p>
                    <p className="mt-0.5 text-sm text-gray-500">
                      {orgTypeLabels[org.org_type] ?? 'Organization'}
                    </p>
                  </div>
                  <span className="rounded-full bg-gray-100 px-2.5 py-0.5 text-xs font-medium text-gray-600 capitalize">
                    {role}
                  </span>
                </div>
                {org.description && (
                  <p className="mt-3 text-sm text-gray-500 line-clamp-2">{org.description}</p>
                )}
              </a>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
