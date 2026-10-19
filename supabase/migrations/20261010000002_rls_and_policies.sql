-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261010000002_rls_and_policies.sql
-- Comprehensive Row-Level Security (RLS), Server-side Security Definer Operations,
-- and Private Storage Policies.
-- ==============================================================================

-- 1. Enable Row-Level Security on All Exposed Tables
alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.company_settings enable row level security;
alter table public.app_settings enable row level security;
alter table public.warranty_plans enable row level security;
alter table public.qr_batches enable row level security;
alter table public.qr_codes enable row level security;
alter table public.bearing_installation_cycles enable row level security;
alter table public.bearing_lifecycle_events enable row level security;
alter table public.scan_records enable row level security;
alter table public.verification_images enable row level security;
alter table public.admin_audit_logs enable row level security;

-- ==============================================================================
-- 2. PROFILES POLICIES
-- ==============================================================================
create policy "Profiles: Users can read own profile"
  on public.profiles for select
  using (auth.uid() = id or public.is_admin(auth.uid()));

create policy "Profiles: Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id or public.is_admin(auth.uid()))
  with check (auth.uid() = id or public.is_admin(auth.uid()));

-- ==============================================================================
-- 3. USER_ROLES POLICIES
-- Prevent elevation of privileges by ordinary users
-- ==============================================================================
create policy "UserRoles: Users can read own role"
  on public.user_roles for select
  using (auth.uid() = user_id or public.is_admin(auth.uid()));

create policy "UserRoles: Admins can insert roles"
  on public.user_roles for insert
  with check (public.is_admin(auth.uid()));

create policy "UserRoles: Admins can update roles"
  on public.user_roles for update
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

create policy "UserRoles: Admins can delete roles"
  on public.user_roles for delete
  using (public.is_admin(auth.uid()));

-- ==============================================================================
-- 4. COMPANY_SETTINGS POLICIES
-- Read-only for authenticated & anonymous users; mutable strictly by Admins
-- ==============================================================================
create policy "CompanySettings: Public read"
  on public.company_settings for select
  using (true);

create policy "CompanySettings: Admin insert"
  on public.company_settings for insert
  with check (public.is_admin(auth.uid()));

create policy "CompanySettings: Admin update"
  on public.company_settings for update
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

-- ==============================================================================
-- 5. APP_SETTINGS POLICIES
-- ==============================================================================
create policy "AppSettings: Read public or auth settings"
  on public.app_settings for select
  using (is_public = true or auth.role() = 'authenticated');

create policy "AppSettings: Admin manage"
  on public.app_settings for all
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

-- ==============================================================================
-- 6. WARRANTY_PLANS POLICIES
-- ==============================================================================
create policy "WarrantyPlans: Public read active plans"
  on public.warranty_plans for select
  using (is_active = true or public.is_admin(auth.uid()));

create policy "WarrantyPlans: Admin manage"
  on public.warranty_plans for all
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

-- ==============================================================================
-- 7. QR_BATCHES POLICIES
-- ==============================================================================
create policy "QrBatches: Admin full access"
  on public.qr_batches for all
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

-- ==============================================================================
-- 8. QR_CODES POLICIES
-- Ordinary users CANNOT update QR codes directly.
-- Users can inspect their assigned bearings or perform public verification.
-- ==============================================================================
create policy "QrCodes: Read access for verification and ownership"
  on public.qr_codes for select
  using (
    -- Anonymous / general users can verify validity and model
    true
  );

create policy "QrCodes: Admins can insert"
  on public.qr_codes for insert
  with check (public.is_admin(auth.uid()));

create policy "QrCodes: Admins can update"
  on public.qr_codes for update
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

create policy "QrCodes: Admins can delete"
  on public.qr_codes for delete
  using (public.is_admin(auth.uid()));

-- ==============================================================================
-- 9. BEARING_INSTALLATION_CYCLES POLICIES
-- Immutable records modified only through secure stored procedures
-- ==============================================================================
create policy "Cycles: Read for owner or admin"
  on public.bearing_installation_cycles for select
  using (
    in_confirmed_by = auth.uid()
    or out_confirmed_by = auth.uid()
    or exists (
      select 1 from public.qr_codes q
      where q.id = qr_code_id
        and q.assigned_customer_id = auth.uid()
    )
    or public.is_admin(auth.uid())
  );

