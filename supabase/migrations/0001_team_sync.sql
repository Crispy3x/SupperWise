-- =====================================================================================================
-- Ridgeline Ops: team sync, round 1.
-- Implements supabase/CONTRACT.md. Paste this whole file into the Supabase SQL Editor and press Run.
-- Safe to run again: tables use "if not exists", functions are replaced, policies are dropped and recreated.
-- =====================================================================================================

-- -----------------------------------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------------------------------
create table if not exists public.businesses (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  owner_id   uuid not null references auth.users,
  created_at timestamptz default now()
);

create table if not exists public.members (
  business_id uuid references public.businesses on delete cascade,
  user_id     uuid references auth.users on delete cascade,
  member_id   uuid null,                       -- the app's TeamMember.id; null for the owner
  role        text not null,                   -- 'owner' or a TeamRole raw value
  permissions text[] not null default '{}',    -- Permission raw values; ignored for the owner
  username    text unique null,                -- lowercased; null for the owner
  disabled    boolean not null default false,
  created_at  timestamptz default now(),
  primary key (business_id, user_id),
  constraint members_role_check check (role in ('owner', 'manager', 'dispatcher', 'crewLead', 'crewMember', 'office')),
  constraint members_permissions_check check (permissions <@ array[
    'viewAllJobs', 'editJobs', 'logVisits', 'useTimeClock', 'viewClients', 'editClients', 'viewRequests',
    'answerRequests', 'viewQuotes', 'editQuotes', 'viewRevenue', 'viewTeam', 'manageTeam', 'manageSettings']::text[]),
  constraint members_username_check check (username is null or username ~ '^[a-z0-9._-]{3,32}$')
);

create sequence if not exists public.records_seq;

create table if not exists public.records (
  business_id uuid references public.businesses on delete cascade,
  kind        text not null,
  id          uuid not null,
  data        jsonb not null,
  deleted     boolean not null default false,
  assignees   uuid[] not null default '{}',
  site_id     uuid null,
  customer_id uuid null,
  updated_by  uuid default auth.uid(),
  updated_at  timestamptz not null default now(),
  seq         bigint not null,                 -- always set by the trigger below
  primary key (business_id, kind, id)
);

-- -----------------------------------------------------------------------------------------------------
-- Indexes
-- -----------------------------------------------------------------------------------------------------
create index if not exists records_business_seq_idx on public.records (business_id, seq);
create index if not exists records_job_customer_idx on public.records (business_id, customer_id) where kind = 'job';
create index if not exists records_job_site_idx on public.records (business_id, site_id) where kind = 'job';
create index if not exists members_user_idx on public.members (user_id);
-- One business per owner (create_business also refuses a second one).
create unique index if not exists businesses_owner_idx on public.businesses (owner_id);
-- One login per app team member within a business.
create unique index if not exists members_member_id_idx on public.members (business_id, member_id) where member_id is not null;

-- -----------------------------------------------------------------------------------------------------
-- Helper functions used by row level security.
-- SECURITY DEFINER so they read members/records/businesses without re-entering RLS (no policy recursion).
-- They only ever answer questions about the signed-in caller (auth.uid()).
-- -----------------------------------------------------------------------------------------------------
create or replace function public.is_owner(b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.businesses where id = b and owner_id = auth.uid());
$$;

-- The caller's active (not disabled) members row in business b, or null.
create or replace function public.my_member(b uuid) returns public.members
language sql stable security definer set search_path = public as $$
  select m.* from public.members m
  where m.business_id = b and m.user_id = auth.uid() and not m.disabled
  limit 1;
$$;

