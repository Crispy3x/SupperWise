-- Row level security tests for migrations/0001_team_sync.sql.
-- Run with tests/run.sh (loads tests/supabase_stub.sql and the migration into a scratch database first).
-- Every check prints one line starting with PASS or FAIL; a summary is printed at the end.
\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned
set client_min_messages = warning;

-- ---------------------------------------------------------------------------------------------------
-- Test helpers (schema t, created as superuser)
-- ---------------------------------------------------------------------------------------------------
create schema t;
grant usage on schema t to public;
create table t.results (n serial primary key, name text not null, ok boolean not null);

create function t.ok(name text, cond boolean) returns text
language plpgsql security definer as $$
begin
  insert into t.results (name, ok) values (name, coalesce(cond, false));
  return case when coalesce(cond, false) then 'PASS  ' else 'FAIL  ' end || name;
end $$;

-- Sign in as a user: role authenticated + JWT sub, the way PostgREST does it. Leave with "reset role".
create function t.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(uid::text, ''), false);
  perform set_config('role', 'authenticated', false);
end $$;

-- Must raise an error. Any effect of the statement is rolled back.
create function t.fails(name text, stmt text) returns text language plpgsql as $$
declare msg text;
begin
  begin
    execute stmt;
    raise exception using errcode = 'RLT01', message = 'no error';
  exception
    when sqlstate 'RLT01' then return t.ok(name || '  (expected an error, got none)', false);
    when others then msg := sqlerrm;
  end;
  return t.ok(name || '  [refused: ' || msg || ']', true);
end $$;

-- Must succeed (effects are kept).
create function t.succeeds(name text, stmt text) returns text language plpgsql as $$
begin
  execute stmt;
  return t.ok(name, true);
exception when others then
  return t.ok(name || '  (error: ' || sqlerrm || ')', false);
end $$;

-- The same statement PostgREST runs for: POST /rest/v1/records, Prefer: resolution=merge-duplicates,return=representation
create function t.push(b uuid, k text, rid uuid, d jsonb, del boolean default false, a uuid[] default '{}',
                       site uuid default null, cust uuid default null) returns public.records
language plpgsql as $$
declare rec public.records;
begin
  insert into public.records as r (business_id, kind, id, data, deleted, assignees, site_id, customer_id)
  values (b, k, rid, d, del, a, site, cust)
  on conflict (business_id, kind, id) do update set
    business_id = excluded.business_id, kind = excluded.kind, id = excluded.id, data = excluded.data,
    deleted = excluded.deleted, assignees = excluded.assignees, site_id = excluded.site_id,
    customer_id = excluded.customer_id
  returning r.* into rec;
  return rec;
end $$;

grant execute on all functions in schema t to public;

-- ---------------------------------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------------------------------
\set ownerA   'a0000000-0000-0000-0000-000000000001'
\set mgrA     'a0000000-0000-0000-0000-000000000002'
\set crewA    'a0000000-0000-0000-0000-000000000003'
\set crew2A   'a0000000-0000-0000-0000-000000000004'
\set disA     'a0000000-0000-0000-0000-000000000005'
\set viewA    'a0000000-0000-0000-0000-000000000006'
\set ownerB   'b0000000-0000-0000-0000-000000000001'
\set crewB    'b0000000-0000-0000-0000-000000000002'
\set loner    'e0000000-0000-0000-0000-000000000001'
\set M1 'c0000000-0000-0000-0000-000000000001'
\set M2 'c0000000-0000-0000-0000-000000000002'
\set M3 'c0000000-0000-0000-0000-000000000003'
\set M4 'c0000000-0000-0000-0000-000000000004'
\set M5 'c0000000-0000-0000-0000-000000000005'
\set MG 'c0000000-0000-0000-0000-000000000006'
\set C1 '10000000-0000-0000-0000-000000000001'
\set C2 '10000000-0000-0000-0000-000000000002'
\set S1 '20000000-0000-0000-0000-000000000001'
\set S2 '20000000-0000-0000-0000-000000000002'
\set J1 '30000000-0000-0000-0000-000000000001'
\set J2 '30000000-0000-0000-0000-000000000002'
\set J3 '30000000-0000-0000-0000-000000000003'
\set V1 '40000000-0000-0000-0000-000000000001'
\set V2 '40000000-0000-0000-0000-000000000002'
\set V3 '40000000-0000-0000-0000-000000000003'
\set I1 '50000000-0000-0000-0000-000000000001'
\set P1 '60000000-0000-0000-0000-000000000001'
\set MB1 '70000000-0000-0000-0000-000000000001'
\set ST1 '80000000-0000-0000-0000-000000000001'
\set T1 '90000000-0000-0000-0000-000000000001'
\set T2 '90000000-0000-0000-0000-000000000002'
\set CB1 'f0000000-0000-0000-0000-000000000001'

