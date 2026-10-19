-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261011000011_fix_authentication_and_rbac.sql
-- Enterprise-grade, Secure Authentication, Onboarding Approval Workflow & RBAC
-- ==============================================================================

-- 1. Enable Required Extensions
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- ==============================================================================
-- 2. Ensure PROFILES Table Exists with is_approved Clearance Flag
-- ==============================================================================
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default 'Operator',
  phone text,
  company_name text,
  facility_code text,
  is_active boolean not null default true,
  is_approved boolean not null default false, -- Mandatory Admin Clearance
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Safely ensure is_approved column exists if table pre-existed
alter table public.profiles add column if not exists is_approved boolean not null default false;

-- ==============================================================================
-- 3. Ensure USER_ROLES Table Exists (1 Authoritative Role per User)
-- ==============================================================================
create table if not exists public.user_roles (
  id uuid default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('ADMIN', 'USER')),
  assigned_at timestamptz not null default now(),
  assigned_by uuid references auth.users(id),
  constraint pk_user_roles primary key (user_id)
);

-- If table pre-existed with multi-column constraint, upgrade to unique user_id
alter table public.user_roles drop constraint if exists uq_user_role;

-- Clean any pre-existing duplicates (prioritize ADMIN role)
delete from public.user_roles a
where exists (
  select 1 from public.user_roles b
  where b.user_id = a.user_id
    and (b.role = 'ADMIN' and a.role = 'USER')
);

delete from public.user_roles a
where exists (
  select 1 from public.user_roles b
  where b.user_id = a.user_id
    and b.ctid < a.ctid
);

-- Ensure unique constraint on user_id exists
do $$
begin
  alter table public.user_roles add constraint uq_user_roles_user_id unique (user_id);
exception
  when duplicate_table or duplicate_object then null;
end $$;

-- Indices for rapid lookup
create index if not exists idx_user_roles_user_id on public.user_roles(user_id);
create index if not exists idx_user_roles_role on public.user_roles(role);

-- Ensure any existing administrators are automatically approved
update public.profiles
set is_approved = true,
    is_active = true
where id in (select user_id from public.user_roles where role = 'ADMIN');

-- ==============================================================================
-- 4. Fast, Security-Definer Role Helpers (Guaranteed No Infinite Recursion)
-- ==============================================================================
-- Check if user is ADMIN
create or replace function public.is_admin(p_user_id uuid default auth.uid())
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.user_roles
    where user_id = coalesce(p_user_id, auth.uid())
      and role = 'ADMIN'
  );
$$;

-- Check if current user is approved
create or replace function public.is_current_user_approved()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (select is_approved or public.is_admin(auth.uid()) from public.profiles where id = auth.uid() limit 1),
    false
  );
$$;

-- Get current user's role
create or replace function public.get_my_role()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (select role from public.user_roles where user_id = auth.uid() limit 1),
    'USER'
  );
$$;

-- ==============================================================================
-- 5. Enable Row-Level Security
-- ==============================================================================
alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;

-- ==============================================================================
-- 6. Non-Recursive RLS Policies for USER_ROLES
-- ==============================================================================
drop policy if exists "UserRoles: Users can read own role" on public.user_roles;
drop policy if exists "UserRoles: Allow read own role" on public.user_roles;
drop policy if exists "UserRoles: Admins can insert roles" on public.user_roles;
drop policy if exists "UserRoles: Admin insert roles" on public.user_roles;
drop policy if exists "UserRoles: Admins can update roles" on public.user_roles;
drop policy if exists "UserRoles: Admin update roles" on public.user_roles;
drop policy if exists "UserRoles: Admins can delete roles" on public.user_roles;
drop policy if exists "UserRoles: Admin delete roles" on public.user_roles;
drop policy if exists "UserRoles: Admin view all roles" on public.user_roles;
drop policy if exists "UserRoles: Admin manage roles" on public.user_roles;

-- Every authenticated user can read their own role (zero subquery, zero recursion)
create policy "UserRoles: Allow read own role"
  on public.user_roles for select
  to authenticated
  using (auth.uid() = user_id);

-- Admins can view all user roles
create policy "UserRoles: Admin view all roles"
  on public.user_roles for select
  to authenticated
  using (public.is_admin(auth.uid()));

-- Admins can insert/update/delete roles
create policy "UserRoles: Admin insert roles"
  on public.user_roles for insert
  to authenticated
  with check (public.is_admin(auth.uid()));

create policy "UserRoles: Admin update roles"
  on public.user_roles for update
  to authenticated
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

create policy "UserRoles: Admin delete roles"
  on public.user_roles for delete
  to authenticated
  using (public.is_admin(auth.uid()));

-- ==============================================================================
-- 7. RLS Policies for PROFILES
-- ==============================================================================
drop policy if exists "Profiles: Users can read own profile" on public.profiles;
drop policy if exists "Profiles: Users can update own profile" on public.profiles;
drop policy if exists "Profiles: Users can insert own profile" on public.profiles;
drop policy if exists "Profiles: Admin view all profiles" on public.profiles;

create policy "Profiles: Users can read own profile"
  on public.profiles for select
  to authenticated
  using (auth.uid() = id or public.is_admin(auth.uid()));

create policy "Profiles: Users can insert own profile"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id or public.is_admin(auth.uid()));

create policy "Profiles: Users can update own profile"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id or public.is_admin(auth.uid()))
  with check (auth.uid() = id or public.is_admin(auth.uid()));

