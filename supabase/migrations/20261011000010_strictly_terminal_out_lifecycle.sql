-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261011000010_strictly_terminal_out_lifecycle.sql
-- Authoritative Terminal Lifecycle: Strict No-Reinstallation Policy
-- Once a bearing is scanned OUT and image proof is submitted, the lifecycle is ended.
-- ==============================================================================

-- 1. Update confirm_bearing_in to strictly prohibit reinstallation
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
  v_now timestamptz := clock_timestamp(); -- Authoritative server clock
  v_new_expiry timestamptz;
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

  -- 4. Terminal Lifecycle Guard: STRICT NO REINSTALLATION
  -- Once marked OUT, the bearing is permanently decommissioned.
  if v_qr.current_lifecycle_state = 'CURRENTLY_OUT' then
    raise exception 'Bearing % has already been marked OUT and is permanently decommissioned. Re-installation is strictly prohibited.', v_clean_id
      using errcode = '55005';
  end if;

  -- 5. Duplicate IN Guard
  if v_qr.current_lifecycle_state = 'CURRENTLY_IN' then
    raise exception 'Bearing % is already marked IN and currently operating.', v_clean_id
      using errcode = '55001';
  end if;

  -- 6. Fetch Warranty Plan
  select * into v_plan
  from public.warranty_plans
  where id = v_qr.assigned_warranty_plan_id;

  if not found then
    raise exception 'Assigned warranty plan % not found for bearing %.', v_qr.assigned_warranty_plan_id, v_clean_id;
  end if;

  -- 7. First IN Warranty Activation
  v_new_expiry := v_now + (v_plan.duration_months || ' months')::interval;

  update public.qr_codes
  set
    current_lifecycle_state = 'CURRENTLY_IN',
    first_in_timestamp = v_now,
    warranty_expiry_timestamp = v_new_expiry,
    assigned_customer_id = coalesce(assigned_customer_id, v_user_id),
    updated_at = v_now
  where id = v_qr.id;

  -- 8. Create new single installation cycle record
  insert into public.bearing_installation_cycles (
    qr_code_id,
    cycle_number,
    in_timestamp,
    in_confirmed_by,
    in_verification_image_id
  ) values (
    v_qr.id,
    1,
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
      'first_activation', true,
      'warranty_expiry', v_new_expiry,
      'notes', p_notes
    )
  );

  return jsonb_build_object(
    'success', true,
    'action', 'MARKED_IN',
    'bearing_id', v_clean_id,
    'lifecycle_state', 'CURRENTLY_IN',
    'first_in_timestamp', v_now,
    'warranty_expiry_timestamp', v_new_expiry,
    'warranty_duration_months', v_plan.duration_months,
    'message', 'Bearing successfully installed. Authoritative warranty clock activated.'
  );
end;
$$ language plpgsql security definer;

-- 2. Update verify_bearing_qr to enforce terminal DECOMMISSIONED state for CURRENTLY_OUT
create or replace function public.verify_bearing_qr(
  p_scanned_payload text,
  p_ip_address inet default null,
  p_user_agent text default null,
  p_device_info text default null
)
returns jsonb as $$
declare
  v_trimmed text := trim(coalesce(p_scanned_payload, ''));
  v_bearing_id text;
  v_user_id uuid := auth.uid();
  v_qr record;
  v_is_expired boolean;