insert into auth.users (id, email) values
  (:'ownerA', 'owner@a.test'), (:'mgrA', 'mgr@crew.ridgelineops.app'), (:'crewA', 'crew@crew.ridgelineops.app'),
  (:'crew2A', 'crew2@crew.ridgelineops.app'), (:'disA', 'gone@crew.ridgelineops.app'),
  (:'viewA', 'viewer@crew.ridgelineops.app'), (:'ownerB', 'owner@b.test'), (:'crewB', 'bcrew@crew.ridgelineops.app'),
  (:'loner', 'loner@x.test');

\echo '--- RPCs and access for anonymous callers'
reset role; select t.login(null); set role anon;
select t.fails('anon cannot call create_business', $$select public.create_business('Nope')$$);
select t.fails('anon cannot read records', $$select count(*) from public.records$$);

\echo '--- create_business / my_membership'
reset role; select t.login(:'ownerA');
select public.create_business('  Ridgeline A  ') as ba \gset
reset role; select t.login(:'ownerB');
select public.create_business('Other Co') as bb \gset

reset role; select t.login(:'ownerA');
select t.ok('create_business trims the name and makes the caller owner',
  (select count(*) = 1 from public.businesses where id = :'ba' and name = 'Ridgeline A' and owner_id = :'ownerA'));
select t.fails('create_business twice fails', $$select public.create_business('Second')$$);
select t.fails('create_business with a blank name fails', $$select public.create_business('   ')$$);
select t.ok('my_membership (owner) returns exactly the owner row',
  (select count(*) = 1 and bool_and(business_id = :'ba' and business_name = 'Ridgeline A' and role = 'owner'
          and member_id is null and permissions = '{}' and not disabled)
   from public.my_membership()));

-- The Edge Function (service role) adds the employees:
reset role;
insert into public.members (business_id, user_id, member_id, role, permissions, username, disabled) values
  (:'ba', :'mgrA',   :'MG', 'manager',    '{manageTeam,viewAllJobs,editJobs,viewTeam,viewClients}', 'mgr', false),
  (:'ba', :'crewA',  :'M1', 'crewMember', '{logVisits,useTimeClock}', 'crew', false),
  (:'ba', :'crew2A', :'M2', 'crewMember', '{logVisits,useTimeClock}', 'crew2', false),
  (:'ba', :'disA',   :'M3', 'office',     '{viewAllJobs,viewClients,viewRevenue,logVisits,editClients}', 'gone', true),
  (:'ba', :'viewA',  :'M4', 'office',     '{viewClients}', 'viewer', false),
  (:'bb', :'crewB',  :'M5', 'crewMember', '{logVisits}', 'bcrew', false);

select t.login(:'crewA');
select t.ok('my_membership (crew) returns business, role, member_id, permissions',
  (select count(*) = 1 and bool_and(business_id = :'ba' and business_name = 'Ridgeline A' and role = 'crewMember'
          and member_id = :'M1' and permissions = '{logVisits,useTimeClock}' and not disabled)
   from public.my_membership()));
select t.fails('create_business fails for someone who already belongs to a business', $$select public.create_business('Mine')$$);
reset role; select t.login(:'disA');
select t.ok('my_membership (disabled) still returns the row with disabled = true',
  (select count(*) = 1 and bool_and(disabled) from public.my_membership()));
reset role; select t.login(:'loner');
select t.ok('my_membership (no business) returns no rows', (select count(*) = 0 from public.my_membership()));

