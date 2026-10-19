-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261010000001_initial_schema.sql
-- Normalized schema for QR lifecycle, multi-tiered warranty, and telemetry tracking
-- ==============================================================================

-- 1. Enable Required PostgreSQL Extensions
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- 2. Trigger Function for Automatic updated_at Maintenance
create or replace function public.handle_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql security definer;

-- ==============================================================================
-- 3. PROFILES Table
-- Extends Supabase auth.users with enterprise profile details
-- ==============================================================================
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  company_name text,
  facility_code text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger tr_profiles_updated_at
  before update on public.profiles
  for each row execute function public.handle_updated_at();

-- ==============================================================================
-- 4. USER_ROLES Table
-- Exactly two system roles: 'ADMIN' and 'USER'
-- Enforced via backend checks and triggers to prevent self-elevation
-- ==============================================================================
create table if not exists public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('ADMIN', 'USER')),
  assigned_at timestamptz not null default now(),
  assigned_by uuid references public.profiles(id),
  constraint uq_user_role unique (user_id, role)
);

create index idx_user_roles_user_id on public.user_roles(user_id);
create index idx_user_roles_role on public.user_roles(role);

-- Helper function to check if a user is an ADMIN
create or replace function public.is_admin(p_user_id uuid default auth.uid())
returns boolean as $$
begin
  if p_user_id is null then
    return false;
  end if;
  return exists (
    select 1
    from public.user_roles
    where user_id = p_user_id
      and role = 'ADMIN'
  );
end;
$$ language plpgsql security definer stable;

