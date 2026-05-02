# Setup, Development, and Deployment Guide

This guide walks you through getting the project running locally and deploying it — assuming no prior familiarity with Next.js, Supabase, or Vercel.

---

## What Each Tool Is

**Next.js** is a React framework for building web apps. It handles routing, server-side rendering, and API endpoints all in one project. You write the frontend (what users see) and backend (API logic) in the same codebase.

**Supabase** is a backend-as-a-service built on Postgres. It gives you a database, user authentication, and fine-grained access control — all through a web dashboard and a JavaScript client library. You don't manage a server; Supabase handles that.

**Vercel** is a hosting platform made by the same team as Next.js. You connect your GitHub repo and it automatically builds and deploys your app every time you push code. No server configuration needed.

---

## Prerequisites

### 1. Install Node.js

Node.js is the JavaScript runtime that runs Next.js locally.

1. Go to https://nodejs.org
2. Download the **LTS** version (the left button)
3. Run the installer
4. Verify it worked: open a terminal and run `node --version`. You should see something like `v22.x.x`.

### 2. Install a Package Manager

`npm` comes with Node.js. We'll use `npm` throughout this guide. If you prefer `pnpm` (faster), install it with:
```bash
npm install -g pnpm
```
Then replace `npm` with `pnpm` in all commands below.

---

## Step 1: Set Up Supabase

### Create an Account and Project

1. Go to https://supabase.com and click **Start your project**
2. Sign up (GitHub login is easiest)
3. Click **New project**
4. Fill in:
   - **Organization**: your name or "Mentree"
   - **Name**: `mentree`
   - **Database Password**: generate a strong one and save it somewhere (you'll rarely need it, but don't lose it)
   - **Region**: pick the one closest to your users
5. Click **Create new project** — it takes about 2 minutes to spin up

### Get Your API Keys

Once the project is ready:

1. In the Supabase dashboard, click **Project Settings** (gear icon, bottom left)
2. Click **API** in the left menu
3. You'll see two values you need:
   - **Project URL** — looks like `https://abcdefghijkl.supabase.co`
   - **anon / public key** — a long string starting with `eyJ...`

Copy both of these — you'll use them in Step 3.

### Run the Database Migration

The migration file creates all the tables, indexes, and access control policies.

1. In the Supabase dashboard, click **SQL Editor** (left sidebar)
2. Click **New query**
3. Open `supabase/migrations/0001_initial_schema.sql` in this project
4. Copy the entire contents and paste it into the SQL editor
5. Click **Run** (or press Cmd+Enter)

You should see "Success. No rows returned." If you see an error, double-check that you copied the whole file.

To verify it worked:
1. Click **Table Editor** in the left sidebar
2. You should see tables like `schools`, `profiles`, `organizations`, `memberships`, `family_relationships`, `relationship_audit`

### Add a Seed School

Your app needs at least one school record to create profiles. Run this in the SQL editor:

```sql
INSERT INTO schools (name, short_name, allowed_email_domains)
VALUES ('Bryn Mawr College', 'BMC', ARRAY['brynmawr.edu']);
```

You can add more schools the same way later.

### Configure Auth Settings

