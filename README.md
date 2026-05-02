# Mentree

A web app to track mentor-mentee lineage within college organizations — starting with Bryn Mawr Hell Families. Think Ancestry.com, but for the family trees that form organically inside student organizations. Families can go back 15+ years; this makes that history explorable and permanent.

---

## What It Does

- **Organizations** — create a lineage tracker for any org (Hell Families, fraternities, sororities, clubs)
- **Family Trees** — track who proposed to whom, going back as far as anyone can remember
- **Ghost Nodes** — add historical members who never registered; they can claim their node later
- **Confirmation Flow** — relationships need both parties to confirm (or an admin to approve), preventing false entries
- **Audit Log** — every change is recorded; admins can restore deleted or incorrect relationships

---

## Architecture

### Stack

| Layer | Technology | Why |
|---|---|---|
| Frontend + API | Next.js 15 (App Router) | Fullstack in one repo, server components, deploys to Vercel with zero config |
| Database + Auth | Supabase (Postgres) | Email auth, Row Level Security, free tier, no separate backend to manage |
| Deployment | Vercel | Git-push deploys, preview URLs per branch, free tier |
| Tree Visualization | React Flow | Pan/zoom tree rendering with minimal implementation |
| Email | Resend | Transactional email for confirmations and notifications |

### Key Design Decisions

**Multi-tenant from day one.** The schema is scoped by `school_id` and `org_id` throughout. Retrofitting multi-tenancy after the fact is extremely painful. The cost is ~20% more upfront complexity.

**Adjacency list for tree storage.** Each relationship row stores `parent_profile_id → child_profile_id`. To query full lineages we use Postgres recursive CTEs. A closure table would be faster for reads but adds significant write complexity — at Bryn Mawr scale (thousands of rows max), recursive CTEs are fast enough and much simpler.

**Ghost nodes for historical people.** A `ghost` profile is a placeholder for someone who hasn't registered. They can be nodes in the tree. When the real person signs up later, they claim the ghost node through an admin-approved claim flow.

**Relationship confirmation.** Adding a parent-child relationship creates a `pending` record. The other party must confirm it, or an org admin approves it. This prevents false relationships while still allowing admins to add historical data unilaterally.

**RLS as the access control layer.** Supabase Row Level Security policies enforce who can read and write what, directly in the database. API routes do validation and return good error messages, but RLS is the hard guarantee. Defense in depth.

**Soft deletes + JSON audit snapshots.** Deleted relationships get a `deleted_at` timestamp rather than being removed. Every state change is logged to `relationship_audit` with a full JSON snapshot of before/after. Admins can restore any soft-deleted record.

**No "everyone is an admin" model.** Each org has a small group of `admin`s (and one `owner`). Members can propose relationships they're party to. Admins can approve anything. This gives a clear accountability chain and a dispute resolution path.

---

## Data Model

```
users           — auth anchor (maps to Supabase auth.users)
  └── profiles  — academic identity per school; can be ghost (no auth account)

schools
  └── organizations
        ├── memberships     — links profiles to orgs with a role
        └── family_relationships — the tree edges (parent → child)
              └── relationship_audit — full history of every change
```

### Roles (per organization)

| Role | Can do |
|---|---|
| `owner` | Everything; can delete org, transfer ownership |
| `admin` | Approve relationships, add/remove members, manage ghost nodes, restore deleted relationships |
| `member` | Propose relationships they're party to, view all org data |
| `viewer` | Read-only; for public orgs or unverified members |

### Relationship Status Flow

```
member proposes relationship → status: pending
  ↓
other party confirms            → status: confirmed
other party rejects             → status: rejected
admin approves directly         → status: confirmed (skips pending)
admin soft-deletes              → deleted_at is set (audit record written)
admin restores                  → deleted_at cleared (audit record written)
```

---

## Project Structure

```
app/
  (auth)/login, signup         — unauthenticated routes
  (app)/dashboard, orgs/[id]   — protected routes (middleware enforces auth)
  api/                         — API route handlers

components/
  auth/                        — login/signup form
  tree/                        — React Flow tree visualization (future)
  ui/                          — shared UI primitives

lib/
  supabase/client.ts           — browser Supabase client
  supabase/server.ts           — server Supabase client (for Server Components + API routes)
  types.ts                     — TypeScript types generated from DB schema

supabase/
  migrations/                  — SQL migration files, run in order

middleware.ts                  — redirects unauthenticated users away from protected routes
```

---

## Development Phases

### Phase 1 — Foundation (current)
- [x] Project scaffold (Next.js, Supabase, Vercel config)
- [x] Database schema + RLS policies
- [x] Auth (login, signup, session management)
- [ ] Onboarding: create profile after signup
- [ ] Org creation and invite flow
- [ ] Basic relationship CRUD

### Phase 2 — Core Product
- [ ] Tree visualization (React Flow, horizontal layout)
- [ ] Ghost node creation and claim flow
- [ ] Relationship confirmation UI
- [ ] Member management UI

### Phase 3 — Trust & Safety
- [ ] Admin approval queue for ghost-to-ghost relationships
- [ ] Audit log viewer for admins
- [ ] Soft delete + restore UI
- [ ] Email notifications via Resend

### Phase 4 — Polish
- [ ] Mobile list view (tree view is desktop-only)
- [ ] Public org URLs (shareable lineage pages)
- [ ] Multi-school support (add new schools via admin panel)
- [ ] Profile claiming for alumni

---

## Environment Variables

See `.env.local.example` for the full list. Required to run locally:

```
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
```

See `SETUP.md` for where to find these values.