\echo '--- owner writes everything'
reset role; select t.login(:'ownerA');
select t.succeeds('owner pushes customers, sites, jobs, visits, invoice, memberPay, member, setting', format($f$
  select t.push(%1$L, 'customer', %2$L, '{"name":"Alice"}');
  select t.push(%1$L, 'customer', %3$L, '{"name":"Bob"}');
  select t.push(%1$L, 'site', %4$L, '{"address":"1 Main"}', false, '{}', null, %2$L);
  select t.push(%1$L, 'site', %5$L, '{"address":"2 Oak"}', false, '{}', null, %3$L);
  select t.push(%1$L, 'job', %6$L, '{"status":"scheduled"}', false, array[%8$L]::uuid[], %4$L, %2$L);
  select t.push(%1$L, 'job', %7$L, '{"status":"scheduled"}', false, array[%9$L]::uuid[], %5$L, %3$L);
  select t.push(%1$L, 'visit', %10$L, '{"note":"v1"}', false, '{}', %4$L, %2$L);
  select t.push(%1$L, 'visit', %11$L, '{"note":"v2"}', false, '{}', %5$L, %3$L);
  select t.push(%1$L, 'invoice', %12$L, '{"total":100}');
  select t.push(%1$L, 'memberPay', %13$L, '{"rate":25}');
  select t.push(%1$L, 'member', %14$L, '{"name":"Crew"}');
  select t.push(%1$L, 'setting', %15$L, '{"k":"v"}');
$f$, :'ba', :'C1', :'C2', :'S1', :'S2', :'J1', :'J2', :'M1', :'M2', :'V1', :'V2', :'I1', :'P1', :'MB1', :'ST1'));
reset role; select t.login(:'crew2A');
select t.succeeds('crew2 clocks in (own timeEntry)', format($$select t.push(%L, 'timeEntry', %L, '{"in":"07:00"}')$$, :'ba', :'T1'));

reset role; select t.login(:'ownerA');
select t.ok('owner sees every record (13)', (select count(*) = 13 from public.records where business_id = :'ba'));
select t.ok('owner sees all members of A, disabled included (6)', (select count(*) = 6 from public.members where business_id = :'ba'));
update public.businesses set name = 'Ridgeline Ops' where id = :'ba';
select t.ok('rename stuck', (select name = 'Ridgeline Ops' from public.businesses where id = :'ba'));
select t.fails('owner cannot hand the business to someone else',
  format($$update public.businesses set owner_id = %L where id = %L$$, :'loner', :'ba'));

\echo '--- crew member reads'
reset role; select t.login(:'crewA');
select t.ok('crew sees only the assigned job (J1)',
  (select array_agg(id) = array[:'J1']::uuid[] from public.records where kind = 'job'));
select t.ok('crew sees only the customer of that job (C1)',
  (select array_agg(id) = array[:'C1']::uuid[] from public.records where kind = 'customer'));
select t.ok('crew sees only the site of that job (S1)',
  (select array_agg(id) = array[:'S1']::uuid[] from public.records where kind = 'site'));
select t.ok('crew sees visits on that job''s site only (V1)',
  (select array_agg(id) = array[:'V1']::uuid[] from public.records where kind = 'visit'));
select t.ok('crew sees no invoices', (select count(*) = 0 from public.records where kind = 'invoice'));
select t.ok('crew sees no memberPay', (select count(*) = 0 from public.records where kind = 'memberPay'));
select t.ok('crew does not see other people''s time entries', (select count(*) = 0 from public.records where kind = 'timeEntry'));
select t.ok('crew sees member and setting rows', (select count(*) = 2 from public.records where kind in ('member', 'setting')));
select t.ok('crew sees the members of their own business (6)', (select count(*) = 6 from public.members));
select t.ok('crew sees their own business row only', (select array_agg(id) = array[:'ba']::uuid[] from public.businesses));
select t.ok('helper can_read_job: J1 yes, J2 no', public.can_read_job(:'ba', :'J1') and not public.can_read_job(:'ba', :'J2'));

\echo '--- crew member writes'
select t.succeeds('crew logs a visit', format($$select t.push(%L, 'visit', %L, '{"note":"done"}', false, '{}', %L, %L)$$, :'ba', :'V3', :'S1', :'C1'));
select seq as j1_seq_before from public.records where business_id = :'ba' and kind = 'job' and id = :'J1' \gset
select t.succeeds('crew changes status of the assigned job', format($$select t.push(%L, 'job', %L, '{"status":"done"}', false, array[%L]::uuid[], %L, %L)$$, :'ba', :'J1', :'M1', :'S1', :'C1'));
select t.ok('status change stored, updated_by = crew',
  (select data->>'status' = 'done' and updated_by = :'crewA' from public.records where business_id = :'ba' and kind = 'job' and id = :'J1'));
select t.ok('seq increases on update',
  (select seq > :j1_seq_before from public.records where business_id = :'ba' and kind = 'job' and id = :'J1'));
select t.succeeds('crew changes status with a plain UPDATE (PATCH) too',
  format($$update public.records set data = '{"status":"en route"}' where business_id = %L and kind = 'job' and id = %L$$, :'ba', :'J1'));
select t.fails('crew cannot change a job not assigned to them',
  format($$select t.push(%L, 'job', %L, '{"status":"done"}', false, array[%L]::uuid[], %L, %L)$$, :'ba', :'J2', :'M2', :'S2', :'C2'));
