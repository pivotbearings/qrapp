-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261011000014_user_signup_metadata.sql
-- Automatic Ingestion & Association of User Sign-Up Metadata:
-- Company Name, Contact Number (Phone), Email, & Auto-Generated Facility Code
-- ==============================================================================

-- 1. Ensure all metadata columns exist on public.profiles
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists phone text;
alter table public.profiles add column if not exists company_name text;
alter table public.profiles add column if not exists facility_code text;

-- 2. Enhanced handle_new_auth_user trigger with strict metadata capture
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
  -- Extract company name and phone safely from auth metadata
  v_company_name := coalesce(nullif(trim(new.raw_user_meta_data->>'company_name'), ''), 'Corporate Account');
  v_phone := nullif(trim(new.raw_user_meta_data->>'phone'), '');
  
  -- Extract display name (prefers company name or full_name)
  v_full_name := coalesce(
    nullif(trim(new.raw_user_meta_data->>'company_name'), ''),
    nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Operator'
  );

  -- Generate facility code from company name if not explicitly set
  v_facility_code := coalesce(
    nullif(trim(new.raw_user_meta_data->>'facility_code'), ''),
    concat('FAC-', upper(substring(regexp_replace(coalesce(v_company_name, 'REG'), '[^a-zA-Z0-9]', '', 'g') from 1 for 4)))
  );

  -- 1. Upsert profile with all mandatory sign-up details
  insert into public.profiles (
    id,
    email,
    full_name,
    phone,
    company_name,
    facility_code,
    is_approved,
    is_active
  )
  values (
    new.id,
    new.email,
    v_full_name,
    v_phone,
    v_company_name,
    v_facility_code,
    false, -- Pending admin approval
    true
  )
  on conflict (id) do update set
    email = coalesce(excluded.email, public.profiles.email),
    full_name = coalesce(nullif(excluded.full_name, ''), public.profiles.full_name),
    phone = coalesce(excluded.phone, public.profiles.phone),
    company_name = coalesce(nullif(excluded.company_name, ''), public.profiles.company_name),
    facility_code = coalesce(nullif(excluded.facility_code, ''), public.profiles.facility_code),
    updated_at = now();

  -- 2. Ensure standard USER role is granted in user_roles
  insert into public.user_roles (user_id, role)
  values (new.id, 'USER')
  on conflict (user_id) do nothing;

  return new;
exception
  when others then
    return new;
end;
$$;

-- 3. Re-attach trigger to auth.users if not already active
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- 4. Backfill existing profiles from auth.users metadata where available
update public.profiles p
set
  email = coalesce(p.email, u.email),
  company_name = coalesce(nullif(p.company_name, ''), nullif(u.raw_user_meta_data->>'company_name', ''), p.company_name),
  phone = coalesce(nullif(p.phone, ''), nullif(u.raw_user_meta_data->>'phone', ''), p.phone),
  facility_code = coalesce(nullif(p.facility_code, ''), nullif(u.raw_user_meta_data->>'facility_code', ''), 'FAC-REG')
from auth.users u
where p.id = u.id;
