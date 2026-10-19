-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261010000006_authoritative_lifecycle_engine.sql
-- Authoritative Server-Side Bearing Lifecycle State Machine & Warranty Engine
-- ==============================================================================

-- 1. Ensure column was_warranty_active_at_out exists on installation cycles
alter table public.bearing_installation_cycles 
  add column if not exists was_warranty_active_at_out boolean;

-- ==============================================================================
-- 2. Enhanced Authoritative confirm_bearing_in
-- ==============================================================================
create or replace function public.confirm_bearing_in(
  p_bearing_id text,
  p_verification_image_id uuid default null,
  p_notes text default null
)
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_qr record;
  v_plan record;
  v_now timestamptz := clock_timestamp(); -- Authoritative real server clock
  v_new_expiry timestamptz;
  v_cycle_count integer;
  v_is_first_activation boolean := false;
  v_clean_id text := upper(trim(coalesce(p_bearing_id, '')));
begin
  -- 1. Authentication Check
  if v_user_id is null then
    raise exception 'Authentication required to confirm bearing installation.'
      using errcode = '42501';
  end if;

  if v_clean_id = '' then
    raise exception 'Bearing ID is required.' using errcode = '22023';
  end if;

  -- 2. Concurrency Lock: Lock QR Record
  select * into v_qr
  from public.qr_codes
  where bearing_id = v_clean_id
  for update;

  if not found then
    raise exception 'Bearing ID % not found in registry.', v_clean_id
      using errcode = 'P0002';
  end if;

  -- 3. Security / Tamper Lock Check
  if v_qr.is_flagged then
    raise exception 'Bearing % is blocked/locked: %', v_clean_id, coalesce(v_qr.flag_reason, 'Flagged by Quality Directorate.')
      using errcode = '55000';
  end if;

  -- 4. State Validation: Duplicate IN Guard
  if v_qr.current_lifecycle_state = 'CURRENTLY_IN' then
    raise exception 'Bearing % is already marked IN and currently operating.', v_clean_id
      using errcode = '55001';
  end if;

  -- 5. Fetch Warranty Plan
  select * into v_plan
  from public.warranty_plans
  where id = v_qr.assigned_warranty_plan_id;

  if not found then
    raise exception 'Assigned warranty plan % not found for bearing %.', v_qr.assigned_warranty_plan_id, v_clean_id;
  end if;

  -- 6. Warranty Anchoring Rule:
  -- Warranty starts strictly on the FIRST confirmed valid IN.
  -- Calendar-month arithmetic correctly handles leap years and month ends.
  -- Subsequent re-installations NEVER restart, overwrite, or extend the original anchor.
  if v_qr.first_in_timestamp is null then
    v_is_first_activation := true;
    v_new_expiry := v_now + (v_plan.duration_months || ' months')::interval;

    update public.qr_codes
    set
      current_lifecycle_state = 'CURRENTLY_IN',
      first_in_timestamp = v_now,
      warranty_expiry_timestamp = v_new_expiry,
      assigned_customer_id = coalesce(assigned_customer_id, v_user_id),
      updated_at = v_now
    where id = v_qr.id;
  else
    -- Reinstallation cycle: Retain original activation & expiration anchor forever
    v_is_first_activation := false;
    v_new_expiry := v_qr.warranty_expiry_timestamp;

    update public.qr_codes
    set
      current_lifecycle_state = 'CURRENTLY_IN',
      updated_at = v_now
    where id = v_qr.id;
  end if;

  -- 7. Calculate next cycle number without overwriting history
  select coalesce(max(cycle_number), 0) + 1 into v_cycle_count
  from public.bearing_installation_cycles
  where qr_code_id = v_qr.id;

  -- 8. Create new installation cycle record
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

  -- 9. Record immutable audit trail event
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
      'is_first_activation', v_is_first_activation,
      'warranty_expiry', v_new_expiry,
      'notes', p_notes
    )
  );

  return jsonb_build_object(
    'success', true,
    'action', 'MARKED_IN',
    'bearing_id', v_clean_id,
    'lifecycle_state', 'CURRENTLY_IN',
    'cycle_number', v_cycle_count,
    'in_timestamp', v_now,
    'first_in_timestamp', coalesce(v_qr.first_in_timestamp, v_now),
    'warranty_expiry_timestamp', v_new_expiry,
    'is_first_activation', v_is_first_activation,
    'message', case 
      when v_is_first_activation then 'First installation confirmed. Warranty activated successfully.'
      else 'Re-installation confirmed. Active cycle resumed.'
    end
  );
end;
$$ language plpgsql security definer;

