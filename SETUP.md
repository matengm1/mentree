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

## Local Development (Fully Offline, Isolated Data)

This section is about running the entire stack — database, auth, everything — on your own machine with no internet required and no shared data. This is the recommended way to do day-to-day development.

**Skip this if** you just want to deploy quickly and don't mind your dev work going into the remote database. In that case, jump to Step 1.

### How it works

The Supabase CLI uses Docker to run a miniature version of all Supabase services on your laptop: a real Postgres database, the auth system, a visual database browser, and a fake email inbox. Everything is isolated — data you create locally never touches the cloud. When you're done working, you shut it down.

```
Your browser → Next.js dev server (localhost:3000)
                     ↓
              Local Supabase (localhost:54321)
                     ↓
              Local Postgres database (localhost:54322)
```

### Prerequisites: A Docker runtime and the Supabase CLI

The Supabase CLI needs a running Docker-compatible daemon. Any of these work — pick whichever you already have:

**Option A — Colima (recommended if you already have it)**

Colima is a lightweight, free container runtime for Mac. If you have it, you're already set. Just start it before running Supabase:

```bash
colima start
```

Verify the Docker CLI is pointed at Colima's socket:
```bash
docker context ls   # colima should be marked with *
```

If it's not active: `docker context use colima`

**Option B — Docker Desktop (if you don't have Colima)**

1. Go to https://www.docker.com/products/docker-desktop
2. Download the Mac version and drag to Applications
3. Launch Docker — wait for the whale icon in the menu bar to stop animating (~30–60s)

You do **not** need a Docker account. It just needs to be running in the background.

---

**Supabase CLI** is the command-line tool that manages the local stack.

Install it with Homebrew (the standard Mac package manager):
```bash
brew install supabase/tap/supabase
```

If you don't have Homebrew:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
Then re-run the `brew install` command.

Verify: `supabase --version` should print a version number.

### Start the local Supabase stack

Make sure your Docker runtime is running (Colima: `colima start` / Docker Desktop: whale in menu bar), then from this project's directory:

```bash
supabase start
```

The first time you run this, it downloads the Supabase Docker images (~1GB). This takes a few minutes. After the first time it starts in about 10 seconds.

When it's done, you'll see output like this (modern Supabase CLI uses a boxed format):

```
Started supabase local development setup.

  Project URL: http://127.0.0.1:54321
  Studio URL:  http://127.0.0.1:54323
  Mailpit URL: http://127.0.0.1:54324
  DB URL:      postgresql://postgres:postgres@127.0.0.1:54322/postgres

  Authentication Keys
    Publishable: sb_publishable_...
    Secret:      sb_secret_...
```

The publishable key in that output is the same for every local Supabase project — that's expected. It's a well-known test key, not a real secret. (The CLI also prints legacy `ANON_KEY` / `SERVICE_ROLE_KEY` JWTs if you run `supabase status -o env`, but this project doesn't use them — see the note in the env section below.)

**What also just happened automatically:**
- All migration files in `supabase/migrations/` were applied (your full schema is set up)
- `supabase/seed.sql` ran (Bryn Mawr College is in the schools table)

You don't need to manually paste SQL or create seed data like the remote setup requires.

### Configure environment variables for local

```bash
cp .env.local.example .env.local
```

Open `.env.local` and set it to the **local** values. The URL is hardcoded (it's always the same locally), and the publishable key is printed by `supabase status` — look for `PUBLISHABLE_KEY`:

```
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

To grab the local publishable key without scrolling the startup banner, run:

```bash
supabase status -o env | grep PUBLISHABLE_KEY
```

> **Note on the legacy anon key.** The Supabase CLI still prints a JWT-style `ANON_KEY` for backward compatibility, but Supabase has moved to a new key system (`sb_publishable_...` for clients, `sb_secret_...` for servers). This project uses the new keys exclusively. The legacy `anon` and `service_role` keys are scheduled for removal in late 2026, so don't fall back to them.

### Install dependencies and start the app

```bash
npm install   # only needed the first time, or after package.json changes
npm run dev
```

Open http://localhost:3000. You're running against a fully local database.

### Creating a test account from the command line

Instead of going through the signup form, you can create a pre-confirmed account directly:

```bash
npm run create-dev-user -- --email you@example.com
npm run create-dev-user -- --email you@example.com --password mypassword
```

Default password if you omit `--password` is `devpassword123`.

The script talks to the local Supabase Admin API and marks the email as already confirmed, so you can sign in immediately at http://localhost:3000/login. It will refuse to run against anything other than the local instance (`127.0.0.1:54321`).

When the script succeeds it prints the user's ID and reminds you of the SQL to grant staff access if you need it.

### Granting yourself staff access

`is_staff` is a flag on your user record that unlocks the future admin panel and lets you manage approved emails across all schools. It can only be set directly in the database — there's no UI for it, by design.

After signing up, open Supabase Studio at http://localhost:54323, click **SQL Editor**, and run:

```sql
UPDATE public.users
SET is_staff = true
WHERE id = (
  SELECT id FROM auth.users WHERE email = 'your@email.com'
);
```

Replace `your@email.com` with the address you signed up with. You only need to do this once — the flag persists across `supabase stop` / `supabase start` cycles.

For remote/production, run the same query in the Supabase dashboard SQL editor.

### Adding an approved email (bypass domain check)

Once you have staff access, you can whitelist any email address for a school. In Studio SQL Editor:

```sql
INSERT INTO approved_emails (email, school_id, note, added_by)
SELECT
  'your.personal@gmail.com',
  s.id,
  'Developer testing account',
  u.id
FROM schools s, auth.users u
WHERE s.short_name = 'BMC'
  AND u.email = 'your.personal@gmail.com';
```

Org admins can do the same for their school's members via the future admin UI.

### Useful local URLs

| URL | What it is |
|---|---|
| http://localhost:3000 | The app |
| http://localhost:54323 | Supabase Studio — visual database browser, run queries, inspect tables |
| http://localhost:54324 | Inbucket — catches all emails the app sends so you can inspect them (sign-up confirmation links will appear here) |

### Email confirmation locally

Locally, email confirmation is **disabled** — you can sign up and immediately use the app without clicking a confirmation link. This makes development faster.

If you do want to test the confirmation email flow, visit Inbucket at http://localhost:54324. Every email the app sends (confirmation links, future notifications) appears there as if it's a real inbox. No real emails are ever sent.

### Stopping and resuming

```bash
supabase stop           # shut down — preserves your local data
supabase stop --no-backup  # shut down and wipe the local database (fresh start)
supabase start          # start again — your data is still there (unless you used --no-backup)
```

Data persists between `supabase stop` / `supabase start` cycles. It's like pausing and resuming.

### Switching between local and remote

Your `.env.local` determines which database the app talks to. To switch:

- **Local**: `NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321` + the local publishable key (`supabase status -o env`)
- **Remote**: `NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co` + your remote publishable key (Supabase dashboard → Project Settings → API Keys → Publishable)

It's just two lines in one file. You can keep both sets of values commented out and toggle between them. Changes take effect the next time you restart `npm run dev`.

### Adding new migrations locally

When you change the schema (add a table, add a column, etc.):

1. Write a new file in `supabase/migrations/` named `0002_description.sql`
2. Run `supabase db reset` — this wipes local data and replays all migrations + seed from scratch

`supabase db reset` is the standard way to apply new migrations locally. It's destructive (wipes data) but that's fine for development.

---

## Step 1: Set Up Supabase (Remote / Production)

> **Only needed for deployment.** If you're developing locally, the section above covers everything. Come back here when you're ready to go live.

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
   NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
   ```

   > Find the publishable key in the Supabase dashboard under **Project Settings → API Keys → Publishable**. Make sure you copy the new `sb_publishable_...` value, not the legacy `anon` JWT under the "Legacy" tab.

`.env.local` is in `.gitignore` — it will never be committed to git. Never share these values publicly (though the publishable key is relatively safe — Supabase's row-level security controls what it can access).

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
   - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
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

The `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` (formerly the "anon key") identifies your project. Row Level Security (RLS) policies then determine what each authenticated user can actually read or write. The publishable key alone doesn't grant access to anything sensitive — it's safe to ship in browser bundles.

---

## Troubleshooting

**`supabase start` fails immediately with "Cannot connect to the Docker daemon"**
→ Your Docker runtime isn't running. If using Colima: `colima start`. If using Docker Desktop: open it and wait for the whale icon to stop animating. Then retry.

**`supabase start` hangs for more than 5 minutes**
→ It's probably downloading Docker images for the first time on a slow connection. Let it run. If it truly stalls, `Ctrl+C`, then `supabase stop --no-backup` and `supabase start` again.

**`supabase: command not found`**
→ The CLI isn't installed or your terminal's PATH doesn't include Homebrew's bin directory. Run `brew install supabase/tap/supabase` and open a fresh terminal window.

**Sign up shows "check your email" on local dev**
→ Either the config change wasn't picked up or `.env.local` is pointing at the remote Supabase. Try `supabase stop && supabase start` to reload `config.toml`, and verify `NEXT_PUBLIC_SUPABASE_URL` in `.env.local` is `http://127.0.0.1:54321`. Alternatively, skip the form entirely and use `npm run create-dev-user` instead.

**Sign up succeeds locally but I'm not logged in**
→ Email confirmations are disabled locally — you should be logged in immediately. If you're not, check that your `.env.local` is pointing to the local URL (`http://127.0.0.1:54321`), not the remote one.

**I can't find the confirmation email**
→ Locally, go to http://localhost:54324 (Inbucket). All emails appear there — no real email is ever sent. On remote/production, check your spam folder; the email comes from Supabase's default sender.

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
