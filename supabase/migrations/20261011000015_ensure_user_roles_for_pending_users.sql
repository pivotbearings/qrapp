-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261011000015_ensure_user_roles_for_pending_users.sql
-- Ensure All Pending & Registered Users are Guaranteed in public.user_roles
-- ==============================================================================

-- 1. Ensure table structure and unique constraint on user_id exists
create table if not exists public.user_roles (
  id uuid default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('ADMIN', 'USER')),
  assigned_at timestamptz not null default now(),
  assigned_by uuid references auth.users(id),
  constraint pk_user_roles primary key (user_id)
);

-- Safely add unique constraint on user_id if primary key was different
do $$
begin
  alter table public.user_roles add constraint uq_user_roles_user_id unique (user_id);
exception
  when duplicate_table or duplicate_object then null;
end $$;

-- 2. Enable RLS and establish policies
alter table public.user_roles enable row level security;

drop policy if exists "UserRoles: Users view own role" on public.user_roles;
create policy "UserRoles: Users view own role"
  on public.user_roles for select
  to authenticated
  using (user_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists "UserRoles: Admin view all roles" on public.user_roles;
create policy "UserRoles: Admin view all roles"
  on public.user_roles for select
  to authenticated
  using (public.is_admin(auth.uid()));

drop policy if exists "UserRoles: Self insert initial USER role" on public.user_roles;
create policy "UserRoles: Self insert initial USER role"
  on public.user_roles for insert
  to authenticated
  with check (user_id = auth.uid() and role = 'USER');

drop policy if exists "UserRoles: Admin manage roles" on public.user_roles;
create policy "UserRoles: Admin manage roles"
  on public.user_roles for all
  to authenticated
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

-- 3. Automatic Trigger Function on auth.users
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_name text;
  v_phone text;
  v_full_name text;
  v_facility_code text;
begin
  v_company_name := coalesce(nullif(trim(new.raw_user_meta_data->>'company_name'), ''), 'Corporate Account');
  v_phone := nullif(trim(new.raw_user_meta_data->>'phone'), '');
  v_full_name := coalesce(
    nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
    nullif(trim(new.raw_user_meta_data->>'company_name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Operator'
  );
  v_facility_code := coalesce(
    nullif(trim(new.raw_user_meta_data->>'facility_code'), ''),
    concat('FAC-', upper(substring(regexp_replace(coalesce(v_company_name, 'REG'), '[^a-zA-Z0-9]', '', 'g') from 1 for 4)))
  );

  -- Insert profile
  insert into public.profiles (
    id, email, full_name, phone, company_name, facility_code, is_approved, is_active
  )
  values (
    new.id, new.email, v_full_name, v_phone, v_company_name, v_facility_code, false, true
  )
  on conflict (id) do update set
    email = coalesce(excluded.email, public.profiles.email),
    full_name = coalesce(nullif(excluded.full_name, ''), public.profiles.full_name),
    phone = coalesce(excluded.phone, public.profiles.phone),
    company_name = coalesce(nullif(excluded.company_name, ''), public.profiles.company_name),
    facility_code = coalesce(nullif(excluded.facility_code, ''), public.profiles.facility_code),
    updated_at = now();

  -- Guaranteed insert into user_roles table for pending user
  insert into public.user_roles (user_id, role)
  values (new.id, 'USER')
  on conflict (user_id) do nothing;

  return new;
exception
  when others then
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- 4. Automatic Trigger Function on public.profiles
-- Ensures that whenever a profile is inserted, a USER role record is immediately created in user_roles
create or replace function public.ensure_user_role_from_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_roles (user_id, role)
  values (new.id, 'USER')
  on conflict (user_id) do nothing;
  return new;
exception
  when others then
    return new;
end;
$$;

drop trigger if exists tr_ensure_user_role on public.profiles;
create trigger tr_ensure_user_role
  after insert on public.profiles
  for each row execute function public.ensure_user_role_from_profile();

-- 5. Comprehensive Immediate Backfill for all existing users & profiles
insert into public.user_roles (user_id, role)
select id, 'USER'
from auth.users u
where not exists (
  select 1 from public.user_roles ur where ur.user_id = u.id
)
on conflict (user_id) do nothing;

insert into public.user_roles (user_id, role)
select id, 'USER'
from public.profiles p
where not exists (
  select 1 from public.user_roles ur where ur.user_id = p.id
)
on conflict (user_id) do nothing;
