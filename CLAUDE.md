# Claude Instructions for Mentree

## Project Overview

This is a Next.js 15 + Supabase app for tracking college organization lineage trees (starting with Bryn Mawr Hell Families). See `README.md` for full architecture and `SETUP.md` for running the project.

---

## Documentation Maintenance Rule

**After every code change, before marking a task done:**

1. Check whether the change affects any behavior described in `README.md`. If so, update the relevant section.
2. Check whether `SETUP.md` setup or deployment steps are still accurate.
3. Check whether any JSDoc/function comments in edited files are now stale or wrong.

Do not leave documentation that contradicts the current behavior. Outdated docs are worse than no docs.

---

## Architecture Constraints (Do Not Violate)

**Database access pattern:**
- In Server Components and API routes: use `lib/supabase/server.ts`
- In Client Components: use `lib/supabase/client.ts`
- Never import the server client into a Client Component (`'use client'` file)
- Never use the `service_role` key client-side — it bypasses all RLS

**RLS is the hard enforcement layer.** API routes do validation and return good error messages, but RLS must independently enforce the same rules. If you add a feature that requires a new access pattern, write the RLS policy first, then the API route.

**Soft deletes only.** Never `DELETE` from `family_relationships`. Always set `deleted_at = now()`. The audit trigger handles logging. Queries must always include `WHERE deleted_at IS NULL` unless intentionally looking at deleted records.

**Multi-tenancy.** Every query involving org data must be scoped by `org_id`. Never return data across orgs. The RLS policies enforce this, but API routes should also scope queries explicitly.

**One parent per person per org.** The `UNIQUE (org_id, child_profile_id)` constraint on `family_relationships` enforces this. Do not try to work around it — if an org type needs multiple parents, that's a deliberate schema change to discuss first.

---

## Code Conventions

**TypeScript:** All new code must be typed. No `any`. Use types from `lib/types.ts`. If the schema changes, update `lib/types.ts` to match.

**Server vs Client Components:** Default to Server Components. Only add `'use client'` when you need browser APIs, React hooks, or event handlers. Keep client components lean.

**API routes:** Live in `app/api/`. Return consistent shapes:
```ts
// Success
{ data: T }

// Error
{ error: string }
```

**Database functions:** Prefer Postgres functions (in migrations) over multi-step API logic for operations that need to be atomic (e.g., creating an org + adding the creator as owner in one transaction).

**Environment variables:** Anything prefixed `NEXT_PUBLIC_` is visible to the browser. Only `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` should be public. The anon key is safe to expose — RLS prevents misuse. The service role key must never be prefixed `NEXT_PUBLIC_`.

---

## Database Migration Conventions

- Migration files live in `supabase/migrations/`, named `NNNN_description.sql`
- Never edit an existing migration — add a new one
- Every migration must be idempotent where practical (`CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`)
- Add a comment at the top of each migration explaining what it does and why

---

## Key Design Decisions (Do Not Re-litigate Without Good Reason)

These were deliberately chosen — see `README.md` for the full rationale:

- **Adjacency list** for tree storage (not closure table)
- **Ghost nodes** for historical members who never registered
- **Relationship confirmation flow** — pending → confirmed/rejected, admin can bypass
- **Roles**: owner > admin > member > viewer per org
- **Soft deletes** + JSON audit snapshots for rollback
- **Resend** for transactional email (not Supabase's built-in email)

---

## Adding New Features Checklist

1. Does the feature need new DB columns or tables? Write the migration first.
2. Does it need new RLS policies? Write and test those before the API route.
3. Does it send emails? Use the Resend client in a Server Action or API route — never client-side.
4. Does it touch the tree structure? Make sure the recursive CTE queries still work.
5. After implementing: update `README.md` Phase tracker and any changed docs.