begin
  -- 1. Extract Bearing ID from URL or Raw Serial
  if v_trimmed ilike 'https://verify.pivotbearings.com/pbi/%' then
    v_bearing_id := split_part(split_part(v_trimmed, '/pbi/', 2), '?', 1);
  else
    v_bearing_id := v_trimmed;
  end if;

  v_bearing_id := upper(trim(v_bearing_id));

  -- 2. Format validation check
  if not (v_bearing_id ~* '^(PB-[0-9]{4}-[A-Z0-9]{2}|PBI-SEC-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}|(PBI|PB)(-[A-Z0-9]{3,8}){2,5})$') then
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
      now()
    );

    return jsonb_build_object(
      'status', 'INVALID',
      'scanned_id', v_bearing_id,
      'error_code', 'INVALID_FORMAT',
      'message', 'Malformed or unverified cryptographic identifier.'
    );
  end if;

  -- 3. Lookup QR Code
  select 
    q.id,
    q.bearing_id,
    q.model_number,
    q.current_lifecycle_state,
    q.first_in_timestamp,
    q.warranty_expiry_timestamp,
    q.is_flagged,
    q.flag_reason,
    b.batch_code,
    b.plant_location,
    p.title as warranty_title,
    p.duration_months
  into v_qr
  from public.qr_codes q
  left join public.qr_batches b on q.batch_id = b.id
  left join public.warranty_plans p on q.warranty_plan_id = p.id
  where q.bearing_id = v_bearing_id;

  if not found then
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
      now()
    );

    return jsonb_build_object(
      'status', 'INVALID',
      'scanned_id', v_bearing_id,
      'error_code', 'NOT_FOUND',
      'message', 'Cryptographic identifier not registered with Pivot Bearings India.'
    );
  end if;

  -- 4. Flagged Bearing Check
  if v_qr.is_flagged then
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
      now()
    );

    return jsonb_build_object(
      'status', 'FLAGGED',
      'bearing_id', v_qr.bearing_id,
      'batch_code', v_qr.batch_code,
      'plant_location', v_qr.plant_location,
      'model_number', v_qr.model_number,
      'flag_reason', v_qr.flag_reason,
      'current_lifecycle_state', v_qr.current_lifecycle_state,
      'can_mark_in', false,
      'can_mark_out', false,
      'message', 'Caution: Bearing has been flagged for investigation by Quality Control.'
    );
  end if;

  -- 5. Terminal State: CURRENTLY_OUT (Permanently Decommissioned)
  if v_qr.current_lifecycle_state = 'CURRENTLY_OUT' then
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
      now()
    );

    return jsonb_build_object(
      'status', 'DECOMMISSIONED_OUT',
      'bearing_id', v_qr.bearing_id,
      'batch_code', v_qr.batch_code,
      'plant_location', v_qr.plant_location,
      'model_number', v_qr.model_number,
      'warranty_title', v_qr.warranty_title,
      'duration_months', v_qr.duration_months,
      'current_lifecycle_state', 'CURRENTLY_OUT',
      'first_in_timestamp', v_qr.first_in_timestamp,
      'warranty_expiry_timestamp', v_qr.warranty_expiry_timestamp,
      'is_expired', (v_qr.warranty_expiry_timestamp is not null and v_qr.warranty_expiry_timestamp < now()),
      'can_mark_in', false,
      'can_mark_out', false,
      'message', 'This bearing was marked OUT and permanently decommissioned. Re-installation is strictly prohibited.'
    );
  end if;

  -- 6. Ready for Activation: NOT_ACTIVATED
  if v_qr.current_lifecycle_state = 'NOT_ACTIVATED' then
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
      now()
    );

    return jsonb_build_object(
      'status', 'VALID_NOT_ACTIVATED',
      'bearing_id', v_qr.bearing_id,
      'batch_code', v_qr.batch_code,
      'plant_location', v_qr.plant_location,
      'model_number', v_qr.model_number,
      'warranty_title', coalesce(v_qr.warranty_title, 'Standard Factory Warranty'),
      'duration_months', coalesce(v_qr.duration_months, 6),
      'current_lifecycle_state', 'NOT_ACTIVATED',
      'can_mark_in', true,
      'can_mark_out', false,
      'message', 'Authentic Pivot Bearing. Ready for installation & warranty activation.'
    );
  end if;

  -- 7. Active Operating Bearing: CURRENTLY_IN
  v_is_expired := (v_qr.warranty_expiry_timestamp is not null and v_qr.warranty_expiry_timestamp < now());

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
    now()
  );

  return jsonb_build_object(
    'status', case when v_is_expired then 'WARRANTY_EXPIRED' else 'VALID_WARRANTY_ACTIVE' end,
    'bearing_id', v_qr.bearing_id,
    'batch_code', v_qr.batch_code,
    'plant_location', v_qr.plant_location,
    'model_number', v_qr.model_number,
    'warranty_title', v_qr.warranty_title,
    'duration_months', v_qr.duration_months,
    'current_lifecycle_state', 'CURRENTLY_IN',
    'first_in_timestamp', v_qr.first_in_timestamp,
    'warranty_expiry_timestamp', v_qr.warranty_expiry_timestamp,
    'is_expired', v_is_expired,
    'can_mark_in', false,
    'can_mark_out', true,
    'message', case when v_is_expired then 'Bearing currently operating. Warranty coverage has expired.' else 'Bearing currently operating with active warranty coverage.' end
  );
end;
$$ language plpgsql security definer;