select t.fails('crew cannot take over a job by adding themselves',
  format($$select t.push(%L, 'job', %L, '{"status":"done"}', false, array[%L, %L]::uuid[], %L, %L)$$, :'ba', :'J2', :'M2', :'M1', :'S2', :'C2'));
select t.fails('crew cannot create a job (even assigned to themselves)',
  format($$select t.push(%L, 'job', %L, '{"status":"new"}', false, array[%L]::uuid[])$$, :'ba', :'J3', :'M1'));
select t.fails('crew cannot reassign their job',
  format($$select t.push(%L, 'job', %L, '{"status":"done"}', false, array[%L]::uuid[], %L, %L)$$, :'ba', :'J1', :'M2', :'S1', :'C1'));
select t.fails('crew cannot delete their job (deleted = true)',
  format($$select t.push(%L, 'job', %L, '{"status":"done"}', true, array[%L]::uuid[], %L, %L)$$, :'ba', :'J1', :'M1', :'S1', :'C1'));
select t.fails('crew cannot create a customer',
  format($$select t.push(%L, 'customer', gen_random_uuid(), '{"name":"Eve"}')$$, :'ba'));
select t.fails('crew cannot edit the linked customer',
  format($$select t.push(%L, 'customer', %L, '{"name":"Hacked"}')$$, :'ba', :'C1'));
select t.fails('crew cannot write memberPay', format($$select t.push(%L, 'memberPay', gen_random_uuid(), '{"rate":99}')$$, :'ba'));
select t.fails('crew cannot write settings', format($$select t.push(%L, 'setting', %L, '{"k":"x"}')$$, :'ba', :'ST1'));
select t.fails('crew cannot hard-delete', format($$delete from public.records where business_id = %L$$, :'ba'));
select t.fails('crew cannot add a members row', format($$insert into public.members (business_id, user_id, role) values (%L, %L, 'manager')$$, :'ba', :'loner'));
select t.fails('crew cannot change their own permissions', format($$update public.members set permissions = '{viewRevenue}' where user_id = %L$$, :'crewA'));
select t.ok('...and their permissions are unchanged', (select permissions = '{logVisits,useTimeClock}' from public.members where user_id = :'crewA'));
select t.succeeds('crew clocks in', format($$select t.push(%L, 'timeEntry', %L, '{"in":"07:05"}')$$, :'ba', :'T2'));
select t.fails('crew cannot edit someone else''s time entry', format($$select t.push(%L, 'timeEntry', %L, '{"in":"03:00"}')$$, :'ba', :'T1'));
select t.ok('crew sees own time entry only', (select array_agg(id) = array[:'T2']::uuid[] from public.records where kind = 'timeEntry'));

\echo '--- server-side columns cannot be spoofed'
insert into public.records (business_id, kind, id, data, updated_by, updated_at, seq)
values (:'ba', 'visit', gen_random_uuid(), '{"note":"spoof"}', :'ownerA', '2000-01-01', 1);
select t.ok('updated_by, updated_at and seq are forced by the server',
  (select updated_by = :'crewA' and updated_at > now() - interval '1 minute' and seq > 1
   from public.records where data->>'note' = 'spoof'));
update public.records set updated_by = :'ownerA', seq = 2 where business_id = :'ba' and kind = 'visit' and id = :'V3';
select t.ok('an UPDATE that sets updated_by / seq is overwritten by the server',
  (select updated_by = :'crewA' and seq > 2 from public.records where business_id = :'ba' and kind = 'visit' and id = :'V3'));

\echo '--- manager (manageTeam, viewAllJobs, editJobs, viewTeam, viewClients)'
reset role; select t.login(:'mgrA');
select t.ok('manager sees all jobs, customers, sites, visits', (select count(*) = 2 from public.records where kind = 'job')
  and (select count(*) = 2 from public.records where kind = 'customer') and (select count(*) = 4 from public.records where kind = 'visit'));
select t.ok('manager sees all time entries (viewTeam)', (select count(*) = 2 from public.records where kind = 'timeEntry'));
select t.ok('manager sees memberPay (manageTeam) but no invoice',
  (select count(*) = 1 from public.records where kind = 'memberPay') and (select count(*) = 0 from public.records where kind = 'invoice'));
select t.succeeds('manager edits a crew time entry', format($$select t.push(%L, 'timeEntry', %L, '{"in":"07:00","fixed":true}')$$, :'ba', :'T1'));
select t.succeeds('manager reassigns J1 away from crew', format($$select t.push(%L, 'job', %L, '{"status":"scheduled"}', false, array[%L]::uuid[], %L, %L)$$, :'ba', :'J1', :'M2', :'S1', :'C1'));
select t.fails('manager cannot write invoices', format($$select t.push(%L, 'invoice', %L, '{"total":1}')$$, :'ba', :'I1'));
reset role; select t.login(:'crewA');
select t.ok('after reassignment crew no longer sees J1, C1 or S1',
  (select count(*) = 0 from public.records where kind in ('job', 'customer', 'site')));