1. In Supabase dashboard, go to **Authentication** → **URL Configuration**
2. Set **Site URL** to `http://localhost:3000` (for local development — you'll update this after deploying)
3. Under **Redirect URLs**, add `http://localhost:3000/**`
4. Click **Save**

---

## Step 2: Install Project Dependencies

In your terminal, navigate to this project folder and run:

```bash
npm install
```

This downloads all the libraries the project uses (Next.js, Supabase client, React Flow, etc.) into a `node_modules` folder. This takes a minute or two on first run.

---

## Step 3: Configure Environment Variables

Environment variables are settings the app reads at runtime — things like API keys that you don't want hardcoded in source code.

1. Copy the example file:
   ```bash
   cp .env.local.example .env.local
   ```

2. Open `.env.local` in your text editor and fill in the values from Step 1:
   ```
   NEXT_PUBLIC_SUPABASE_URL=https://your-project-id.supabase.co
   NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGci...your-anon-key...
   ```

`.env.local` is in `.gitignore` — it will never be committed to git. Never share these values publicly (though the anon key is relatively safe — Supabase's row-level security controls what it can access).

---

## Step 4: Run the Development Server

```bash
npm run dev
```

Open http://localhost:3000 in your browser. You should see the app's landing page.

The development server has **hot reload** — when you save a file, the browser updates automatically without a full refresh. You'll use this constantly while building.

To stop the server: `Ctrl+C` in the terminal.

### Common Dev Commands

| Command | What it does |
|---|---|
| `npm run dev` | Start development server (hot reload) |
| `npm run build` | Build for production (catches TypeScript errors) |
| `npm run lint` | Check for code style issues |

---

## Step 5: Deploy to Vercel

### Create a Vercel Account

1. Go to https://vercel.com and sign up (GitHub login is easiest — use the same GitHub account that has your code)

### Push Your Code to GitHub

If you haven't already:

```bash
# In the project directory
git init
git add .
git commit -m "Initial scaffold"
```

Then create a new repo on GitHub (go to github.com → New repository) and follow the instructions to push your local code.

### Connect to Vercel

1. In Vercel, click **Add New... → Project**
2. Click **Import** next to your GitHub repo
3. Vercel auto-detects it's a Next.js project — no configuration changes needed
4. Click **Environment Variables** and add the same two variables from your `.env.local`:
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
5. Click **Deploy**

Vercel builds and deploys. After a minute you'll get a live URL like `https://mentree-abc123.vercel.app`.

### Update Supabase Auth Settings for Production

Now that you have a live URL:

1. Go back to Supabase → **Authentication** → **URL Configuration**
2. Update **Site URL** to your Vercel URL (e.g., `https://mentree-abc123.vercel.app`)
3. Add your Vercel URL to **Redirect URLs**: `https://mentree-abc123.vercel.app/**`
4. Also keep `http://localhost:3000/**` in Redirect URLs so local dev still works
5. Save

### Future Deploys

Every `git push` to your main branch will trigger a new Vercel deploy automatically. Vercel also creates a unique preview URL for every branch/PR — useful for testing before merging.

---

## How Supabase Auth Works (What's Happening Under the Hood)

When a user signs up:
1. Supabase creates an entry in `auth.users` (managed by Supabase, not editable directly)
2. A database trigger (`handle_new_user`) automatically creates a row in your `public.users` table
3. Supabase sends a confirmation email to the user
4. User clicks the link, gets redirected back to your app
5. Supabase sets a session cookie; every subsequent request includes this cookie
6. Your middleware reads the cookie, validates the session, and redirects unauthenticated users away from protected routes

The `NEXT_PUBLIC_SUPABASE_ANON_KEY` is a JWT that identifies your project. Row Level Security (RLS) policies then determine what each authenticated user can actually read or write. The anon key alone doesn't grant access to anything sensitive.

---

## Troubleshooting

**"Module not found" error when running `npm run dev`**
→ Run `npm install` again. Something didn't install correctly.

**Redirect loop on login page**
→ Your Supabase redirect URLs are probably misconfigured. Check Authentication → URL Configuration.

**"Row Level Security" errors when querying data**
→ The logged-in user doesn't have permission for that operation. Check that the user has the right role in `memberships` and that the RLS policy covers that case.

**Build fails with TypeScript errors**
→ Run `npm run build` locally before pushing to see errors before Vercel does. TypeScript errors that the dev server warns about become hard failures in production builds.

**Supabase project is paused**
→ The free tier pauses projects after 1 week of inactivity. Log into Supabase, go to your project, and click **Restore project**. Consider upgrading to the Pro tier ($25/mo) once you have real users.

---

## Adding a Second Developer

1. They clone the repo from GitHub
2. You invite them to the Supabase project: Settings → Team → Invite
3. They create their own `.env.local` with the same keys (get them from Supabase → Settings → API)
4. They run `npm install && npm run dev`

The database is shared — changes either of you make locally write to the same Supabase project. If you want isolated databases, Supabase supports branching on the Pro plan.