-- The caller's TeamMember id in business b (null for the owner, for disabled members and for outsiders).
create or replace function public.my_member_id(b uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select m.member_id from public.members m
  where m.business_id = b and m.user_id = auth.uid() and not m.disabled
  limit 1;
$$;

-- Owner, or an active member of business b.
create or replace function public.is_member(b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner(b)
      or exists (select 1 from public.members m
                 where m.business_id = b and m.user_id = auth.uid() and not m.disabled);
$$;

-- The owner has every permission; an active member has the ones listed on their row; disabled members have none.
create or replace function public.has_perm(b uuid, p text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner(b)
      or exists (select 1 from public.members m
                 where m.business_id = b and m.user_id = auth.uid() and not m.disabled
                   and p = any (m.permissions));
$$;

-- Can the caller read job job_id of business b? (viewAllJobs, or the caller's member_id is in its assignees)
create or replace function public.can_read_job(b uuid, job_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_member(b) and exists (
    select 1 from public.records j
    where j.business_id = b and j.kind = 'job' and j.id = job_id
      and (public.has_perm(b, 'viewAllJobs') or public.my_member_id(b) = any (j.assignees)));
$$;

-- Is the (already stored) job job_id assigned to the caller? Used for the "logVisits may update an assigned job" rule.
create or replace function public.job_assigned_to_me(b uuid, job_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.records j
    where j.business_id = b and j.kind = 'job' and j.id = job_id
      and public.my_member_id(b) = any (j.assignees));
$$;

-- Is customer cid linked (records.customer_id) from a job the caller can read?
create or replace function public.job_links_customer(b uuid, cid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_member(b) and exists (
    select 1 from public.records j
    where j.business_id = b and j.kind = 'job' and j.customer_id = cid
      and (public.has_perm(b, 'viewAllJobs') or public.my_member_id(b) = any (j.assignees)));
$$;

-- Is site sid linked (records.site_id) from a job the caller can read?
create or replace function public.job_links_site(b uuid, sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_member(b) and exists (
    select 1 from public.records j
    where j.business_id = b and j.kind = 'job' and j.site_id = sid
      and (public.has_perm(b, 'viewAllJobs') or public.my_member_id(b) = any (j.assignees)));
$$;

-- The permission needed to insert / update a record of kind k (the contract's "insert / update" column,
-- without the two special cases: logVisits on an assigned job, and "own rows" for timeEntry).
create or replace function public.can_write_kind(b uuid, k text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_member(b) and (
    public.is_owner(b) or coalesce(case
      when k = 'job'                                      then public.has_perm(b, 'editJobs')
      when k in ('customer', 'site')                      then public.has_perm(b, 'editClients')
      when k = 'visit'                                    then public.has_perm(b, 'logVisits')
      when k = 'timeEntry'                                then public.has_perm(b, 'useTimeClock') or public.has_perm(b, 'manageTeam')
      when k in ('member', 'memberPay')                   then public.has_perm(b, 'manageTeam')
      when k in ('contract', 'invoice', 'quote', 'expense') then public.has_perm(b, 'viewRevenue')
      when k = 'setting'                                  then public.has_perm(b, 'manageSettings')
      else false
    end, false));
$$;

-- Safe text -> uuid (null when the text is not a uuid). Used for storage paths.
create or replace function public.uuid_or_null(t text) returns uuid
language plpgsql immutable set search_path = public as $$
begin
  if t ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return t::uuid;
  end if;
  return null;
end;
$$;

-- -----------------------------------------------------------------------------------------------------
-- records trigger: seq / updated_at / updated_by are always set by the server.
-- A per-business transaction lock makes seq order equal commit order inside a business, so a device that
-- pulls "seq > cursor" can never skip a row that commits late with a lower seq.
-- -----------------------------------------------------------------------------------------------------
create or replace function public.records_before_write() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if new.business_id <> old.business_id or new.kind <> old.kind or new.id <> old.id then
      raise exception 'A record cannot be moved to another business, kind or id.';
    end if;
    -- Someone who may only log visits can change a job's status, not who or what it is for.
    if new.kind = 'job' and auth.uid() is not null and not public.has_perm(new.business_id, 'editJobs') then
      if not (new.assignees @> old.assignees and new.assignees <@ old.assignees)
         or new.site_id is distinct from old.site_id
         or new.customer_id is distinct from old.customer_id
         or new.deleted is distinct from old.deleted then
        raise exception 'You can only change the status of a job assigned to you.';
      end if;
    end if;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('ridgeline-records:' || new.business_id::text, 0));
  new.seq        := nextval('public.records_seq');
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

drop trigger if exists records_before_write on public.records;
create trigger records_before_write
  before insert or update on public.records
  for each row execute function public.records_before_write();

-- -----------------------------------------------------------------------------------------------------
-- Row level security
-- -----------------------------------------------------------------------------------------------------
alter table public.businesses enable row level security;
alter table public.members    enable row level security;
alter table public.records    enable row level security;

-- businesses: members read their own business; the owner may rename it. Created only by create_business().
drop policy if exists businesses_select on public.businesses;
create policy businesses_select on public.businesses for select to authenticated
  using (public.is_member(id));

drop policy if exists businesses_update on public.businesses;
create policy businesses_update on public.businesses for update to authenticated
  using (public.is_owner(id))
  with check (owner_id = auth.uid());

-- members: active members read the members of their own business. Only the Edge Function (service role)
-- and create_business() write members, so there are no insert / update / delete policies.
drop policy if exists members_select on public.members;
create policy members_select on public.members for select to authenticated
  using (public.is_member(business_id));

-- records: read
drop policy if exists records_select on public.records;
create policy records_select on public.records for select to authenticated
  using (
    public.is_member(business_id) and (
      public.is_owner(business_id) or coalesce(case
        when kind = 'job' then
          public.has_perm(business_id, 'viewAllJobs') or public.my_member_id(business_id) = any (assignees)
        when kind = 'customer' then
          public.has_perm(business_id, 'viewClients') or public.job_links_customer(business_id, id)
        when kind = 'site' then
          public.has_perm(business_id, 'viewClients') or public.job_links_site(business_id, id)
        when kind = 'visit' then
          public.has_perm(business_id, 'viewAllJobs') or updated_by = auth.uid()
          or (site_id is not null and public.job_links_site(business_id, site_id))
        when kind = 'timeEntry' then
          public.has_perm(business_id, 'viewTeam') or updated_by = auth.uid()
        when kind in ('member', 'setting') then
          true
        when kind = 'memberPay' then
          public.has_perm(business_id, 'viewRevenue') or public.has_perm(business_id, 'manageTeam')
        when kind in ('contract', 'invoice', 'quote', 'expense') then
          public.has_perm(business_id, 'viewRevenue')
        else false
      end, false)));

-- records: insert. (PostgREST's upsert also checks this on the proposed row.)
-- logVisits may only "insert" a job that already exists and is assigned to the caller (the upsert of a status change);
-- it can never create a new job.
drop policy if exists records_insert on public.records;
create policy records_insert on public.records for insert to authenticated
  with check (
    public.can_write_kind(business_id, kind)
    or (kind = 'job'
        and public.has_perm(business_id, 'logVisits')
        and public.my_member_id(business_id) = any (assignees)
        and public.job_assigned_to_me(business_id, id)));

-- records: update. USING checks the stored row, WITH CHECK the new row.
-- timeEntry: own rows only, unless manageTeam.
drop policy if exists records_update on public.records;
create policy records_update on public.records for update to authenticated
  using (
    (public.can_write_kind(business_id, kind)
       and (kind <> 'timeEntry' or updated_by = auth.uid() or public.has_perm(business_id, 'manageTeam')))
    or (kind = 'job'
        and public.has_perm(business_id, 'logVisits')
        and public.my_member_id(business_id) = any (assignees)))
  with check (
    public.can_write_kind(business_id, kind)
    or (kind = 'job'
        and public.has_perm(business_id, 'logVisits')
        and public.my_member_id(business_id) = any (assignees)));

-- No delete policy on records: nobody hard-deletes (delete = update with deleted = true).

-- -----------------------------------------------------------------------------------------------------
-- RPCs
-- -----------------------------------------------------------------------------------------------------
create or replace function public.create_business(p_name text) returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  nm  text := btrim(coalesce(p_name, ''));
  bid uuid;
begin
  if uid is null then
    raise exception 'Please sign in first.' using errcode = '42501';
  end if;
  if nm = '' then
    raise exception 'Please enter a business name.';
  end if;
  if length(nm) > 200 then
    raise exception 'The business name is too long.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('ridgeline-create-business:' || uid::text, 0));
  if exists (select 1 from public.businesses where owner_id = uid)
     or exists (select 1 from public.members where user_id = uid) then
    raise exception 'You already belong to a business.';
  end if;
  insert into public.businesses (name, owner_id) values (nm, uid) returning id into bid;
  insert into public.members (business_id, user_id, member_id, role, permissions, username, disabled)
  values (bid, uid, null, 'owner', '{}', null, false);
  return bid;
end;
$$;

create or replace function public.my_membership()
returns table (business_id uuid, business_name text, role text, member_id uuid, permissions text[], disabled boolean)
language sql stable security definer set search_path = public as $$
  select m.business_id, b.name, m.role, m.member_id, m.permissions, m.disabled
  from public.members m
  join public.businesses b on b.id = m.business_id
  where m.user_id = auth.uid()
  order by m.created_at;
$$;

-- -----------------------------------------------------------------------------------------------------
-- Privileges (Supabase grants everything to anon/authenticated by default; RLS + these grants narrow it).
-- -----------------------------------------------------------------------------------------------------
revoke all on public.businesses, public.members, public.records from anon, authenticated;
grant select on public.businesses to authenticated;
grant update (name) on public.businesses to authenticated;
grant select on public.members to authenticated;
grant select, insert, update on public.records to authenticated;   -- no delete
grant all on public.businesses, public.members, public.records to service_role;
revoke all on sequence public.records_seq from anon, authenticated;
grant all on sequence public.records_seq to service_role;

revoke execute on function public.is_owner(uuid), public.my_member(uuid), public.my_member_id(uuid),
  public.is_member(uuid), public.has_perm(uuid, text), public.can_read_job(uuid, uuid),
  public.job_assigned_to_me(uuid, uuid), public.job_links_customer(uuid, uuid), public.job_links_site(uuid, uuid),
  public.can_write_kind(uuid, text), public.uuid_or_null(text),
  public.create_business(text), public.my_membership()
  from public, anon;
grant execute on function public.is_owner(uuid), public.my_member(uuid), public.my_member_id(uuid),
  public.is_member(uuid), public.has_perm(uuid, text), public.can_read_job(uuid, uuid),
  public.job_assigned_to_me(uuid, uuid), public.job_links_customer(uuid, uuid), public.job_links_site(uuid, uuid),
  public.can_write_kind(uuid, text), public.uuid_or_null(text),
  public.create_business(text), public.my_membership()
  to authenticated, service_role;
revoke execute on function public.records_before_write() from public, anon, authenticated;

-- -----------------------------------------------------------------------------------------------------
-- Storage (round 2): private bucket "photos", objects stored under "<business_id>/...".
-- -----------------------------------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('photos', 'photos', false)
on conflict (id) do nothing;

drop policy if exists "ridgeline photos read" on storage.objects;
create policy "ridgeline photos read" on storage.objects for select to authenticated
  using (bucket_id = 'photos'
         and public.is_member(public.uuid_or_null((storage.foldername(name))[1])));

drop policy if exists "ridgeline photos upload" on storage.objects;
create policy "ridgeline photos upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos'
              and public.has_perm(public.uuid_or_null((storage.foldername(name))[1]), 'logVisits'));
