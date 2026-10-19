-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261011000009_cryptographic_qr_keys.sql
-- Cryptographic QR Encryption Keys & Tamper-Evident Token Generation
-- ==============================================================================

-- 1. Update Function: generate_qr_batch with Cryptographic Key Generation
create or replace function public.generate_qr_batch(
  p_batch_code text,
  p_plant_location text,
  p_quantity integer,
  p_model_number text default 'PBI-6204-ZZ',
  p_default_warranty_plan_id uuid default null
)
returns jsonb as $$
declare
  v_admin_id uuid := auth.uid();
  v_batch_id uuid;
  v_plan_id uuid := p_default_warranty_plan_id;
  v_generated_count integer := 0;
  v_max_attempts integer := p_quantity * 5;
  v_attempts integer := 0;
  v_model_token text;
  v_epoch_token text;
  v_nonce_token text;
  v_checksum text;
  v_base_payload text;
  v_bearing_id text;
  v_payload text;
  v_hash text;
  v_inserted_ids text[] := array[]::text[];
  v_salt text := 'PIVOT_BEARINGS_INDIA_INDUSTRIAL_AUTHENTICITY_SALT_2026';
begin
  -- 1. Enforce Admin Privilege
  if not public.is_admin(v_admin_id) then
    raise exception 'Insufficient privilege: ADMIN role required to generate QR batches.'
      using errcode = '42501';
  end if;

  -- 2. Validate Quantity
  if p_quantity is null or p_quantity < 1 or p_quantity > 5000 then
    raise exception 'Invalid quantity: % (Must be between 1 and 5000).', p_quantity
      using errcode = '22023';
  end if;

  -- 3. Resolve Default Warranty Plan if null
  if v_plan_id is null then
    select id into v_plan_id
    from public.warranty_plans
    where is_active = true
    order by duration_months asc
    limit 1;
    
    if v_plan_id is null then
      raise exception 'No active warranty plan available.';
    end if;
  else
    if not exists (select 1 from public.warranty_plans where id = v_plan_id) then
      raise exception 'Specified warranty plan % not found.', v_plan_id;
    end if;
  end if;

  -- 4. Create or Resolve QR Batch Record
  select id into v_batch_id
  from public.qr_batches
  where batch_code = p_batch_code;

  if v_batch_id is null then
    insert into public.qr_batches (
      batch_code,
      plant_location,
      lot_date,
      total_quantity,
      default_warranty_plan_id,
      created_by,
      status
    ) values (
      p_batch_code,
      p_plant_location,
      current_date,
      p_quantity,
      v_plan_id,
      v_admin_id,
      'ACTIVE'
    )
    returning id into v_batch_id;
  else
    update public.qr_batches
    set total_quantity = total_quantity + p_quantity,
        updated_at = now()
    where id = v_batch_id;
  end if;

  -- Extract 4-character functional model token
  -- Examples: 'PBI-6204-ZZ' -> '6204', 'PBI-22216-E' -> '2216'
  v_model_token := substring(regexp_replace(replace(p_model_number, 'PBI-', ''), '[^A-Za-z0-9]', '', 'g') from 1 for 4);
  if length(v_model_token) < 4 then
    v_model_token := rpad(v_model_token, 4, '0');
  end if;
  v_model_token := upper(v_model_token);

  -- Epoch token: Year offset + Month + Day (4 hex chars)
  v_epoch_token := upper(to_hex(((extract(year from current_date)::int - 2020) * 256) + (extract(month from current_date)::int * 16) + (extract(day from current_date)::int % 16)));
  if length(v_epoch_token) < 4 then
    v_epoch_token := lpad(v_epoch_token, 4, '0');
  end if;

  -- 5. Cryptographically Generate Unique Identifiers (PBI-SEC-[MODEL]-[EPOCH]-[NONCE]-[CHECKSUM])
  while v_generated_count < p_quantity and v_attempts < v_max_attempts loop
    v_attempts := v_attempts + 1;
    
    -- 4 hex chars CSPRNG entropy
    v_nonce_token := upper(encode(gen_random_bytes(2), 'hex'));
    
    v_base_payload := v_model_token || '-' || v_epoch_token || '-' || v_nonce_token;
    -- 4 hex chars SHA-256 HMAC checksum
    v_checksum := upper(substring(encode(digest(v_salt || ':' || v_base_payload, 'sha256'), 'hex') from 1 for 4));
    
    v_bearing_id := 'PBI-SEC-' || v_base_payload || '-' || v_checksum;

    -- Standard payload URL (identifies registered bearing without sensitive or editable dates)
    v_payload := 'https://verify.pivotbearings.com/pbi/' || v_bearing_id
              || '?batch=' || p_batch_code
              || '&m=' || p_model_number;

    -- Cryptographic SHA-256 hash for database index
    v_hash := 'SHA-256: ' || upper(encode(digest(v_payload, 'sha256'), 'hex'));

    -- Attempt atomic insertion; on conflict ignore and retry next random iteration
    begin
      insert into public.qr_codes (
        bearing_id,
        batch_id,
        model_number,
        payload_value,
        payload_hash,
        warranty_plan_id,
        current_lifecycle_state,
        is_flagged
      ) values (
        v_bearing_id,
        v_batch_id,
        p_model_number,
        v_bearing_id,
        v_hash,
        v_plan_id,
        'NOT_ACTIVATED',
        false
      );

      v_generated_count := v_generated_count + 1;
      v_inserted_ids := array_append(v_inserted_ids, v_bearing_id);
    exception when unique_violation then
      -- Collision caught; loop proceeds to generate another unique token
      null;
    end;
  end loop;

  -- 6. Audit Trail Logging
  insert into public.audit_logs (
    admin_id,
    action,
    target_entity,
    target_id,
    details
  ) values (
    v_admin_id,
    'GENERATE_CRYPTOGRAPHIC_QR_BATCH',
    'qr_batches',
    v_batch_id,
    jsonb_build_object(
      'batch_code', p_batch_code,
      'quantity_requested', p_quantity,
      'quantity_generated', v_generated_count,
      'key_format', 'PBI-SEC-V2',
      'plant_location', p_plant_location,
      'model_number', p_model_number
    )
  );

  -- 7. Return Result JSON
  return jsonb_build_object(
    'batch_id', v_batch_id,
    'batch_code', p_batch_code,
    'quantity_generated', v_generated_count,
    'bearing_ids', to_jsonb(v_inserted_ids)
  );
