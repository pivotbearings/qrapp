-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261012000020_user_module_permissions_rbac.sql
-- Role-Based Access Control (RBAC) for Warranty and Track Your Bearing Modules
-- ==============================================================================

-- 1. Add module permission columns to public.profiles (OFF by default for all new users)
alter table public.profiles 
add column if not exists has_warranty_access boolean not null default false;

alter table public.profiles 
add column if not exists has_track_bearing_access boolean not null default false;

-- Create indexes for rapid filtering
create index if not exists idx_profiles_warranty_access on public.profiles(has_warranty_access);
create index if not exists idx_profiles_track_access on public.profiles(has_track_bearing_access);

-- 2. Update existing admin profiles so admins always retain full access
update public.profiles p
set has_warranty_access = true,
    has_track_bearing_access = true
from public.user_roles r
where p.id = r.user_id and r.role = 'ADMIN';

-- 3. Update handle_new_auth_user trigger function
-- Guarantees every newly registered user has:
-- - has_warranty_access = FALSE
-- - has_track_bearing_access = FALSE
-- (Access only to Bearing Authentication page by default)
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_company_name text;
  v_phone text;
  v_full_name text;
  v_facility_code text;
  v_email text;
  v_is_admin boolean;
begin
  -- 1. Extract clean user email
  v_email := lower(trim(coalesce(new.email, '')));
  v_is_admin := (v_email = 'abc@gmail.com' or v_email like '%admin%');

  -- 2. Extract company name and phone from signup metadata
  v_company_name := coalesce(nullif(trim(new.raw_user_meta_data->>'company_name'), ''), 'Corporate Account');
  v_phone := nullif(trim(new.raw_user_meta_data->>'phone'), '');

  -- 3. Extract display full name
  v_full_name := coalesce(
    nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
    nullif(trim(new.raw_user_meta_data->>'company_name'), ''),
    nullif(split_part(v_email, '@', 1), ''),
    'Operator'
  );

  -- 4. Generate facility code
  v_facility_code := coalesce(
    nullif(trim(new.raw_user_meta_data->>'facility_code'), ''),
    concat('FAC-', upper(substring(regexp_replace(coalesce(v_company_name, 'REG'), '[^a-zA-Z0-9]', '', 'g') from 1 for 4)))
  );

  -- 5. Upsert into public.profiles with default OFF for modules
  insert into public.profiles (
    id,
    email,
    full_name,
    phone,
    company_name,
    facility_code,
    is_approved,
    is_active,
    has_warranty_access,
    has_track_bearing_access,
    created_at,
    updated_at
  )
  values (
    new.id,
    v_email,
    v_full_name,
    v_phone,
    v_company_name,
    v_facility_code,
    v_is_admin, -- Admins are auto-approved, standard users are pending
    true,
    v_is_admin, -- OFF by default for standard users, ON for admin
    v_is_admin, -- OFF by default for standard users, ON for admin
    now(),
    now()
  )
  on conflict (id) do update set
    email = coalesce(excluded.email, public.profiles.email),
    full_name = coalesce(nullif(excluded.full_name, ''), public.profiles.full_name),
    phone = coalesce(excluded.phone, public.profiles.phone),
    company_name = coalesce(nullif(excluded.company_name, ''), public.profiles.company_name),
    facility_code = coalesce(nullif(excluded.facility_code, ''), public.profiles.facility_code),
    is_approved = case when v_is_admin then true else public.profiles.is_approved end,
    has_warranty_access = case when v_is_admin then true else public.profiles.has_warranty_access end,
    has_track_bearing_access = case when v_is_admin then true else public.profiles.has_track_bearing_access end,
    updated_at = now();

  -- 6. Guarantee record in public.user_roles
  insert into public.user_roles (user_id, role, assigned_at)
  values (
    new.id,
    case when v_is_admin then 'ADMIN' else 'USER' end,
    now()
  )
  on conflict (user_id) do update set
    role = case
      when public.user_roles.role = 'ADMIN' then 'ADMIN'
      when v_is_admin then 'ADMIN'
      else public.user_roles.role
    end;

  return new;
exception
  when others then
    raise warning 'handle_new_auth_user notice: %', sqlerrm;
    return new;
end;
$$;

-- 4. Stored Procedure: admin_update_user_module_permissions
-- Allows administrators to enable or disable Warranty and Track modules independently
create or replace function public.admin_update_user_module_permissions(
  p_target_user_id uuid,
  p_has_warranty boolean,
  p_has_track_bearing boolean
)
returns jsonb as $$
declare
  v_admin_id uuid := auth.uid();
begin
  -- Enforce Administrator role
  if not public.is_admin(v_admin_id) then
    raise exception 'Unauthorized: Only administrators can update user module permissions.'
      using errcode = '42501';
  end if;

  update public.profiles
  set has_warranty_access = coalesce(p_has_warranty, false),
      has_track_bearing_access = coalesce(p_has_track_bearing, false),
      updated_at = now()
  where id = p_target_user_id;

  return jsonb_build_object(
    'success', true,
    'user_id', p_target_user_id,
    'has_warranty_access', p_has_warranty,
    'has_track_bearing_access', p_has_track_bearing
  );
end;
$$ language plpgsql security definer;

-- 5. Execution Grants
grant execute on function public.admin_update_user_module_permissions(uuid, boolean, boolean) to authenticated;
