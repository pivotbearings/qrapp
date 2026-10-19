-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261010000005_verify_bearing_qr_rpc.sql
-- Authoritative Server-Side QR Verification Function with Telemetry Logging
-- ==============================================================================

create or replace function public.verify_bearing_qr(
  p_scanned_payload text,
  p_ip_address text default null,
  p_user_agent text default null,
  p_device_info text default null
)
returns jsonb as $$
declare
  v_trimmed text;
  v_bearing_id text;
  v_qr record;
  v_batch record;
  v_plan record;
  v_user_id uuid := auth.uid();
  v_status text;
  v_is_expired boolean := false;
  v_now timestamptz := now();
  v_can_mark_in boolean := false;
  v_can_mark_out boolean := false;
begin
  v_trimmed := trim(coalesce(p_scanned_payload, ''));

  if v_trimmed = '' then
    return jsonb_build_object(
      'verification_status', 'QR_UNKNOWN_OR_INVALID',
      'message', 'Empty payload scanned.'
    );
  end if;

  -- 1. Extract Bearing ID from URL or Raw Serial
  if v_trimmed ilike 'https://verify.pivotbearings.com/pbi/%' then
    v_bearing_id := split_part(split_part(v_trimmed, '/pbi/', 2), '?', 1);
  else
    v_bearing_id := v_trimmed;
  end if;

  v_bearing_id := upper(trim(v_bearing_id));

  -- 2. Format validation check against standard regex ^PB-[0-9]{4}-[A-Z0-9]{2}$
  if not (v_bearing_id ~* '^PB-[0-9]{4}-[A-Z0-9]{2}$') then
    -- Telemetry logging of invalid scan
    insert into public.scan_records (
      scanned_payload,
      scanned_by,
      is_valid,
      ip_address,
      user_agent,
      device_info,
      scan_timestamp
    ) values (
      v_trimmed,
      v_user_id,
      false,
      p_ip_address,
      p_user_agent,
      p_device_info,
      v_now
    );

    return jsonb_build_object(
      'verification_status', 'QR_UNKNOWN_OR_INVALID',
      'scanned_id', v_bearing_id,
      'message', 'Malformed identifier format. Expected format: PB-XXXX-YY.'
    );
  end if;

  -- 3. Authoritative DB Lookup
  select * into v_qr
  from public.qr_codes
  where bearing_id = v_bearing_id;

  if not found then
    -- Telemetry logging
    insert into public.scan_records (
      scanned_payload,
      scanned_by,
      is_valid,
      ip_address,
      user_agent,
      device_info,
      scan_timestamp
    ) values (
      v_trimmed,
      v_user_id,
      false,
      p_ip_address,
      p_user_agent,
      p_device_info,
      v_now
    );

    return jsonb_build_object(
      'verification_status', 'QR_UNKNOWN_OR_INVALID',
      'scanned_id', v_bearing_id,
      'message', 'Cryptographic identifier not found in authoritative Pivot Bearings India registry.'
    );
  end if;

  -- Telemetry logging for valid lookup
  insert into public.scan_records (
    qr_code_id,
    scanned_payload,
    scanned_by,
    is_valid,
    ip_address,
    user_agent,
    device_info,
    scan_timestamp
  ) values (
    v_qr.id,
    v_trimmed,
    v_user_id,
    true,
    p_ip_address,
    p_user_agent,
    p_device_info,
    v_now
  );

  -- Fetch Batch and Warranty Plan details
  select * into v_batch from public.qr_batches where id = v_qr.batch_id;
  select * into v_plan from public.warranty_plans where id = v_qr.assigned_warranty_plan_id;

  -- 4. Check Blocked / Flagged State
  if v_qr.is_flagged then
    return jsonb_build_object(
      'verification_status', 'QR_BLOCKED',
      'bearing_id', v_qr.bearing_id,
      'flag_reason', coalesce(v_qr.flag_reason, 'Flagged by Quality Directorate'),
      'model_number', v_qr.model_number,
      'batch_code', v_batch.batch_code,
      'plant_location', v_batch.plant_location,
      'current_lifecycle_state', v_qr.current_lifecycle_state,
      'can_mark_in', false,
      'can_mark_out', false
    );
  end if;

  -- 5. Determine Authoritative State
  if v_qr.current_lifecycle_state = 'NOT_ACTIVATED' then
    v_status := 'VALID_NOT_ACTIVATED';
    v_can_mark_in := true;
    v_can_mark_out := false;
  else
    -- Activated bearing: check whether warranty has expired
    if v_qr.warranty_expiry_timestamp is not null and v_qr.warranty_expiry_timestamp < v_now then
      v_status := 'WARRANTY_EXPIRED';
      v_is_expired := true;
    else
      v_status := 'VALID_WARRANTY_ACTIVE';
      v_is_expired := false;
    end if;

    if v_qr.current_lifecycle_state = 'CURRENTLY_IN' then
      v_can_mark_in := false;
      v_can_mark_out := true;
    else
      -- CURRENTLY_OUT: can be re-installed (marked IN)
      v_can_mark_in := true;
      v_can_mark_out := false;
    end if;
  end if;

  -- NOTE: Scanning alone strictly DOES NOT mutate bearing state or warranty duration
  return jsonb_build_object(
    'verification_status', v_status,
    'bearing_id', v_qr.bearing_id,
    'batch_code', v_batch.batch_code,
    'plant_location', v_batch.plant_location,
    'model_number', v_qr.model_number,
    'warranty_plan_title', v_plan.title,
    'warranty_duration_months', v_plan.duration_months,
    'current_lifecycle_state', v_qr.current_lifecycle_state,
    'first_in_timestamp', v_qr.first_in_timestamp,
    'warranty_expiry_timestamp', v_qr.warranty_expiry_timestamp,
    'is_expired', v_is_expired,
    'can_mark_in', v_can_mark_in,
    'can_mark_out', v_can_mark_out,
    'payload_hash', v_qr.payload_hash
  );
end;
$$ language plpgsql security definer;
