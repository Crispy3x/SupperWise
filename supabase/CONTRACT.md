# Team sync contract (round 1)

The single source of truth for how the app and the Supabase backend talk. Both sides must match this file exactly.
If either side needs a change, change this file in the same commit.

## Configuration
- App reads `RidgelineSupabaseURL` and `RidgelineSupabaseAnonKey` from Info.plist (build settings `RIDGELINE_SUPABASE_URL`,
  `RIDGELINE_SUPABASE_ANON_KEY`, filled from GitHub secrets of the same names). Both empty = team sync is off and the app
  works exactly as today (single device).
- The anon key is public by design. The service-role key is only ever set inside the Edge Function's environment.

## Auth (Supabase GoTrue REST, no SDK)
- Owner sign up: `POST {url}/auth/v1/signup` `{email, password}`. Email confirmation must be OFF in the project
  (Authentication > Providers > Email > "Confirm email" off) so the owner can continue at once.
- Owner / employee sign in: `POST {url}/auth/v1/token?grant_type=password` `{email, password}`.
- Refresh: `POST {url}/auth/v1/token?grant_type=refresh_token` `{refresh_token}`.
- Every request sends headers `apikey: <anon key>` and, when signed in, `Authorization: Bearer <access_token>`.
- Employee usernames: 3 to 32 chars `[a-z0-9._-]`, lowercased, globally unique. The employee's auth email is
  `<username>@crew.ridgelineops.app` (never shown to anyone; nobody can receive mail there). The employee types only the
  username and password.

## Tables (schema public)
```
businesses(id uuid pk default gen_random_uuid(), name text not null, owner_id uuid not null references auth.users,
           created_at timestamptz default now())
members(business_id uuid references businesses on delete cascade, user_id uuid references auth.users on delete cascade,
        member_id uuid null,            -- the app's TeamMember.id; null for the owner
        role text not null,             -- 'owner' or a TeamRole raw value: manager dispatcher crewLead crewMember office
        permissions text[] not null default '{}',   -- Permission raw values (see below); ignored for the owner
        username text unique null,      -- lowercased; null for the owner
        disabled boolean not null default false,
        created_at timestamptz default now(),
        primary key (business_id, user_id))
records(business_id uuid references businesses on delete cascade,
        kind text not null,             -- see kinds
        id uuid not null,               -- the app's own id for that item
        data jsonb not null,            -- the item encoded exactly as the app's Codable type (JSONEncoder, dates ISO-8601)
        deleted boolean not null default false,
        assignees uuid[] not null default '{}',   -- jobs: TeamMember ids assigned
        site_id uuid null, customer_id uuid null, -- denormalised links used by row security
        updated_by uuid default auth.uid(),
        updated_at timestamptz not null default now(),
        seq bigint not null,            -- set by trigger from a sequence on every insert and update; the sync cursor
        primary key (business_id, kind, id))
```
Index on (business_id, seq).

## Kinds and who may see / write them (enforced by row level security)
Permission raw values: viewAllJobs editJobs logVisits useTimeClock viewClients editClients viewRequests answerRequests
viewQuotes editQuotes viewRevenue viewTeam manageTeam manageSettings. The business owner may do everything.
Disabled members may do nothing.

| kind | read | insert / update |
|---|---|---|
| `job` | viewAllJobs, or caller's member_id = any(assignees) | editJobs; or logVisits for a job assigned to caller (status changes) |
| `customer` | viewClients, or linked (records.id = customer_id) from a job the caller can read | editClients |
| `site` | viewClients, or linked (records.id = site_id) from a job the caller can read | editClients |
| `visit` | viewAllJobs, or updated_by = caller, or its site_id is on a job the caller can read | logVisits |
| `timeEntry` | viewTeam, or updated_by = caller | useTimeClock (own rows; manageTeam may edit any) |
| `member` | any active member of the business (name, role only: the app must not put pay in it) | manageTeam |
| `memberPay` | viewRevenue or manageTeam | manageTeam |
| `contract`, `invoice`, `quote`, `expense` | viewRevenue | viewRevenue |
| `setting` | any active member | manageSettings |

Rows are never hard-deleted by the app: delete = update with `deleted = true` (so other devices learn about it).

## REST used by the app (PostgREST)
- Pull: `GET {url}/rest/v1/records?business_id=eq.{b}&seq=gt.{cursor}&order=seq.asc&limit=500`
  (repeat until fewer than 500 rows). Cursor = highest seq seen, stored per business on the device.
- Push: `POST {url}/rest/v1/records` with header `Prefer: resolution=merge-duplicates,return=representation`,
  body = array of rows `{business_id, kind, id, data, deleted, assignees, site_id, customer_id}` (max 200 per call).
  The server sets updated_by, updated_at and seq. Last write wins per record.
- RPC `POST {url}/rest/v1/rpc/create_business` `{p_name}` -> `uuid` (the caller becomes owner; fails if the caller already
  owns or belongs to a business).
- RPC `POST {url}/rest/v1/rpc/my_membership` `{}` -> `[{business_id, business_name, role, member_id, permissions, disabled}]`
  (empty array when the caller belongs to no business).

## Edge Function `team` (POST {url}/functions/v1/team, caller's Bearer token)
Body `{action, business_id, ...}`; caller must be the owner or have manageTeam in that business.
- `create`: `{member_id, username, password, role, permissions}` -> creates the auth user
  (`<username>@crew.ridgelineops.app`, email_confirm true) and the members row. 409 `{error:"username taken"}`.
- `reset_password`: `{username, password}`.
- `set_access`: `{username, role, permissions, disabled}`.
- `remove`: `{username}` -> deletes the auth user (cascade removes the members row).
- `delete_me`: `{}` (no business_id) -> deletes the caller's own login; for an owner also their business, all its records,
  photos and every employee login. Used by Delete account (App Store rule 5.1.1(v)).
Responses: `200 {ok:true}` or `4xx/5xx {error:"plain sentence"}`. Passwords: at least 8 characters.

## Round 1 scope in the app
Synced kinds: customer, site, job, visit, timeEntry, member, memberPay. Money kinds and photos come in round 2.