-- ==============================================================================
-- 10. BEARING_LIFECYCLE_EVENTS POLICIES
-- Immutable audit events
-- ==============================================================================
create policy "Events: Read for owner or admin"
  on public.bearing_lifecycle_events for select
  using (
    recorded_by = auth.uid()
    or exists (
      select 1 from public.qr_codes q
      where q.id = qr_code_id
        and q.assigned_customer_id = auth.uid()
    )
    or public.is_admin(auth.uid())
  );

-- ==============================================================================
-- 11. SCAN_RECORDS POLICIES
-- ==============================================================================
create policy "ScanRecords: Anyone can insert scan telemetry"
  on public.scan_records for insert
  with check (true);

create policy "ScanRecords: Users can read own scans"
  on public.scan_records for select
  using (scanned_by = auth.uid() or public.is_admin(auth.uid()));

-- ==============================================================================
-- 12. VERIFICATION_IMAGES POLICIES
-- ==============================================================================
create policy "VerificationImages: Read for uploader, owner or admin"
  on public.verification_images for select
  using (
    uploaded_by = auth.uid()
    or exists (
      select 1 from public.qr_codes q
      where q.id = qr_code_id
        and q.assigned_customer_id = auth.uid()
    )
    or public.is_admin(auth.uid())
  );

create policy "VerificationImages: Authenticated users can insert"
  on public.verification_images for insert
  with check (auth.role() = 'authenticated' and uploaded_by = auth.uid());

-- ==============================================================================
-- 13. ADMIN_AUDIT_LOGS POLICIES
-- Strictly readable by Admins only
-- ==============================================================================
create policy "AuditLogs: Admin read only"
  on public.admin_audit_logs for select
  using (public.is_admin(auth.uid()));

-- ==============================================================================
-- 14. SERVER-SIDE SECURE STORED PROCEDURES (SECURITY DEFINER)
-- Prevents ordinary users from tampering with timestamps, warranties, or states
-- ==============================================================================

-- Stored Procedure: Confirm Bearing IN (Installation & Warranty Start)
create or replace function public.confirm_bearing_in(
  p_bearing_id text,
  p_verification_image_id uuid default null,
  p_notes text default null
)
returns jsonb as $$
declare
  v_qr record;
  v_plan record;
  v_now timestamptz := now();
  v_new_expiry timestamptz;
  v_cycle_count integer;
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Authentication required to confirm bearing installation.';
  end if;

  -- 1. Fetch QR Record with row lock
  select * into v_qr
  from public.qr_codes
  where bearing_id = p_bearing_id
  for update;

  if not found then
    raise exception 'Bearing ID % not found.', p_bearing_id;
  end if;

  if v_qr.is_flagged then
    raise exception 'Bearing is flagged and locked: %', v_qr.flag_reason;
  end if;

  if v_qr.current_lifecycle_state = 'CURRENTLY_IN' then
    raise exception 'Bearing is already marked IN and currently operating.';
  end if;

  -- 2. Fetch Warranty Plan
  select * into v_plan
  from public.warranty_plans
  where id = v_qr.assigned_warranty_plan_id;

  -- 3. Calculate Expiry:
  -- Business Rule: Warranty anchors to the FIRST confirmed IN timestamp.
  -- Reinstallation does NOT reset or extend the warranty.
  if v_qr.first_in_timestamp is null then
    v_new_expiry := v_now + (v_plan.duration_months || ' months')::interval;
    update public.qr_codes
    set
      current_lifecycle_state = 'CURRENTLY_IN',
      first_in_timestamp = v_now,
      warranty_expiry_timestamp = v_new_expiry,
      assigned_customer_id = coalesce(assigned_customer_id, v_user_id)
    where id = v_qr.id;
  else
    -- Subsequent installation: retain original first IN & expiry anchor
    v_new_expiry := v_qr.warranty_expiry_timestamp;
    update public.qr_codes
    set current_lifecycle_state = 'CURRENTLY_IN'
    where id = v_qr.id;
  end if;

  -- 4. Count and insert new installation cycle
  select coalesce(max(cycle_number), 0) + 1 into v_cycle_count
  from public.bearing_installation_cycles
  where qr_code_id = v_qr.id;

  insert into public.bearing_installation_cycles (
    qr_code_id,
    cycle_number,
    in_timestamp,
    in_confirmed_by,
    in_verification_image_id
  ) values (
    v_qr.id,
    v_cycle_count,
    v_now,
    v_user_id,
    p_verification_image_id
  );

  -- 5. Record immutable lifecycle event
  insert into public.bearing_lifecycle_events (
    qr_code_id,
    event_type,
    recorded_by,
    server_timestamp,
    verification_image_id,
    metadata
  ) values (
    v_qr.id,
    'MARKED_IN',
    v_user_id,
    v_now,
    p_verification_image_id,
    jsonb_build_object(
      'cycle_number', v_cycle_count,
      'is_first_activation', (v_qr.first_in_timestamp is null),
      'warranty_expiry', v_new_expiry,
      'notes', p_notes
    )
  );

  return jsonb_build_object(
    'success', true,
    'bearing_id', p_bearing_id,
    'status', 'CURRENTLY_IN',
    'cycle_number', v_cycle_count,
    'in_timestamp', v_now,
    'warranty_expiry', v_new_expiry
  );