select t.ok('crew still sees the visit they logged (updated_by = caller)',
  (select count(*) = 1 from public.records where kind = 'visit' and id = :'V3'));
reset role; select t.login(:'crew2A');
select t.ok('crew2 now sees J1 and J2 and both sites', (select count(*) = 2 from public.records where kind = 'job')
  and (select count(*) = 2 from public.records where kind = 'site'));

\echo '--- viewer with viewClients only'
reset role; select t.login(:'viewA');
select t.ok('viewClients sees all customers and sites but no jobs',
  (select count(*) = 2 from public.records where kind = 'customer') and (select count(*) = 2 from public.records where kind = 'site')
  and (select count(*) = 0 from public.records where kind = 'job'));

\echo '--- disabled member'
reset role; select t.login(:'disA');
select t.ok('disabled member sees no records', (select count(*) = 0 from public.records));
select t.ok('disabled member sees no members', (select count(*) = 0 from public.members));
select t.ok('disabled member sees no business', (select count(*) = 0 from public.businesses));
select t.fails('disabled member cannot write', format($$select t.push(%L, 'customer', gen_random_uuid(), '{"name":"x"}')$$, :'ba'));

\echo '--- business isolation'
reset role; select t.login(:'ownerB');
select t.succeeds('owner B writes in B', format($$select t.push(%L, 'customer', %L, '{"name":"B cust"}')$$, :'bb', :'CB1'));
select t.ok('owner B sees nothing of A', (select count(*) = 0 from public.records where business_id = :'ba')
  and (select count(*) = 0 from public.members where business_id = :'ba') and (select count(*) = 0 from public.businesses where id = :'ba'));
select t.fails('owner B cannot write into A', format($$select t.push(%L, 'customer', gen_random_uuid(), '{"name":"x"}')$$, :'ba'));
select t.fails('owner B cannot overwrite an A record', format($$select t.push(%L, 'customer', %L, '{"name":"x"}')$$, :'ba', :'C1'));
reset role; select t.login(:'ownerA');
select t.ok('owner A sees nothing of B', (select count(*) = 0 from public.records where business_id = :'bb')
  and (select count(*) = 0 from public.members where business_id = :'bb'));
select t.fails('owner A cannot write into B', format($$select t.push(%L, 'customer', gen_random_uuid(), '{"name":"x"}')$$, :'bb'));
select t.fails('a record cannot be moved to another business',
  format($$update public.records set business_id = %L where business_id = %L and kind = 'customer' and id = %L$$, :'bb', :'ba', :'C1'));
reset role; select t.login(:'crewA');
select t.fails('crew A cannot write into B', format($$select t.push(%L, 'visit', gen_random_uuid(), '{}')$$, :'bb'));

\echo '--- storage bucket photos'
reset role; select t.login(:'crewA');
select t.succeeds('crew (logVisits) uploads under their business folder',
  format($$insert into storage.objects (bucket_id, name) values ('photos', %L)$$, :'ba' || '/visits/p1.jpg'));
select t.fails('crew cannot upload into another business folder',
  format($$insert into storage.objects (bucket_id, name) values ('photos', %L)$$, :'bb' || '/x.jpg'));
select t.fails('a path that is not a business id is refused (not an error in the policy)',
  $$insert into storage.objects (bucket_id, name) values ('photos', 'not-a-uuid/x.jpg')$$);
reset role; select t.login(:'viewA');
select t.fails('member without logVisits cannot upload',
  format($$insert into storage.objects (bucket_id, name) values ('photos', %L)$$, :'ba' || '/v.jpg'));
select t.ok('any active member reads the business photos', (select count(*) = 1 from storage.objects where bucket_id = 'photos'));
reset role; select t.login(:'ownerB');
select t.ok('another business cannot read them', (select count(*) = 0 from storage.objects where bucket_id = 'photos'));
reset role; select t.login(:'disA');
select t.ok('a disabled member cannot read them', (select count(*) = 0 from storage.objects where bucket_id = 'photos'));

\echo '--- removing a user'
reset role;
delete from auth.users where id = :'crew2A';
select t.ok('deleting the auth user removes the members row', (select count(*) = 0 from public.members where user_id = :'crew2A'));

reset role;
\echo ''
select format('SUMMARY: %s passed, %s failed', count(*) filter (where ok), count(*) filter (where not ok)) from t.results;
