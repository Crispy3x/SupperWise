-- Supperwise backend: community recipes (uploaded, approved by an admin, then shared) and AI food-scan usage.

-- Who is an admin. Make yourself one after signing in once:
--   update public.profiles set is_admin = true where id = (select id from auth.users where email = 'you@example.com');
create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text check (char_length(display_name) <= 40),
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
create policy "read own profile" on public.profiles for select using (auth.uid() = id);
create policy "update own name" on public.profiles for update using (auth.uid() = id)
  with check (auth.uid() = id and is_admin = (select p.is_admin from public.profiles p where p.id = auth.uid()));

create function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin insert into public.profiles (id) values (new.id) on conflict do nothing; return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create function public.is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false) $$;

-- Community recipes. `recipe` holds the same shape as the app's bundled recipes (ingredients mapped to catalog ids).
create type public.review_status as enum ('pending', 'approved', 'rejected');
create table public.community_recipes (
  id uuid primary key default gen_random_uuid(),
  author uuid not null default auth.uid() references auth.users on delete cascade,
  author_name text check (char_length(author_name) <= 40),
  status public.review_status not null default 'pending',
  recipe jsonb not null check (jsonb_typeof(recipe) = 'object' and pg_column_size(recipe) < 60000),
  photo_path text,
  reject_reason text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users
);
create index community_recipes_status on public.community_recipes (status, created_at desc);
alter table public.community_recipes enable row level security;
-- Everyone (signed in or not) sees approved recipes; authors see their own in any state; admins see everything.
create policy "approved are public" on public.community_recipes for select using (status = 'approved');
create policy "authors see own" on public.community_recipes for select using (auth.uid() = author);
create policy "admins see all" on public.community_recipes for select using (public.is_admin());
-- Signed-in people submit, always as pending, as themselves.
create policy "submit as pending" on public.community_recipes for insert to authenticated
  with check (auth.uid() = author and status = 'pending' and reviewed_at is null and reviewed_by is null);
-- Authors may withdraw (delete) their own pending or rejected recipes.
create policy "authors delete own" on public.community_recipes for delete using (auth.uid() = author and status <> 'approved');
-- Only admins approve or reject.
create policy "admins review" on public.community_recipes for update using (public.is_admin()) with check (public.is_admin());

-- Photos for community recipes: public to read, each person uploads only into their own folder (<user id>/...).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('recipe-photos', 'recipe-photos', true, 3145728, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do nothing;
create policy "upload own photos" on storage.objects for insert to authenticated
  with check (bucket_id = 'recipe-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "delete own photos" on storage.objects for delete to authenticated
  using (bucket_id = 'recipe-photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- AI food scans: a monthly count per person, written only by the scan function (service role).
create table public.scan_usage (
  user_id uuid not null references auth.users on delete cascade,
  month text not null,             -- '2026-11'
  scans int not null default 0,
  primary key (user_id, month)
);
alter table public.scan_usage enable row level security;
create policy "read own usage" on public.scan_usage for select using (auth.uid() = user_id);

-- Counts one scan if the person is under their monthly limit; returns the new count, or -1 when over.
create function public.use_scan(p_user uuid, p_limit int) returns int language plpgsql security definer set search_path = public as $$
declare m text := to_char(now() at time zone 'utc', 'YYYY-MM'); n int;
begin
  insert into scan_usage (user_id, month, scans) values (p_user, m, 0) on conflict do nothing;
  update scan_usage set scans = scans + 1 where user_id = p_user and month = m and scans < p_limit returning scans into n;
  return coalesce(n, -1);
end $$;
revoke execute on function public.use_scan(uuid, int) from public, anon, authenticated;

-- Reports on published recipes (App Store guideline 1.2: a way to flag objectionable content). Admins act on them.
create table public.recipe_reports (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.community_recipes on delete cascade,
  reporter uuid not null default auth.uid() references auth.users on delete cascade,
  reason text not null check (char_length(reason) between 1 and 500),
  created_at timestamptz not null default now(),
  unique (recipe_id, reporter)
);
alter table public.recipe_reports enable row level security;
create policy "report as yourself" on public.recipe_reports for insert to authenticated with check (auth.uid() = reporter);
create policy "admins read reports" on public.recipe_reports for select using (public.is_admin());
create policy "admins clear reports" on public.recipe_reports for delete using (public.is_admin());
