-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261012000018_bearing_authentication_and_scan_count.sql
-- Bearing Authentication & Global Cross-Device Scan Counter Engine
-- ==============================================================================

-- 1. Add scan_count and timestamp columns to public.qr_codes if not already present
alter table public.qr_codes 
add column if not exists scan_count integer not null default 0;

alter table public.qr_codes 
add column if not exists first_scanned_at timestamptz,
add column if not exists last_scanned_at timestamptz;

-- Create index on scan_count for rapid reporting and auditing
create index if not exists idx_qr_codes_scan_count on public.qr_codes(scan_count);

-- 2. Backfill existing scan counts from scan_records table
update public.qr_codes q
set scan_count = coalesce((
  select count(*) 
  from public.scan_records s 
  where s.qr_code_id = q.id and s.is_valid = true
), 0)
where q.scan_count = 0;

-- Backfill first_scanned_at and last_scanned_at from scan_records if available
update public.qr_codes q
set first_scanned_at = (
  select min(scan_timestamp)
  from public.scan_records s
  where s.qr_code_id = q.id and s.is_valid = true
),
last_scanned_at = (
  select max(scan_timestamp)
  from public.scan_records s
  where s.qr_code_id = q.id and s.is_valid = true
)
where q.first_scanned_at is null;

-- 3. Stored Procedure: authenticate_bearing_qr
-- Authoritative, atomic, concurrency-safe authentication & scan count increment
create or replace function public.authenticate_bearing_qr(
  p_scanned_payload text,
  p_device_info text default null,
  p_ip_address inet default null
)
returns jsonb as $$
declare
  v_trimmed text := trim(coalesce(p_scanned_payload, ''));
  v_bearing_id text;
  v_user_id uuid := auth.uid();
  v_qr record;
  v_batch record;
  v_plan record;
  v_prev_scans integer := 0;
  v_total_scans integer := 1;
  v_device_already_scanned boolean := false;
  v_now timestamptz := now();
