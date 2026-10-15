-- =====================================================================
-- Stokvel SaaS — multi-club Supabase schema (stage 1: club separation)
-- Run in a NEW Supabase project (SQL Editor > New query > Run). Safe to re-run.
--
-- The one rule everything here enforces:
--   a signed-in person can only ever touch rows whose club_id is THEIR club,
--   and only while their club is 'active'.
-- The browser never sends club_id: the database fills it in (default mk_club()).
-- =====================================================================

-- ---------- Clubs and the platform owner ----------
create table if not exists mk_clubs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact_name text,
  contact_phone text,
  contact_email text,
  status text not null default 'pending' check (status in ('pending','active','suspended')),
  created_at timestamptz not null default now(),
  approved_at timestamptz
);
-- People who run the platform (you). Add yourself once by hand (see bottom of file).
create table if not exists mk_platform_admins (user_id uuid primary key);

create table if not exists mk_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  club_id uuid references mk_clubs(id) on delete cascade,
  role text not null default 'pending' check (role in ('pending','admin','capture','member','auditor')),
  member_full text,
  perms text[] not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists mk_profiles_club_idx on mk_profiles (club_id);

-- ---------- Club data (every table carries club_id) ----------
create or replace function mk_club() returns uuid
language sql stable security definer set search_path = public as $$
  select p.club_id from mk_profiles p join mk_clubs c on c.id = p.club_id
  where p.id = auth.uid() and c.status = 'active';
$$;

create table if not exists mk_members (
  club_id uuid not null default mk_club() references mk_clubs(id) on delete cascade,
  id text not null,
  surname text not null, name text not null, full_name text not null,
  fixed numeric not null default 0,
  resigned boolean default false, resigned_date text,
  primary key (club_id, id)
);
create unique index if not exists mk_members_full_idx on mk_members (club_id, full_name);

create table if not exists mk_datalog (
  club_id uuid not null default mk_club() references mk_clubs(id) on delete cascade,
  id text not null,
  date text, name text not null, month text, year int,
  contr numeric default 0, loan_rep numeric default 0, int_pay numeric default 0,
  pena numeric default 0, b2s numeric default 0, funeral numeric default 0,
  taken numeric default 0, powng numeric default 0, pool_chg numeric default 0,
  source text default 'manual', note text,
  created_by text, created_at timestamptz default now(), updated_by text, updated_at timestamptz,
  primary key (club_id, id)
);
create index if not exists mk_datalog_name_idx on mk_datalog (club_id, name);

create table if not exists mk_settings (
  club_id uuid not null default mk_club() references mk_clubs(id) on delete cascade,
  id text not null, data text not null,
  primary key (club_id, id)
);
create table if not exists mk_att_meetings (
  club_id uuid not null default mk_club() references mk_clubs(id) on delete cascade,
  id text not null, date text, number int, notes text, records text,
  primary key (club_id, id)
);
create table if not exists mk_resignations (
  club_id uuid not null default mk_club() references mk_clubs(id) on delete cascade,
  id text not null, date text, data text,
  primary key (club_id, id)
);
create table if not exists mk_archives (
  club_id uuid not null default mk_club() references mk_clubs(id) on delete cascade,
  id text not null, year int, closed_at text, datalog text,
  primary key (club_id, id)
);
create table if not exists mk_audits (
  club_id uuid not null default mk_club() references mk_clubs(id) on delete cascade,
  id text not null, month text not null, answers text not null,
  overall_status text default 'Incomplete', auditor_name text, signed_off_by text, signed_off_date text,
  member_full text, created_by text, updated_by text, updated_at timestamptz default now(),
  primary key (club_id, id)
);
create table if not exists mk_bank_trips (
  club_id uuid not null default mk_club() references mk_clubs(id) on delete cascade,
  id text not null, trip_date text not null, sig1 text, sig2 text,
  notice_transfer numeric default 0, misc_desc text, misc_amount numeric default 0, petrol numeric default 200,
  notes text, created_at timestamptz default now(), created_by text, updated_by text, updated_at timestamptz,
  primary key (club_id, id)
);
create table if not exists mk_bank_loans (
  club_id uuid not null default mk_club() references mk_clubs(id) on delete cascade,
  id text not null, trip_date text not null, member_name text not null,
  amount numeric default 0, notes text, created_at timestamptz default now(),
  created_by text, updated_by text, updated_at timestamptz,
  primary key (club_id, id)
);
-- Who the club's executives are (the auditor sees only these).
create table if not exists mk_executives (
  club_id uuid not null default mk_club() references mk_clubs(id) on delete cascade,
  member_full text not null, role_title text not null,
  primary key (club_id, member_full)
);
create table if not exists mk_audit_log (
  id bigserial primary key,
  club_id uuid,
  at timestamptz not null default now(),
  user_id uuid, user_email text, user_role text,
  table_name text not null, action text not null, row_id text,
  old_data jsonb, new_data jsonb
);
create index if not exists mk_audit_log_club_at_idx on mk_audit_log (club_id, at desc);