end;
$$ language plpgsql security definer;

-- 2. Update Function: verify_bearing_qr to Accept Both Cryptographic Keys and Legacy Serials
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
  v_can_mark_in boolean;
  v_can_mark_out boolean;
begin
  -- 1. Extract Bearing ID from URL or Raw Serial
  if v_trimmed ilike 'https://verify.pivotbearings.com/pbi/%' then
    v_bearing_id := split_part(split_part(v_trimmed, '/pbi/', 2), '?', 1);
  else
    v_bearing_id := v_trimmed;
  end if;

  v_bearing_id := upper(trim(v_bearing_id));

  -- 2. Format validation check: Cryptographic Key (PBI-SEC-) or Legacy Format (PB-0000-XX)
  if not (v_bearing_id ~* '^(PB-[0-9]{4}-[A-Z0-9]{2}|PBI-SEC-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}|(PBI|PB)(-[A-Z0-9]{3,8}){2,5})$') then
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
      now()
    );

    return jsonb_build_object(
      'status', 'INVALID',
      'scanned_id', v_bearing_id,
      'error_code', 'INVALID_FORMAT',
      'message', 'Malformed or unverified cryptographic identifier.'
    );
  end if;

  -- 3. Lookup QR Code with Joined Batch and Warranty Plan Information
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

  -- 4. Not Found In Database -> Log as Unregistered Scan
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

  -- 5. Flagged Bearing Check
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

  -- 6. State Evaluation & State Transition Permissions
  if v_qr.current_lifecycle_state = 'NOT_ACTIVATED' then
    v_is_expired := false;
    v_can_mark_in := true;
    v_can_mark_out := false;

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

  -- Active / Expired Evaluation
  v_is_expired := (v_qr.warranty_expiry_timestamp is not null and v_qr.warranty_expiry_timestamp < now());
  v_can_mark_in := (v_qr.current_lifecycle_state = 'CURRENTLY_OUT');
  v_can_mark_out := (v_qr.current_lifecycle_state = 'CURRENTLY_IN');

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
    'current_lifecycle_state', v_qr.current_lifecycle_state,
    'first_in_timestamp', v_qr.first_in_timestamp,
    'warranty_expiry_timestamp', v_qr.warranty_expiry_timestamp,
    'is_expired', v_is_expired,
    'can_mark_in', v_can_mark_in,
    'can_mark_out', v_can_mark_out,
    'message', case when v_is_expired then 'Bearing warranty coverage has expired.' else 'Bearing warranty active.' end
  );
end;
$$ language plpgsql security definer;