begin
  -- 1. Basic sanitization
  if v_trimmed = '' then
    return jsonb_build_object(
      'is_authentic', false,
      'status', 'INVALID',
      'error_code', 'EMPTY_PAYLOAD',
      'message', 'Bearing Authenticity Could Not Be Verified'
    );
  end if;

  -- 2. Extract Bearing ID from URL or Raw Serial
  if v_trimmed ilike 'https://verify.pivotbearings.com/pbi/%' then
    v_bearing_id := split_part(split_part(v_trimmed, '/pbi/', 2), '?', 1);
  elsif v_trimmed ilike '%/pbi/%' then
    v_bearing_id := split_part(split_part(v_trimmed, '/pbi/', 2), '?', 1);
  else
    v_bearing_id := v_trimmed;
  end if;

  v_bearing_id := upper(trim(v_bearing_id));

  -- 3. Format validation check
  -- Matches standard PB-0000-XX, cryptographic PBI-SEC-..., or standard PBI models
  if not (v_bearing_id ~* '^(PB-[0-9]{4}-[A-Z0-9]{2}|PBI-SEC-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}|(PBI|PB)(-[A-Z0-9]{3,8}){2,5})$') then
    -- Log invalid scan attempt into scan_records
    insert into public.scan_records (
      scanned_payload,
      scanned_by,
      is_valid,
      device_info,
      ip_address,
      scan_timestamp
    ) values (
      v_trimmed,
      v_user_id,
      false,
      p_device_info,
      p_ip_address,
      v_now
    );

    return jsonb_build_object(
      'is_authentic', false,
      'status', 'INVALID',
      'scanned_id', v_bearing_id,
      'error_code', 'INVALID_FORMAT',
      'message', 'Invalid Bearing Code'
    );
  end if;

  -- 4. Authoritative DB Lookup with row lock for exact, concurrency-safe scan count
  select 
    q.id,
    q.bearing_id,
    q.batch_id,
    q.model_number,
    q.payload_value,
    q.assigned_warranty_plan_id,
    q.warranty_plan_id,
    q.current_lifecycle_state,
    q.first_in_timestamp,
    q.warranty_expiry_timestamp,
    q.is_flagged,
    q.flag_reason,
    q.scan_count,
    q.first_scanned_at,
    q.created_at
  into v_qr
  from public.qr_codes q
  where q.bearing_id = v_bearing_id 
     or q.payload_value = v_trimmed 
     or q.payload_value = v_bearing_id
  for update;

  if not found then
    -- Record invalid scan telemetry
    insert into public.scan_records (
      scanned_payload,
      scanned_by,
      is_valid,
      device_info,
      ip_address,
      scan_timestamp
    ) values (
      v_trimmed,
      v_user_id,
      false,
      p_device_info,
      p_ip_address,
      v_now
    );

    return jsonb_build_object(
      'is_authentic', false,
      'status', 'INVALID',
      'scanned_id', v_bearing_id,
      'error_code', 'NOT_REGISTERED',
      'message', 'Bearing Authenticity Could Not Be Verified'
    );
  end if;

  -- Check if this device has already scanned this bearing
  if p_device_info is not null and p_device_info <> '' then
    select exists (
      select 1 
      from public.scan_records s 
      where s.qr_code_id = v_qr.id 
        and s.is_valid = true 
        and s.device_info = p_device_info
    ) into v_device_already_scanned;
  end if;

  -- 5. Calculate scan count
  if v_device_already_scanned then
    -- Same device scanning again: retain count, do NOT increment
    v_total_scans := greatest(coalesce(v_qr.scan_count, 1), 1);
    v_prev_scans := v_total_scans - 1;
  else
    -- New device scanning for first time: increment scan_count
    v_prev_scans := coalesce(v_qr.scan_count, 0);
    v_total_scans := v_prev_scans + 1;

    -- 6. Atomically increment qr_codes scan_count and record scan timestamps
    update public.qr_codes
    set scan_count = v_total_scans,
        first_scanned_at = coalesce(v_qr.first_scanned_at, v_now),
        last_scanned_at = v_now,
        updated_at = v_now
    where id = v_qr.id;
  end if;

  -- 7. Insert authoritative record into scan_records
  insert into public.scan_records (
    qr_code_id,
    scanned_payload,
    scanned_by,
    is_valid,
    device_info,
    ip_address,
    scan_timestamp
  ) values (
    v_qr.id,
    v_trimmed,
    v_user_id,
    true,
    p_device_info,
    p_ip_address,
    v_now
  );

  -- 8. Fetch Batch and Warranty Plan details
  select * into v_batch from public.qr_batches where id = v_qr.batch_id;
  select * into v_plan from public.warranty_plans where id = coalesce(v_qr.assigned_warranty_plan_id, v_qr.warranty_plan_id);

  -- 9. Return complete authoritative response
  return jsonb_build_object(
    'is_authentic', true,
    'status', 'AUTHENTIC',
    'bearing_id', v_qr.bearing_id,
    'model_number', v_qr.model_number,
    'batch_code', coalesce(v_batch.batch_code, 'N/A'),
    'plant_location', coalesce(v_batch.plant_location, 'Pivot Bearings India — Chakan Plant'),
    'warranty_plan_title', coalesce(v_plan.title, 'Standard Factory Warranty'),
    'warranty_duration_months', coalesce(v_plan.duration_months, 6),
    'current_lifecycle_state', v_qr.current_lifecycle_state,
    'previous_scan_count', v_prev_scans,
    'total_scan_count', v_total_scans,
    'first_scanned_at', coalesce(v_qr.first_scanned_at, v_now),
    'last_scanned_at', v_now,
    'is_flagged', v_qr.is_flagged,
    'flag_reason', v_qr.flag_reason
  );
end;
$$ language plpgsql security definer;

-- 4. RLS Grants for Execution
grant execute on function public.authenticate_bearing_qr(text, text, inet) to authenticated, anon;
grant select on public.scan_records to authenticated;
grant insert on public.scan_records to authenticated, anon;