-- ---------- "Who am I?" helpers (all return nothing unless the club is active) ----------
create or replace function mk_role() returns text
language sql stable security definer set search_path = public as $$
  select p.role from mk_profiles p join mk_clubs c on c.id = p.club_id
  where p.id = auth.uid() and c.status = 'active';
$$;
create or replace function mk_member() returns text
language sql stable security definer set search_path = public as $$
  select p.member_full from mk_profiles p join mk_clubs c on c.id = p.club_id
  where p.id = auth.uid() and c.status = 'active';
$$;
create or replace function mk_has(perm text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.role = 'admin' or (p.role = 'capture' and perm = any(p.perms))
    from mk_profiles p join mk_clubs c on c.id = p.club_id
    where p.id = auth.uid() and c.status = 'active'), false);
$$;
create or replace function mk_is_platform_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from mk_platform_admins where user_id = auth.uid());
$$;
create or replace function mk_is_exec(f text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from mk_executives where club_id = mk_club() and member_full = f);
$$;

-- New logins start with no club and no access.
create or replace function mk_handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.mk_profiles (id, email, role, club_id)
  values (new.id, new.email, 'pending',
          (select i.club_id from public.mk_invites i join public.mk_clubs c on c.id = i.club_id
            where i.email = lower(new.email) and c.status <> 'suspended' order by i.invited_at limit 1))
  on conflict (id) do nothing;
  delete from public.mk_invites where email = lower(new.email);
  return new;
end; $$;
drop trigger if exists mk_on_auth_user_created on auth.users;
create trigger mk_on_auth_user_created after insert on auth.users
  for each row execute procedure mk_handle_new_user();

-- A profile's club can never be changed through the API (only by the functions below).
create or replace function mk_lock_club() returns trigger
language plpgsql as $$
begin
  if new.club_id is distinct from old.club_id and current_user not in ('postgres','supabase_admin') and not mk_is_platform_admin() then
    raise exception 'club cannot be changed';
  end if;
  return new;
end; $$;
drop trigger if exists mk_lock_club_trg on mk_profiles;
create trigger mk_lock_club_trg before update on mk_profiles for each row execute procedure mk_lock_club();

-- ---------- Registering and approving a club ----------
-- A new person signs up, then calls this once. The club starts 'pending' and the
-- person is its admin, but nothing works until the platform owner approves it.
create or replace function mk_register_club(p_name text, p_contact text, p_phone text)
returns uuid language plpgsql security definer set search_path = public as $$
declare cid uuid; em text;
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  if exists (select 1 from mk_profiles where id = auth.uid() and club_id is not null) then
    raise exception 'this login already belongs to a club';
  end if;
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'club name needed'; end if;
  select email into em from mk_profiles where id = auth.uid();
  insert into mk_clubs (name, contact_name, contact_phone, contact_email)
    values (trim(p_name), p_contact, p_phone, em) returning id into cid;
  update mk_profiles set club_id = cid, role = 'admin' where id = auth.uid();
  return cid;
end; $$;

