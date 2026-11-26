# Ridgeline Ops team sync (Supabase backend)

This folder is the online part of Ridgeline Ops. It lets the owner and the crew share one set of customers, sites,
jobs, visits and time entries across all their iPhones. Each person signs in, and the server decides what they may
see and change based on the permissions the owner gave them (for example, a crew member only sees the jobs assigned
to them, and never sees invoices or pay).

Without this set up, the app keeps working exactly as it does today on a single phone.

What is here:

| File | What it is |
|---|---|
| `CONTRACT.md` | The exact agreement between the app and this backend. |
| `migrations/0001_team_sync.sql` | Creates the database tables, the security rules and the photo storage. You paste it into Supabase once. |
| `functions/team/index.ts` | A small server program ("Edge Function") the app uses to create, change and remove employee logins. |
| `tests/` | Automated checks of the security rules and of the Edge Function (for developers; you don't need them). |

---

## Setup (about 20 minutes, no coding)

### 1. Create the Supabase project
1. Go to <https://supabase.com> and sign up (signing in with GitHub is easiest).
2. Click **New project**.
   - **Name:** `ridgeline-ops`
   - **Database password:** click *Generate a password* and save it in your password manager. (The app never needs it.)
   - **Region:** pick a US region close to you (for example *East US (North Virginia)* or *West US (Oregon)*).
   - **Plan:** Free is fine to start.
3. Click **Create new project** and wait a minute or two until it says the project is ready.

### 2. Turn off "Confirm email"
Employees get made-up email addresses that can't receive mail, and you should be able to sign up and continue at once.
1. In the left menu open **Authentication**, then **Sign In / Providers** (on some screens it is called **Providers**).
2. Open **Email**.
3. Turn **Confirm email** **off** and click **Save**.

### 3. Create the database tables and security rules
1. In the left menu open **SQL Editor** and click **New query** (or the **+**).
2. Open the file `supabase/migrations/0001_team_sync.sql` from this repository, select everything in it and copy it.
3. Paste it into the SQL Editor and click **Run**.
4. You should see *Success. No rows returned*. (If Supabase warns that the query has "destructive operations", that
   is because the file safely replaces its own rules if you run it again; click to run it anyway.)

### 4. Deploy the `team` Edge Function
Pick **one** of the two ways. Either way, **JWT verification must stay ON** (it is on by default). Do not turn it off
and do not use `--no-verify-jwt`.

**Way A: in the browser (easiest)**
1. In the left menu open **Edge Functions**.
2. Click **Deploy a new function** and choose **Via Editor**.
3. Name the function exactly `team`.
4. Delete the sample code in the editor. Open `supabase/functions/team/index.ts` from this repository, copy all of it
   and paste it into the editor.
5. Click **Deploy function** and wait until it says it is deployed.
6. Open the function's **Details** (or **Settings**) and check that **Verify JWT** / **Enforce JWT verification** is **on**.

**Way B: with the Supabase command line (for a developer)**
From the repository folder on a computer with Node.js installed:
```bash
npx supabase login
npx supabase functions deploy team --project-ref <your-project-ref>
```
`<your-project-ref>` is the random code in your project's address, `https://<project-ref>.supabase.co`.
JWT verification stays on because no `--no-verify-jwt` flag is given.

Nothing else is needed for the function: Supabase gives it the project address and the service role key by itself.

### 5. Connect the app (GitHub secrets)
1. In Supabase open **Project Settings** (the gear at the bottom left), then **API** (on newer screens: **Data API**
   for the URL and **API Keys** for the key).
2. Copy the **Project URL** (looks like `https://abcdefgh.supabase.co`).
3. Copy the **anon public** key (on newer screens it is on the **Legacy API Keys** tab as `anon` `public`; it is a
   long text starting with `eyJ`).
4. On GitHub open the repository **Crispy3x/SupperWise**, then **Settings > Secrets and variables > Actions >
   New repository secret**, and add two secrets:
   - Name `RIDGELINE_SUPABASE_URL`, value: the Project URL.
   - Name `RIDGELINE_SUPABASE_ANON_KEY`, value: the anon public key.
5. The next app build picks them up and team sync turns on.

> **Never share the `service_role` key** (also called the *secret* key). Don't put it in GitHub, in the app, in an
> email or in a chat. It can read and change everything. Only the Edge Function uses it, and Supabase supplies it to
> the function automatically. The anon key, on the other hand, is meant to be inside the app and is safe to share.

### 6. First use
Open the app, choose to set up team sync, and sign up with your own email and a password. You become the owner of
your business. Then add your people in the app's Team screen: give each a username and password and tick what they
may do. They sign in on their own phones with just that username and password.

---

## How it works (short version)

- **Sign-in** uses Supabase Auth. The owner signs in with their email. Employees sign in with a username; behind the
  scenes their login is `<username>@crew.ridgelineops.app`, an address nobody can receive mail at.
- **Data** lives in one table, `records`. Each customer, site, job, visit, time entry and so on is one row holding the
  item exactly as the app stores it. Every change gets a new, ever-increasing number (`seq`). Each phone remembers the
  highest number it has seen and asks only for newer rows, so syncing is fast and nothing is missed. Deleting in the
  app marks a row as deleted instead of erasing it, so the other phones hear about it.
- **Security** is enforced by the database itself (row level security), not by the app. Even someone with a modified
  app can only see and change what their permissions allow: for example, crew members see only their assigned jobs and
  those jobs' customers and sites; nobody sees another business's data; a disabled employee sees nothing. The server
  also stamps who changed each row and when, so that can't be faked.
- **Team logins** (create, reset password, change access, remove) go through the `team` Edge Function, which checks
  that the caller is the owner or has *Manage team*. A manager can never hand out a permission they don't have
  themselves, can't touch the owner's login, and can't change someone who has more access than they do.
- **Photos** (coming in round 2) go into a private storage bucket called `photos`, one folder per business.

## Costs

- **Free plan ($0):** plenty for a small crew. At the time of writing it includes a 500 MB database (hundreds of
  thousands of jobs, visits and time entries), 1 GB of file storage, 50,000 monthly active users and 500,000 Edge Function calls a month.
  Catch: a free project is **paused after about a week with no activity** (you can un-pause it from the dashboard),
  and there are no automatic backups.
- **Pro plan ($25 per month):** switch when you start storing lots of photos, want daily backups, or can't risk the
  project pausing. It includes 8 GB of database, 100 GB of file storage and no pausing. Upgrade any time from
  **Project Settings > Billing** without losing data.
- Current limits and prices: <https://supabase.com/pricing>.

---

## For developers

- `tests/run.sh` loads a stub of Supabase's `auth`/`storage` schemas plus the migration into a scratch PostgreSQL
  database (15+) and runs `tests/rls_test.sql` (80 checks). Use `tests/run.sh --temp-cluster` to have it start and
  stop its own throwaway server, or point it at a server with `PGHOST`/`PGPORT`/`PGUSER` (superuser).
- `tests/team_function_test.ts` exercises the Edge Function against an in-memory fake of Supabase Auth and PostgREST:
  `deno test --allow-env --allow-net=registry.npmjs.org supabase/tests/team_function_test.ts`.
- The migration is safe to run more than once. Later changes go in new files (`0002_...sql`).