end;
$$ language plpgsql security definer;

-- Stored Procedure: Confirm Bearing OUT (Removal & Operating Duration Calculation)
create or replace function public.confirm_bearing_out(
  p_bearing_id text,
  p_verification_image_id uuid default null,
  p_notes text default null
)
returns jsonb as $$
declare
  v_qr record;
  v_cycle record;
  v_now timestamptz := now();
  v_duration_interval interval;
  v_duration_seconds bigint;
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Authentication required to confirm bearing removal.';
  end if;

  -- 1. Fetch QR Record with row lock
  select * into v_qr
  from public.qr_codes
  where bearing_id = p_bearing_id
  for update;

  if not found then
    raise exception 'Bearing ID % not found.', p_bearing_id;
  end if;

  if v_qr.current_lifecycle_state != 'CURRENTLY_IN' then
    raise exception 'Bearing is not currently marked IN. Cannot record OUT event.';
  end if;

  -- 2. Fetch latest open installation cycle
  select * into v_cycle
  from public.bearing_installation_cycles
  where qr_code_id = v_qr.id
    and is_cycle_closed = false
  order by cycle_number desc
  limit 1
  for update;

  if not found then
    raise exception 'No active installation cycle found for bearing %.', p_bearing_id;
  end if;

  -- 3. Calculate operating cycle duration
  v_duration_interval := v_now - v_cycle.in_timestamp;
  v_duration_seconds := extract(epoch from v_duration_interval)::bigint;

  -- 4. Close cycle
  update public.bearing_installation_cycles
  set
    out_timestamp = v_now,
    out_confirmed_by = v_user_id,
    out_verification_image_id = p_verification_image_id,
    operating_duration_interval = v_duration_interval,
    operating_duration_seconds = v_duration_seconds,
    is_cycle_closed = true
  where id = v_cycle.id;

  -- 5. Update QR Code state
  update public.qr_codes
  set current_lifecycle_state = 'CURRENTLY_OUT'
  where id = v_qr.id;

  -- 6. Record immutable lifecycle event
  insert into public.bearing_lifecycle_events (
    qr_code_id,
    event_type,
    recorded_by,
    server_timestamp,
    verification_image_id,
    metadata
  ) values (
    v_qr.id,
    'MARKED_OUT',
    v_user_id,
    v_now,
    p_verification_image_id,
    jsonb_build_object(
      'cycle_number', v_cycle.cycle_number,
      'duration_seconds', v_duration_seconds,
      'duration_interval', v_duration_interval::text,
      'notes', p_notes
    )
  );

  return jsonb_build_object(
    'success', true,
    'bearing_id', p_bearing_id,
    'status', 'CURRENTLY_OUT',
    'cycle_number', v_cycle.cycle_number,
    'out_timestamp', v_now,
    'operating_seconds', v_duration_seconds
  );
end;
$$ language plpgsql security definer;

-- ==============================================================================
-- 15. PRIVATE STORAGE CONFIGURATION & POLICIES
-- Creates bucket 'verification-images' (Private bucket)
-- ==============================================================================
insert into storage.buckets (id, name, public)
values ('verification-images', 'verification-images', false)
on conflict (id) do update set public = false;

-- Policy 1: Authenticated users can upload to their own user subfolder
create policy "Storage: Authenticated users can upload verification images"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'verification-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Policy 2: Users can view images in their folder or if they are Admin
create policy "Storage: Users can read own images or Admin reads all"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'verification-images'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_admin(auth.uid())
    )
  );

-- Policy 3: Only Admins can delete verification images
create policy "Storage: Admins can delete images"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'verification-images'
    and public.is_admin(auth.uid())
  );