-- ==============================================================================
-- 8. Safe Trigger for Automatic Auth User Onboarding
-- New users start with is_approved = false (Pending Admin Approval)
-- ==============================================================================
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_full_name text;
begin
  -- Extract full name safely with fallback to email prefix
  v_full_name := coalesce(
    nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Operator'
  );

  -- 1. Create or update profile with is_approved = false by default
  insert into public.profiles (id, full_name, phone, company_name, is_approved, is_active)
  values (
    new.id,
    v_full_name,
    new.raw_user_meta_data->>'phone',
    new.raw_user_meta_data->>'company_name',
    false, -- Requires Admin approval
    true
  )
  on conflict (id) do update set
    full_name = coalesce(nullif(excluded.full_name, ''), public.profiles.full_name),
    company_name = coalesce(excluded.company_name, public.profiles.company_name),
    updated_at = now();

  -- 2. Assign standard USER role by default
  insert into public.user_roles (user_id, role)
  values (new.id, 'USER')
  on conflict (user_id) do nothing;

  return new;
exception
  when others then
    return new;
end;
$$;

-- Bind trigger to auth.users
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ==============================================================================
-- 9. Enterprise Helper Procedures for Easy Admin Control via SQL & UI
-- ==============================================================================

-- Procedure 1: Approve any user by email directly in SQL
-- Usage: SELECT approve_user('operator@company.com');
--    or: SELECT approve_user('admin@company.com', 'ADMIN');
create or replace function public.approve_user(
  p_email text,
  p_role text default 'USER'
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_normalized_role text;
begin
  v_normalized_role := upper(trim(p_role));
  if v_normalized_role not in ('ADMIN', 'USER') then
    raise exception 'Invalid role "%". Supported roles: ADMIN, USER', p_role;
  end if;

  select id into v_user_id
  from auth.users
  where lower(email) = lower(trim(p_email));

  if v_user_id is null then
    raise exception 'User not found with email: %. Ensure user has registered first.', p_email;
  end if;

  -- 1. Mark approved in profiles
  update public.profiles
  set is_approved = true,
      is_active = true,
      updated_at = now()
  where id = v_user_id;

  -- 2. Upsert role
  insert into public.user_roles (user_id, role, assigned_at)
  values (v_user_id, v_normalized_role, now())
  on conflict (user_id) do update set
    role = v_normalized_role,
    assigned_at = now();

  return format('SUCCESS: User %s has been APPROVED with role [%s].', p_email, v_normalized_role);
end;
$$;

-- Procedure 2: Approve user by UUID (Called directly from Admin Dashboard UI)
create or replace function public.approve_user_by_id(
  p_user_id uuid,
  p_role text default 'USER'
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_normalized_role text;
begin
  -- RBAC guard: Only admins can approve users
  if not public.is_admin(auth.uid()) then
    raise exception 'Access Denied: Only administrators can approve users.' using errcode = '42501';
  end if;

  v_normalized_role := upper(trim(p_role));
  if v_normalized_role not in ('ADMIN', 'USER') then
    raise exception 'Invalid role "%"', p_role;
  end if;

  update public.profiles
  set is_approved = true,
      is_active = true,
      updated_at = now()
  where id = p_user_id;

  insert into public.user_roles (user_id, role, assigned_at)
  values (p_user_id, v_normalized_role, now())
  on conflict (user_id) do update set
    role = v_normalized_role,
    assigned_at = now();

  return format('SUCCESS: User ID %s approved with role [%s].', p_user_id, v_normalized_role);
end;
$$;

-- Procedure 3: Set user role and auto-approve
-- Usage: SELECT set_user_role('admin@company.com', 'ADMIN');
create or replace function public.set_user_role(
  p_email text,
  p_role text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_normalized_role text;
begin
  v_normalized_role := upper(trim(p_role));
  if v_normalized_role not in ('ADMIN', 'USER') then
    raise exception 'Invalid role "%". Supported enterprise roles: ADMIN, USER', p_role;
  end if;

  select id into v_user_id
  from auth.users
  where lower(email) = lower(trim(p_email));

  if v_user_id is null then
    raise exception 'User not found with email: %. Please ensure user has registered first.', p_email;
  end if;

  -- Ensure profile exists and is approved
  insert into public.profiles (id, full_name, is_approved, is_active)
  values (v_user_id, split_part(p_email, '@', 1), true, true)
  on conflict (id) do update set
    is_approved = true,
    is_active = true,
    updated_at = now();

  -- Upsert role
  insert into public.user_roles (user_id, role, assigned_at)
  values (v_user_id, v_normalized_role, now())
  on conflict (user_id) do update set
    role = v_normalized_role,
    assigned_at = now();

  return format('SUCCESS: User %s is now assigned role [%s] and approved.', p_email, v_normalized_role);
end;
$$;

-- ==============================================================================
-- 10. Auto-Confirm Users (Sets email_confirmed_at only, letting confirmed_at generate)
-- ==============================================================================
update auth.users
set email_confirmed_at = coalesce(email_confirmed_at, now())
where email_confirmed_at is null;

create or replace function public.auto_confirm_auth_users()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.email_confirmed_at is null then
    new.email_confirmed_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_auto_confirm on auth.users;
create trigger on_auth_user_auto_confirm
  before insert on auth.users
  for each row execute function public.auto_confirm_auth_users();

-- ==============================================================================
-- 11. Schema Permissions
-- ==============================================================================
grant usage on schema public to anon, authenticated, service_role;
grant all on all tables in schema public to postgres, service_role;
grant select, insert, update on public.profiles to authenticated;
grant select on public.user_roles to authenticated;
grant execute on function public.is_admin(uuid) to anon, authenticated, service_role;
grant execute on function public.is_current_user_approved() to authenticated;
grant execute on function public.get_my_role() to authenticated;
grant execute on function public.set_user_role(text, text) to postgres, service_role;
grant execute on function public.approve_user(text, text) to postgres, service_role;
grant execute on function public.approve_user_by_id(uuid, text) to authenticated;