create or replace function mk_set_club_status(p_club uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not mk_is_platform_admin() then raise exception 'not allowed'; end if;
  if p_status not in ('active','suspended','pending') then raise exception 'bad status'; end if;
  update mk_clubs set status = p_status,
    approved_at = case when p_status = 'active' and approved_at is null then now() else approved_at end
  where id = p_club;
end; $$;

-- ---------- Inviting people into a club ----------
-- The club admin invites an email. When that person creates their login with that
-- email (or already has one without a club) they are placed in the club as 'pending';
-- the admin then gives them a role. Keep "Confirm email" ON in Supabase
-- (Authentication > Providers > Email) so nobody can claim an email they do not own.
create table if not exists mk_invites (
  club_id uuid not null references mk_clubs(id) on delete cascade,
  email text not null,
  invited_at timestamptz not null default now(),
  primary key (club_id, email)
);

create or replace function mk_invite_user(p_email text) returns text
language plpgsql security definer set search_path = public as $$
declare e text := lower(trim(coalesce(p_email,''))); cid uuid := mk_club(); pid uuid; pclub uuid;
begin
  if cid is null or mk_role() <> 'admin' then raise exception 'not allowed'; end if;
  if e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'that does not look like an email address'; end if;
  select id, club_id into pid, pclub from mk_profiles where lower(email) = e;
  if pid is not null then
    if pclub = cid then return 'That person is already in your club.'; end if;
    if pclub is not null then raise exception 'That email already belongs to another club.'; end if;
    update mk_profiles set club_id = cid, role = 'pending' where id = pid;
    return 'Added. They can sign in now; give them a role below.';
  end if;
  insert into mk_invites (club_id, email) values (cid, e) on conflict do nothing;
  return 'Invited. Ask them to create a login with ' || e || '.';
end; $$;

-- ---------- Row Level Security ----------
do $$
declare t text;
begin
  foreach t in array array['mk_clubs','mk_platform_admins','mk_profiles','mk_members','mk_datalog','mk_settings',
    'mk_att_meetings','mk_resignations','mk_archives','mk_audits','mk_bank_trips','mk_bank_loans','mk_executives','mk_audit_log','mk_invites']
  loop execute format('alter table %I enable row level security', t); end loop;
end $$;

-- Clubs: a person sees their own club (any status, so they can see "waiting for approval");
-- the platform owner sees all. Only the platform owner changes status (via the function).
drop policy if exists "see own club" on mk_clubs;
create policy "see own club" on mk_clubs for select using (
  mk_is_platform_admin() or id = (select club_id from mk_profiles where id = auth.uid()));
drop policy if exists "admin renames club" on mk_clubs;
create policy "admin renames club" on mk_clubs for update
  using (id = mk_club() and mk_role() = 'admin') with check (id = mk_club());
drop policy if exists "owner sees owners" on mk_platform_admins;
create policy "owner sees owners" on mk_platform_admins for select using (mk_is_platform_admin());

-- Profiles
drop policy if exists "self or club admin read" on mk_profiles;
create policy "self or club admin read" on mk_profiles for select using (
  id = auth.uid() or (mk_role() = 'admin' and club_id = mk_club()));
drop policy if exists "club admin update profiles" on mk_profiles;
create policy "club admin update profiles" on mk_profiles for update
  using (mk_role() = 'admin' and club_id = mk_club())
  with check (mk_role() = 'admin' and club_id = mk_club());
drop policy if exists "club admin delete profiles" on mk_profiles;
create policy "club admin delete profiles" on mk_profiles for delete
  using (mk_role() = 'admin' and club_id = mk_club() and id <> auth.uid());

-- Members
drop policy if exists "read" on mk_members;
create policy "read" on mk_members for select using (club_id = mk_club() and (
  mk_role() in ('admin','capture')
  or (mk_role() = 'auditor' and mk_is_exec(full_name))
  or (mk_role() = 'member' and full_name = mk_member())));
drop policy if exists "insert" on mk_members;
create policy "insert" on mk_members for insert with check (club_id = mk_club() and mk_has('members'));
drop policy if exists "update" on mk_members;
create policy "update" on mk_members for update using (club_id = mk_club() and mk_has('members')) with check (club_id = mk_club());
drop policy if exists "delete" on mk_members;
create policy "delete" on mk_members for delete using (club_id = mk_club() and mk_has('members'));

-- Ledger
drop policy if exists "read" on mk_datalog;
create policy "read" on mk_datalog for select using (club_id = mk_club() and (
  mk_role() in ('admin','capture')
  or (mk_role() = 'auditor' and mk_is_exec(name))
  or (mk_role() = 'member' and name = mk_member())));
drop policy if exists "staff insert" on mk_datalog;
create policy "staff insert" on mk_datalog for insert with check (club_id = mk_club() and mk_role() in ('admin','capture'));
drop policy if exists "auditor insert bank loan rows" on mk_datalog;
create policy "auditor insert bank loan rows" on mk_datalog for insert with check (
  club_id = mk_club() and mk_role() = 'auditor' and mk_is_exec(name) and source = 'banktrip'
  and coalesce(taken,0) > 0 and coalesce(contr,0) = 0 and coalesce(loan_rep,0) = 0 and coalesce(int_pay,0) = 0
  and coalesce(pena,0) = 0 and coalesce(b2s,0) = 0 and coalesce(funeral,0) = 0 and coalesce(powng,0) = 0);
drop policy if exists "staff update" on mk_datalog;
create policy "staff update" on mk_datalog for update using (club_id = mk_club() and mk_role() in ('admin','capture')) with check (club_id = mk_club());
drop policy if exists "staff delete" on mk_datalog;
create policy "staff delete" on mk_datalog for delete using (club_id = mk_club() and mk_role() in ('admin','capture'));

-- Settings
drop policy if exists "read" on mk_settings;
create policy "read" on mk_settings for select using (club_id = mk_club());
drop policy if exists "insert" on mk_settings;
create policy "insert" on mk_settings for insert with check (club_id = mk_club() and (mk_has('settings') or mk_has('yearend')));
drop policy if exists "update" on mk_settings;
create policy "update" on mk_settings for update using (club_id = mk_club() and (mk_has('settings') or mk_has('yearend'))) with check (club_id = mk_club());

-- Attendance (admin + capture only)
drop policy if exists "read" on mk_att_meetings;
create policy "read" on mk_att_meetings for select using (club_id = mk_club() and mk_role() in ('admin','capture'));
drop policy if exists "insert" on mk_att_meetings;
create policy "insert" on mk_att_meetings for insert with check (club_id = mk_club() and mk_role() in ('admin','capture'));
drop policy if exists "update" on mk_att_meetings;
create policy "update" on mk_att_meetings for update using (club_id = mk_club() and mk_role() = 'admin') with check (club_id = mk_club());
drop policy if exists "delete" on mk_att_meetings;
create policy "delete" on mk_att_meetings for delete using (club_id = mk_club() and mk_role() = 'admin');

-- Resignations
drop policy if exists "read" on mk_resignations;
create policy "read" on mk_resignations for select using (club_id = mk_club() and mk_role() in ('admin','capture'));
drop policy if exists "insert" on mk_resignations;
create policy "insert" on mk_resignations for insert with check (club_id = mk_club() and mk_has('members'));
drop policy if exists "update" on mk_resignations;
create policy "update" on mk_resignations for update using (club_id = mk_club() and mk_has('members')) with check (club_id = mk_club());
drop policy if exists "delete" on mk_resignations;
create policy "delete" on mk_resignations for delete using (club_id = mk_club() and mk_has('members'));

-- Year-end archives
drop policy if exists "read" on mk_archives;
create policy "read" on mk_archives for select using (club_id = mk_club() and mk_role() in ('admin','capture'));
drop policy if exists "insert" on mk_archives;
create policy "insert" on mk_archives for insert with check (club_id = mk_club() and mk_has('yearend'));
drop policy if exists "delete" on mk_archives;
create policy "delete" on mk_archives for delete using (club_id = mk_club() and mk_has('yearend'));

-- Member audits
drop policy if exists "read" on mk_audits;
create policy "read" on mk_audits for select using (club_id = mk_club() and (mk_role() = 'admin' or (mk_role() = 'auditor' and mk_is_exec(member_full))));
drop policy if exists "insert" on mk_audits;
create policy "insert" on mk_audits for insert with check (club_id = mk_club() and (mk_role() = 'admin' or (mk_role() = 'auditor' and mk_is_exec(member_full))));
drop policy if exists "update" on mk_audits;
create policy "update" on mk_audits for update using (club_id = mk_club() and (mk_role() = 'admin' or (mk_role() = 'auditor' and mk_is_exec(member_full))))
  with check (club_id = mk_club() and (mk_role() = 'admin' or (mk_role() = 'auditor' and mk_is_exec(member_full))));

-- Bank visits and their loans
do $$
declare t text;
begin
  foreach t in array array['mk_bank_trips','mk_bank_loans'] loop
    execute format('drop policy if exists "read" on %I', t);
    execute format('create policy "read" on %I for select using (club_id = mk_club() and mk_role() in (''admin'',''auditor''))', t);
    execute format('drop policy if exists "insert" on %I', t);
    execute format('create policy "insert" on %I for insert with check (club_id = mk_club() and mk_role() in (''admin'',''auditor''))', t);
    execute format('drop policy if exists "update" on %I', t);
    execute format('create policy "update" on %I for update using (club_id = mk_club() and mk_role() in (''admin'',''auditor'')) with check (club_id = mk_club())', t);
    execute format('drop policy if exists "delete" on %I', t);
    execute format('create policy "delete" on %I for delete using (club_id = mk_club() and mk_role() = ''admin'')', t);
  end loop;
end $$;

-- Invites (club admin only)
drop policy if exists "admin manage" on mk_invites;
create policy "admin manage" on mk_invites for all using (club_id = mk_club() and mk_role() = 'admin') with check (club_id = mk_club());

-- Executives
drop policy if exists "read" on mk_executives;
create policy "read" on mk_executives for select using (club_id = mk_club() and mk_role() in ('admin','capture','auditor'));
drop policy if exists "admin manage" on mk_executives;
create policy "admin manage" on mk_executives for all using (club_id = mk_club() and mk_role() = 'admin') with check (club_id = mk_club());

-- Activity log: club admin (or delegated), auditor sees executives + bank visits only
drop policy if exists "read" on mk_audit_log;
create policy "read" on mk_audit_log for select using (club_id = mk_club() and (
  mk_role() = 'admin' or mk_has('activity')
  or (mk_role() = 'auditor' and (
       table_name in ('mk_bank_trips','mk_bank_loans')
       or mk_is_exec(coalesce(new_data->>'name', old_data->>'name', new_data->>'full_name', old_data->>'full_name',
                              new_data->>'member_full', old_data->>'member_full', new_data->>'member_name', old_data->>'member_name'))))));

-- ---------- Stamping and the activity log ----------
create or replace function mk_stamp() returns trigger
language plpgsql security definer set search_path = public as $$
declare who text; r text; stamp text := to_jsonb(now()) #>> '{}';
begin
  select email, role into who, r from mk_profiles where id = auth.uid();
  who := coalesce(who, 'system');
  if tg_op = 'INSERT' then
    new := jsonb_populate_record(new, jsonb_build_object(
      'created_by', case when r = 'admin' then coalesce(nullif(to_jsonb(new)->>'created_by',''), who) else who end,
      'created_at', coalesce(to_jsonb(new)->>'created_at', stamp), 'updated_by', who, 'updated_at', stamp));
  else
    new := jsonb_populate_record(new, jsonb_build_object(
      'created_by', to_jsonb(old)->>'created_by', 'created_at', to_jsonb(old)->>'created_at',
      'updated_by', who, 'updated_at', stamp));
  end if;
  return new;
end; $$;

create or replace function mk_log_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare who text; r text; o jsonb; n jsonb; cid uuid;
begin
  select email, role into who, r from mk_profiles where id = auth.uid();
  if tg_op in ('UPDATE','DELETE') then o := to_jsonb(old); end if;
  if tg_op in ('INSERT','UPDATE') then n := to_jsonb(new); end if;
  cid := coalesce((n->>'club_id')::uuid, (o->>'club_id')::uuid);
  if tg_table_name = 'mk_archives' then o := o - 'datalog'; n := n - 'datalog'; end if;
  if tg_op = 'UPDATE' and (o - 'updated_at' - 'updated_by') = (n - 'updated_at' - 'updated_by') then return null; end if;
  insert into mk_audit_log (club_id, user_id, user_email, user_role, table_name, action, row_id, old_data, new_data)
  values (cid, auth.uid(), coalesce(who,'system'), r, tg_table_name, tg_op, coalesce(n->>'id', o->>'id'), o, n);
  return null;
end; $$;

do $$
declare t text;
begin
  foreach t in array array['mk_datalog','mk_bank_trips','mk_bank_loans','mk_audits'] loop
    execute format('drop trigger if exists mk_stamp_trg on %I', t);
    execute format('create trigger mk_stamp_trg before insert or update on %I for each row execute procedure mk_stamp()', t);
  end loop;
  foreach t in array array['mk_members','mk_datalog','mk_settings','mk_att_meetings','mk_resignations','mk_archives',
                           'mk_audits','mk_bank_trips','mk_bank_loans','mk_executives'] loop
    execute format('drop trigger if exists mk_log_trg on %I', t);
    execute format('create trigger mk_log_trg after insert or update or delete on %I for each row execute procedure mk_log_change()', t);
  end loop;
end $$;

-- ---------- Make yourself the platform owner (run ONCE, with your own email) ----------
-- 1) Create your login in Authentication > Users, then:
--    insert into mk_platform_admins (user_id) select id from auth.users where email = 'you@example.com';
