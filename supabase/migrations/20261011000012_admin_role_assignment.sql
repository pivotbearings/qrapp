-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261011000012_admin_role_assignment.sql
-- Dedicated Admin Role Assignment, Onboarding Clearance & Live User Directives
-- ==============================================================================

-- 1. Ensure email column exists on public.profiles
alter table public.profiles add column if not exists email text;

-- Populate existing profile emails from auth.users
update public.profiles p
set email = u.email
from auth.users u
where p.id = u.id and (p.email is null or p.email = '');

-- 2. Enhanced automatic auth user onboarding trigger
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
  insert into public.profiles (id, email, full_name, phone, company_name, facility_code, is_approved, is_active)
  values (
    new.id,
    new.email,
    v_full_name,
    new.raw_user_meta_data->>'phone',
    new.raw_user_meta_data->>'company_name',
    new.raw_user_meta_data->>'facility_code',
    false, -- Requires Admin approval
    true
  )
  on conflict (id) do update set
    email = coalesce(excluded.email, public.profiles.email),
    full_name = coalesce(nullif(excluded.full_name, ''), public.profiles.full_name),
    company_name = coalesce(excluded.company_name, public.profiles.company_name),
    facility_code = coalesce(excluded.facility_code, public.profiles.facility_code),
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

-- 3. Dedicated Admin RPC: Fetch all users for role assignment and clearance
drop function if exists public.admin_get_all_users();
create or replace function public.admin_get_all_users()
returns table (
  id uuid,
  email text,
  full_name text,
  company_name text,
  facility_code text,
  role text,
  is_approved boolean,
  is_active boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- RBAC Guard: Only Admins can execute
  if not public.is_admin(auth.uid()) then
    raise exception 'Access Denied: Only administrators can view role assignments.' using errcode = '42501';
  end if;

  return query
  select
    u.id,
    u.email::text,
    coalesce(p.full_name, split_part(u.email, '@', 1), 'Operator')::text as full_name,
    coalesce(p.company_name, '')::text as company_name,
    coalesce(p.facility_code, '')::text as facility_code,
    coalesce(r.role, 'USER')::text as role,
    coalesce(p.is_approved, false) as is_approved,
    coalesce(p.is_active, true) as is_active,
    u.created_at
  from auth.users u
  left join public.profiles p on p.id = u.id
  left join public.user_roles r on r.user_id = u.id
  order by u.created_at desc;
end;
$$;

-- 4. Dedicated Admin RPC: Update user role and clearance
drop function if exists public.admin_update_user_role_and_clearance(uuid, text, boolean);
create or replace function public.admin_update_user_role_and_clearance(
  p_target_user_id uuid,
  p_role text,
  p_approved boolean
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_normalized_role text;
begin
  -- RBAC Guard: Only Admins can modify
  if not public.is_admin(auth.uid()) then
    raise exception 'Access Denied: Only administrators can update roles and clearances.' using errcode = '42501';
  end if;

  v_normalized_role := upper(trim(p_role));
  if v_normalized_role not in ('ADMIN', 'USER') then
    raise exception 'Invalid role "%". Supported enterprise roles: ADMIN, USER', p_role;
  end if;

  -- 1. Update profiles table
  update public.profiles
  set is_approved = p_approved,
      is_active = p_approved,
      updated_at = now()
  where id = p_target_user_id;

  if not found then
    insert into public.profiles (id, full_name, is_approved, is_active)
    values (p_target_user_id, 'Operator', p_approved, p_approved);
  end if;

  -- 2. Update user_roles table (Zero constraint dependencies)
  delete from public.user_roles where user_id = p_target_user_id;
  insert into public.user_roles (user_id, role, assigned_at, assigned_by)
  values (p_target_user_id, v_normalized_role, now(), auth.uid());

  return format('SUCCESS: User %s updated to role [%s], approved=%s', p_target_user_id, v_normalized_role, p_approved);
end;
$$;

-- 5. Permissions
grant execute on function public.admin_get_all_users() to authenticated;
grant execute on function public.admin_update_user_role_and_clearance(uuid, text, boolean) to authenticated;

-- 6. Immediately promote abc@gmail.com to ADMIN and configure user@gmail.com as USER
do $$
declare
  v_admin_id uuid;
  v_user_id uuid;
begin
  -- 1. Ensure abc@gmail.com is set as ADMIN and approved if present in auth.users
  select id into v_admin_id from auth.users where lower(email) = 'abc@gmail.com';
  if v_admin_id is not null then
    update public.profiles
    set email = 'abc@gmail.com',
        full_name = 'Chief System Administrator',
        company_name = 'Pivot Bearings India Ltd',
        facility_code = 'PBI-HQ-CHAKAN',
        is_approved = true,
        is_active = true,
        updated_at = now()
    where id = v_admin_id;
    if not found then
      insert into public.profiles (id, email, full_name, company_name, facility_code, is_approved, is_active)
      values (v_admin_id, 'abc@gmail.com', 'Chief System Administrator', 'Pivot Bearings India Ltd', 'PBI-HQ-CHAKAN', true, true);
    end if;

    delete from public.user_roles where user_id = v_admin_id;
    insert into public.user_roles (user_id, role, assigned_at)
    values (v_admin_id, 'ADMIN', now());
  end if;

  -- 2. Ensure user@gmail.com is configured as standard USER
  select id into v_user_id from auth.users where lower(email) = 'user@gmail.com';
  if v_user_id is not null then
    update public.profiles
    set email = 'user@gmail.com',
        full_name = 'Certified Field Inspector',
        company_name = 'Apex Engineering Facility',
        facility_code = 'APX-IND-04',
        updated_at = now()
    where id = v_user_id;

    if not found then
      insert into public.profiles (id, email, full_name, company_name, facility_code, is_approved, is_active)
      values (v_user_id, 'user@gmail.com', 'Certified Field Inspector', 'Apex Engineering Facility', 'APX-IND-04', false, true);
    end if;

    delete from public.user_roles where user_id = v_user_id;
    insert into public.user_roles (user_id, role, assigned_at)
    values (v_user_id, 'USER', now());
  end if;
end $$;