-- ==============================================================================
-- 3. Enhanced Authoritative confirm_bearing_out
-- ==============================================================================
create or replace function public.confirm_bearing_out(
  p_bearing_id text,
  p_verification_image_id uuid default null,
  p_notes text default null
)
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_qr record;
  v_cycle record;
  v_now timestamptz := clock_timestamp(); -- Authoritative real server clock
  v_duration_interval interval;
  v_duration_seconds bigint;
  v_was_warranty_active boolean;
  v_clean_id text := upper(trim(coalesce(p_bearing_id, '')));
  v_formatted_duration text;
  v_days integer;
  v_hours integer;
  v_mins integer;
begin
  -- 1. Authentication Check
  if v_user_id is null then
    raise exception 'Authentication required to confirm bearing removal.'
      using errcode = '42501';
  end if;

  if v_clean_id = '' then
    raise exception 'Bearing ID is required.' using errcode = '22023';
  end if;

  -- 2. Concurrency Lock: Lock QR Record
  select * into v_qr
  from public.qr_codes
  where bearing_id = v_clean_id
  for update;

  if not found then
    raise exception 'Bearing ID % not found in registry.', v_clean_id
      using errcode = 'P0002';
  end if;

  -- 3. Security / Tamper Lock Check
  if v_qr.is_flagged then
    raise exception 'Bearing % is blocked/locked: %', v_clean_id, coalesce(v_qr.flag_reason, 'Flagged by Quality Directorate.')
      using errcode = '55000';
  end if;

  -- 4. State Validation:
  -- Guard 4a: OUT before first IN
  if v_qr.current_lifecycle_state = 'NOT_ACTIVATED' or v_qr.first_in_timestamp is null then
    raise exception 'Bearing % has never been installed (NOT_ACTIVATED). Cannot record OUT event before first IN.', v_clean_id
      using errcode = '55002';
  end if;

  -- Guard 4b: Duplicate OUT (already removed)
  if v_qr.current_lifecycle_state != 'CURRENTLY_IN' then
    raise exception 'Bearing % is not currently marked IN. Cannot record OUT event.', v_clean_id
      using errcode = '55003';
  end if;

  -- 5. Fetch and Lock the latest open installation cycle
  select * into v_cycle
  from public.bearing_installation_cycles
  where qr_code_id = v_qr.id
    and is_cycle_closed = false
  order by cycle_number desc
  limit 1
  for update;

  if not found then
    raise exception 'No active open installation cycle found for bearing %.', v_clean_id
      using errcode = '55004';
  end if;

  -- 6. Calculate Operating Cycle Duration & Warranty Status at OUT
  -- Invariant: OUT remains fully possible after warranty expiry
  v_duration_interval := v_now - v_cycle.in_timestamp;
  v_duration_seconds := extract(epoch from v_duration_interval)::bigint;

  v_was_warranty_active := (
    v_qr.warranty_expiry_timestamp is not null 
    and v_now <= v_qr.warranty_expiry_timestamp
  );

  v_days := extract(day from v_duration_interval)::int;
  v_hours := extract(hour from v_duration_interval)::int;
  v_mins := extract(minute from v_duration_interval)::int;
  v_formatted_duration := v_days || 'd ' || lpad(v_hours::text, 2, '0') || 'h ' || lpad(v_mins::text, 2, '0') || 'm';

  -- 7. Close Active Installation Cycle
  update public.bearing_installation_cycles
  set
    out_timestamp = v_now,
    out_confirmed_by = v_user_id,
    out_verification_image_id = p_verification_image_id,
    operating_duration_interval = v_duration_interval,
    operating_duration_seconds = v_duration_seconds,
    was_warranty_active_at_out = v_was_warranty_active,
    is_cycle_closed = true,
    updated_at = v_now
  where id = v_cycle.id;

  -- 8. Set Current State to CURRENTLY_OUT
  update public.qr_codes
  set
    current_lifecycle_state = 'CURRENTLY_OUT',
    updated_at = v_now
  where id = v_qr.id;

  -- 9. Record Immutable Audit Trail Event
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
      'was_warranty_active', v_was_warranty_active,
      'notes', p_notes
    )
  );

  return jsonb_build_object(
    'success', true,
    'action', 'MARKED_OUT',
    'bearing_id', v_clean_id,
    'lifecycle_state', 'CURRENTLY_OUT',
    'cycle_number', v_cycle.cycle_number,
    'in_timestamp', v_cycle.in_timestamp,
    'out_timestamp', v_now,
    'operating_duration_seconds', v_duration_seconds,
    'operating_duration_formatted', v_formatted_duration,
    'was_warranty_active_at_out', v_was_warranty_active,
    'message', case 
      when v_was_warranty_active then 'Bearing removal recorded. Operating cycle completed within active warranty.'
      else 'Bearing removal recorded. Operating cycle completed after warranty expiry.'
    end
  );
end;
$$ language plpgsql security definer;