-- ==============================================================================
-- 5. COMPANY_SETTINGS Table
-- Singleton record storing corporate, tax, and branding details
-- ==============================================================================
create table if not exists public.company_settings (
  id uuid primary key default gen_random_uuid(),
  company_name text not null default 'Pivot Bearings India',
  gst_number text not null,
  address text not null,
  contact_email text not null,
  contact_phone text not null,
  website text not null,
  logo_storage_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger tr_company_settings_updated_at
  before update on public.company_settings
  for each row execute function public.handle_updated_at();

-- ==============================================================================
-- 6. APP_SETTINGS Table
-- System configuration parameters, timeouts, and feature switches
-- ==============================================================================
create table if not exists public.app_settings (
  id uuid primary key default gen_random_uuid(),
  setting_key text not null unique,
  setting_value jsonb not null,
  description text,
  is_public boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger tr_app_settings_updated_at
  before update on public.app_settings
  for each row execute function public.handle_updated_at();

-- ==============================================================================
-- 7. WARRANTY_PLANS Table
-- Standard industrial warranty horizons (3, 6, 12, 24 months)
-- ==============================================================================
create table if not exists public.warranty_plans (
  id uuid primary key default gen_random_uuid(),
  plan_code text not null unique,
  title text not null,
  duration_months integer not null check (duration_months > 0),
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger tr_warranty_plans_updated_at
  before update on public.warranty_plans
  for each row execute function public.handle_updated_at();

-- ==============================================================================
-- 8. QR_BATCHES Table
-- Production lots and manufacturing run manifests
-- ==============================================================================
create table if not exists public.qr_batches (
  id uuid primary key default gen_random_uuid(),
  batch_code text not null unique,
  plant_location text not null,
  lot_date date not null default current_date,
  total_quantity integer not null check (total_quantity > 0),
  default_warranty_plan_id uuid not null references public.warranty_plans(id),
  created_by uuid references public.profiles(id),
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'CLOSED', 'ARCHIVED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_qr_batches_batch_code on public.qr_batches(batch_code);
create trigger tr_qr_batches_updated_at
  before update on public.qr_batches
  for each row execute function public.handle_updated_at();

-- ==============================================================================
-- 9. QR_CODES Table
-- Individual serial bearing assets.
-- RULE: Raster QR images are NOT stored. Payload values and hashes are stored;
-- QR matrices are generated client-side dynamically.
-- ==============================================================================
create table if not exists public.qr_codes (
  id uuid primary key default gen_random_uuid(),
  bearing_id text not null unique check (bearing_id ~* '^PB-[0-9]{4}-[A-Z0-9]{2}$'),
  batch_id uuid not null references public.qr_batches(id) on delete restrict,
  model_number text not null default 'PBI-6204-ZZ',
  payload_value text not null unique,
  payload_hash text not null,
  assigned_warranty_plan_id uuid not null references public.warranty_plans(id),
  assigned_customer_id uuid references public.profiles(id),
  current_lifecycle_state text not null default 'NOT_ACTIVATED' 
    check (current_lifecycle_state in ('NOT_ACTIVATED', 'CURRENTLY_IN', 'CURRENTLY_OUT')),
  first_in_timestamp timestamptz,
  warranty_expiry_timestamp timestamptz,
  is_flagged boolean not null default false,
  flag_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_qr_codes_bearing_id on public.qr_codes(bearing_id);
create index idx_qr_codes_batch_id on public.qr_codes(batch_id);
create index idx_qr_codes_lifecycle_state on public.qr_codes(current_lifecycle_state);
create index idx_qr_codes_customer_id on public.qr_codes(assigned_customer_id);

create trigger tr_qr_codes_updated_at
  before update on public.qr_codes
  for each row execute function public.handle_updated_at();

-- ==============================================================================
-- 10. VERIFICATION_IMAGES Table
-- Optical proof metadata stored in private Supabase Storage
-- ==============================================================================
create table if not exists public.verification_images (
  id uuid primary key default gen_random_uuid(),
  qr_code_id uuid not null references public.qr_codes(id) on delete cascade,
  uploaded_by uuid not null references public.profiles(id),
  storage_path text not null unique,
  sha256_hash text not null,
  file_size_bytes integer not null check (file_size_bytes > 0),
  width integer,
  height integer,
  image_type text not null check (image_type in ('IN_INSTALLATION', 'OUT_REMOVAL', 'CONDITION_INSPECTION')),
  created_at timestamptz not null default now()
);

create index idx_verification_images_qr_code on public.verification_images(qr_code_id);
create index idx_verification_images_hash on public.verification_images(sha256_hash);

-- ==============================================================================
-- 11. BEARING_INSTALLATION_CYCLES Table
-- Operational intervals tracking each installation and removal
-- ==============================================================================
create table if not exists public.bearing_installation_cycles (
  id uuid primary key default gen_random_uuid(),
  qr_code_id uuid not null references public.qr_codes(id) on delete cascade,
  cycle_number integer not null check (cycle_number > 0),
  in_timestamp timestamptz not null default now(),
  in_confirmed_by uuid not null references public.profiles(id),
  in_verification_image_id uuid references public.verification_images(id),
  out_timestamp timestamptz,
  out_confirmed_by uuid references public.profiles(id),
  out_verification_image_id uuid references public.verification_images(id),
  operating_duration_interval interval,
  operating_duration_seconds bigint,
  is_cycle_closed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint uq_bearing_cycle unique (qr_code_id, cycle_number)
);

create index idx_installation_cycles_qr on public.bearing_installation_cycles(qr_code_id);
create trigger tr_installation_cycles_updated_at
  before update on public.bearing_installation_cycles
  for each row execute function public.handle_updated_at();

-- ==============================================================================
-- 12. BEARING_LIFECYCLE_EVENTS Table
-- Immutable historical audit trail for every bearing action
-- ==============================================================================
create table if not exists public.bearing_lifecycle_events (
  id uuid primary key default gen_random_uuid(),
  qr_code_id uuid not null references public.qr_codes(id) on delete cascade,
  event_type text not null check (event_type in (
    'INITIAL_GENERATION',
    'CUSTOMER_ASSIGNMENT',
    'MARKED_IN',
    'MARKED_OUT',
    'INSPECTION',
    'FLAGGED',
    'WARRANTY_EXTENDED'
  )),
  recorded_by uuid not null references public.profiles(id),
  server_timestamp timestamptz not null default now(),
  verification_image_id uuid references public.verification_images(id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index idx_lifecycle_events_qr on public.bearing_lifecycle_events(qr_code_id);
create index idx_lifecycle_events_timestamp on public.bearing_lifecycle_events(server_timestamp);

-- ==============================================================================
-- 13. SCAN_RECORDS Table
-- Optical telemetry logging every scan event
-- ==============================================================================
create table if not exists public.scan_records (
  id uuid primary key default gen_random_uuid(),
  qr_code_id uuid references public.qr_codes(id) on delete set null,
  scanned_payload text not null,
  scanned_by uuid references public.profiles(id) on delete set null,
  is_valid boolean not null default false,
  ip_address text,
  user_agent text,
  device_info text,
  scan_timestamp timestamptz not null default now()
);

create index idx_scan_records_qr on public.scan_records(qr_code_id);
create index idx_scan_records_timestamp on public.scan_records(scan_timestamp);

-- ==============================================================================
-- 14. ADMIN_AUDIT_LOGS Table
-- Audit trail of administrative overrides and operations
-- ==============================================================================
create table if not exists public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id),
  action text not null,
  target_entity text not null,
  target_id uuid,
  old_values jsonb,
  new_values jsonb,
  ip_address text,
  created_at timestamptz not null default now()
);

create index idx_admin_audit_admin on public.admin_audit_logs(admin_id);
create index idx_admin_audit_created on public.admin_audit_logs(created_at);

-- ==============================================================================
-- 15. Automatic User Registration Trigger
-- Ensures new signups automatically create a Profile and default 'USER' role
-- Self-assigned ADMIN privileges are prevented.
-- ==============================================================================
create or replace function public.handle_new_auth_user()
returns trigger as $$
declare
  v_full_name text;
begin
  v_full_name := coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1));

  -- 1. Create profile
  insert into public.profiles (id, full_name, phone, company_name)
  values (
    new.id,
    v_full_name,
    new.raw_user_meta_data->>'phone',
    new.raw_user_meta_data->>'company_name'
  );

  -- 2. Assign standard USER role only (never ADMIN on self-signup)
  insert into public.user_roles (user_id, role)
  values (new.id, 'USER');

  return new;
end;
$$ language plpgsql security definer;

-- Bind trigger to auth.users
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();
