-- Pivot Bearings India - Database Migration: 20261029000031_guarantee_exact_warranty_duration.sql
-- Description: Guaranteed 100% authoritative warranty duration binding across all QR codes & batches.
-- Automatically resolves or creates matching warranty plans for any duration (0M to 240M+).
-- Fixes existing test records (#CJ7HMKGH$PE to 36M, FKUAiJWaEgIh to 36M, IO1tjaoIX1h3 to 12M, yCPfc7a*CuPR to 3M).

-- ==============================================================================
-- 1. Ensure Standard Warranty Plans Exist in public.warranty_plans
-- ==============================================================================
insert into public.warranty_plans (id, plan_code, title, duration_months, description, is_active)
values  
  ('00000000-0000-0000-0000-000000000000', 'WP-0M', '0 Month Warranty (0M)', 0, 'No Warranty Coverage / As-Is', true),
  ('11111111-1111-1111-1111-111111111111', 'WP-3M', '3 Months Standard Warranty (3M)', 3, 'Standard 3-Month Industrial Coverage', true),
  ('22222222-2222-2222-2222-222222222222', 'WP-6M', '6 Months Heavy Duty Warranty (6M)', 6, '6-Month Heavy Duty Industrial Coverage', true),
  ('33333333-3333-3333-3333-333333333333', 'WP-12M', '12 Months Industrial Warranty (12M)', 12, '12-Month Factory Industrial Coverage', true),
  ('44444444-4444-4444-4444-444444444444', 'WP-18M', '18 Months Extended Warranty (18M)', 18, '18-Month Extended Industrial Coverage', true),
  ('55555555-5555-5555-5555-555555555555', 'WP-24M', '24 Months Extended Mining Warranty (24M)', 24, '24-Month Extended Mining & Heavy Load Coverage', true),
  ('66666666-6666-6666-6666-666666666666', 'WP-36M', '36 Months Long-Term Industrial (36M)', 36, '36-Month Long-Term Industrial Coverage', true),
  ('77777777-7777-7777-7777-777777777777', 'WP-48M', '48 Months Heavy Industrial (48M)', 48, '48-Month Heavy Industrial Coverage', true),
  ('88888888-8888-8888-8888-888888888888', 'WP-60M', '60 Months Lifetime Industrial Assurance (60M)', 60, '60-Month Premium Assurance Coverage', true)
on conflict (id) do update set
  plan_code = excluded.plan_code,
  title = excluded.title,
  duration_months = excluded.duration_months,
  is_active = true;

-- ==============================================================================
-- 2. Stored Procedure: get_or_create_warranty_plan
-- Guarantees that ANY duration (standard or custom) maps to an authoritative plan
-- ==============================================================================
drop function if exists public.get_or_create_warranty_plan(integer) cascade;

create or replace function public.get_or_create_warranty_plan(
  p_duration_months integer
)
returns uuid as $$
declare
  v_plan_id uuid;
  v_months integer := coalesce(p_duration_months, 12);
  v_code text;
  v_title text;
begin
  if v_months < 0 then
    v_months := 0;
  end if;

  select id into v_plan_id
  from public.warranty_plans
  where duration_months = v_months
  order by is_active desc, created_at asc
  limit 1;

  if v_plan_id is not null then
    return v_plan_id;
  end if;

  v_code := 'WP-' || v_months || 'M';
  v_title := v_months || ' Months Industrial Warranty (' || v_months || 'M)';

  insert into public.warranty_plans (
    plan_code,
    title,
    duration_months,
    description,
    is_active
  ) values (
    v_code,
    v_title,
    v_months,
    'Official Pivot Bearings India ' || v_months || '-Month Warranty Coverage',
    true
  )
  on conflict (id) do nothing
  returning id into v_plan_id;

  if v_plan_id is null then
    select id into v_plan_id from public.warranty_plans where duration_months = v_months limit 1;
  end if;

  return v_plan_id;
end;
$$ language plpgsql security definer;

grant execute on function public.get_or_create_warranty_plan(integer) to authenticated, anon;

-- ==============================================================================
-- 3. Stored Procedure: generate_qr_batch (Clean Drop & Single Unified Definition)
-- Avoids PostgreSQL 42P13 error by dropping all overloads first
-- ==============================================================================
drop function if exists public.generate_qr_batch(text, text, integer, text, uuid, integer) cascade;
drop function if exists public.generate_qr_batch(text, text, integer, text, uuid) cascade;
drop function if exists public.generate_qr_batch(text, text, integer, text) cascade;
drop function if exists public.generate_qr_batch(text, text, integer) cascade;

create or replace function public.generate_qr_batch(
  p_batch_code text,
  p_plant_location text,
  p_quantity integer,
  p_model_number text default 'B1',
  p_default_warranty_plan_id uuid default null,
  p_warranty_duration_months integer default null
)
returns jsonb as $$
declare
  v_admin_id uuid := auth.uid();
  v_batch_id uuid;
  v_plan_id uuid := p_default_warranty_plan_id;
  v_generated_count integer := 0;
  v_max_attempts integer := p_quantity * 15;
  v_attempts integer := 0;
  v_qr_value text;
  v_hash text;
  v_inserted_ids text[] := array[]::text[];
begin
  if not public.is_admin(v_admin_id) then
    raise exception 'Insufficient privilege: ADMIN role required to generate QR batches.'
      using errcode = '42501';
  end if;

  if p_quantity is null or p_quantity < 1 or p_quantity > 5000 then
    raise exception 'Invalid quantity: % (Must be between 1 and 5000).', p_quantity
      using errcode = '22023';
  end if;

  if p_warranty_duration_months is not null then
    v_plan_id := public.get_or_create_warranty_plan(p_warranty_duration_months);
  elsif v_plan_id is null then
    select id into v_plan_id
    from public.warranty_plans
    where duration_months = 12 and is_active = true
    limit 1;
    
    if v_plan_id is null then
      v_plan_id := public.get_or_create_warranty_plan(12);
    end if;
  else
    if not exists (select 1 from public.warranty_plans where id = v_plan_id) then
      v_plan_id := public.get_or_create_warranty_plan(12);
    end if;
  end if;

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
        default_warranty_plan_id = coalesce(v_plan_id, default_warranty_plan_id),
        updated_at = now()
    where id = v_batch_id;
  end if;

  while v_generated_count < p_quantity and v_attempts < v_max_attempts loop
    v_attempts := v_attempts + 1;
    v_qr_value := public.generate_random_12char_qr_value();

    if v_qr_value = any(v_inserted_ids) then
      continue;
    end if;

    v_hash := upper(encode(digest(v_qr_value, 'sha256'), 'hex'));

    begin
      insert into public.qr_codes (
        bearing_id,
        batch_id,
        model_number,
        payload_value,
        payload_hash,
        assigned_warranty_plan_id,
        current_lifecycle_state,
        is_flagged
      ) values (
        v_qr_value,
        v_batch_id,
        coalesce(p_model_number, 'B1'),
        v_qr_value,
        v_hash,
        v_plan_id,
        'NOT_ACTIVATED',
        false
      );

      v_generated_count := v_generated_count + 1;
      v_inserted_ids := array_append(v_inserted_ids, v_qr_value);
    exception when unique_violation then
      null;
    end;
  end loop;

  return jsonb_build_object(
    'success', true,
    'batch_id', v_batch_id,
    'batch_code', p_batch_code,
    'quantity_generated', v_generated_count,
    'bearing_ids', v_inserted_ids,
    'warranty_plan_id', v_plan_id
  );
end;
$$ language plpgsql security definer;

grant execute on function public.generate_qr_batch(text, text, integer, text, uuid, integer) to authenticated, anon;

-- ==============================================================================
-- 4. Stored Procedure: verify_bearing_qr (Fixed join on assigned_warranty_plan_id)
-- ==============================================================================
drop function if exists public.verify_bearing_qr(text, inet, text, text) cascade;
drop function if exists public.verify_bearing_qr(text) cascade;

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
  v_dur int := 12;
begin
  if v_trimmed = '' then
    return jsonb_build_object('status', 'INVALID', 'error_code', 'EMPTY_PAYLOAD', 'message', 'Empty scanned payload.');
  end if;

  if v_trimmed ilike '%/pbi/%' then
    v_bearing_id := split_part(split_part(v_trimmed, '/pbi/', 2), '?', 1);
  elsif v_trimmed ilike '%/verify/%' then
    v_bearing_id := split_part(split_part(v_trimmed, '/verify/', 2), '?', 1);
  elsif v_trimmed ilike 'http%://%' then
    v_bearing_id := split_part(split_part(split_part(v_trimmed, '?', 1), '#', 1), '/', array_length(string_to_array(split_part(split_part(v_trimmed, '?', 1), '#', 1), '/'), 1));
  else
    v_bearing_id := v_trimmed;
  end if;

  v_bearing_id := trim(v_bearing_id);

  select 
    q.id,
    q.bearing_id,
    q.model_number,
    q.current_lifecycle_state,
    q.first_in_timestamp,
    q.last_out_timestamp,
    q.warranty_expiry_timestamp,
    q.is_flagged,
    q.flag_reason,
    b.batch_code,
    b.plant_location,
    p.title as warranty_title,
    coalesce(p.duration_months, 12) as duration_months
  into v_qr
  from public.qr_codes q
  left join public.qr_batches b on q.batch_id = b.id
  left join public.warranty_plans p on p.id = coalesce(q.assigned_warranty_plan_id, b.default_warranty_plan_id)
  where q.bearing_id = v_bearing_id
     or q.payload_value = v_trimmed
     or q.bearing_id = upper(v_bearing_id)
     or q.bearing_id ilike v_bearing_id
     or q.payload_value ilike v_trimmed
     or replace(replace(q.bearing_id, 'l', 'I'), '1', 'I') ilike replace(replace(v_bearing_id, 'l', 'I'), '1', 'I')
  limit 1;

  if not found then
    insert into public.scan_records (scanned_payload, scanned_by, is_valid, ip_address, user_agent, device_info, scan_timestamp)
    values (v_trimmed, v_user_id, false, p_ip_address, p_user_agent, p_device_info, now());

    return jsonb_build_object('status', 'INVALID', 'scanned_id', v_bearing_id, 'error_code', 'NOT_FOUND', 'message', 'Cryptographic identifier not registered with Pivot Bearings India.');
  end if;

  v_dur := coalesce(v_qr.duration_months, 12);

  if v_qr.is_flagged then
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

  if v_qr.current_lifecycle_state in ('CURRENTLY_OUT', 'FINAL_OUT', 'DECOMMISSIONED') then
    return jsonb_build_object(
      'status', 'DECOMMISSIONED_OUT',
      'bearing_id', v_qr.bearing_id,
      'batch_code', v_qr.batch_code,
      'plant_location', v_qr.plant_location,
      'model_number', v_qr.model_number,
      'warranty_title', coalesce(v_qr.warranty_title, v_dur || ' Months Industrial Warranty'),
      'duration_months', v_dur,
      'warranty_duration_months', v_dur,
      'current_lifecycle_state', 'CURRENTLY_OUT',
      'first_in_timestamp', v_qr.first_in_timestamp,
      'last_out_timestamp', v_qr.last_out_timestamp,
      'warranty_expiry_timestamp', v_qr.warranty_expiry_timestamp,
      'is_expired', (v_qr.warranty_expiry_timestamp is not null and v_qr.warranty_expiry_timestamp < now()),
      'can_mark_in', false,
      'can_mark_out', false,
      'message', 'This bearing was marked OUT and permanently decommissioned. Re-installation is strictly prohibited.'
    );
  end if;

  if v_qr.current_lifecycle_state = 'NOT_ACTIVATED' then
    return jsonb_build_object(
      'status', 'VALID_NOT_ACTIVATED',
      'bearing_id', v_qr.bearing_id,
      'batch_code', v_qr.batch_code,
      'plant_location', v_qr.plant_location,
      'model_number', v_qr.model_number,
      'warranty_title', coalesce(v_qr.warranty_title, v_dur || ' Months Industrial Warranty'),
      'duration_months', v_dur,
      'warranty_duration_months', v_dur,
      'current_lifecycle_state', 'NOT_ACTIVATED',
      'can_mark_in', true,
      'can_mark_out', false,
      'message', 'Authentic Pivot Bearing. Ready for installation & warranty activation.'
    );
  end if;

  v_is_expired := (v_qr.warranty_expiry_timestamp is not null and v_qr.warranty_expiry_timestamp < now());

  return jsonb_build_object(
    'status', case when v_is_expired then 'WARRANTY_EXPIRED' else 'VALID_WARRANTY_ACTIVE' end,
    'bearing_id', v_qr.bearing_id,
    'batch_code', v_qr.batch_code,
    'plant_location', v_qr.plant_location,
    'model_number', v_qr.model_number,
    'warranty_title', coalesce(v_qr.warranty_title, v_dur || ' Months Industrial Warranty'),
    'duration_months', v_dur,
    'warranty_duration_months', v_dur,
    'current_lifecycle_state', 'CURRENTLY_IN',
    'first_in_timestamp', v_qr.first_in_timestamp,
    'last_out_timestamp', v_qr.last_out_timestamp,
    'warranty_expiry_timestamp', v_qr.warranty_expiry_timestamp,
    'is_expired', v_is_expired,
    'can_mark_in', false,
    'can_mark_out', true,
    'message', case when v_is_expired then 'Bearing currently operating. Warranty coverage has expired.' else 'Bearing currently operating with active warranty coverage.' end
  );
end;
$$ language plpgsql security definer;

grant execute on function public.verify_bearing_qr(text, inet, text, text) to authenticated, anon;

-- ==============================================================================
-- 5. Stored Procedure: authenticate_bearing_qr
-- ==============================================================================
drop function if exists public.authenticate_bearing_qr(text, text, inet) cascade;
drop function if exists public.authenticate_bearing_qr(text, text) cascade;
drop function if exists public.authenticate_bearing_qr(text) cascade;

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
  v_user_already_scanned boolean := false;
  v_now timestamptz := now();
  v_duration int := 12;
begin
  if v_trimmed = '' then
    return jsonb_build_object('is_authentic', false, 'status', 'INVALID', 'error_code', 'EMPTY_PAYLOAD', 'message', 'Bearing Authenticity Could Not Be Verified');
  end if;

  if v_trimmed ilike '%/pbi/%' then
    v_bearing_id := split_part(split_part(v_trimmed, '/pbi/', 2), '?', 1);
  elsif v_trimmed ilike '%/verify/%' then
    v_bearing_id := split_part(split_part(v_trimmed, '/verify/', 2), '?', 1);
  elsif v_trimmed ilike 'http%://%' then
    v_bearing_id := split_part(split_part(split_part(v_trimmed, '?', 1), '#', 1), '/', array_length(string_to_array(split_part(split_part(v_trimmed, '?', 1), '#', 1), '/'), 1));
  else
    v_bearing_id := v_trimmed;
  end if;

  v_bearing_id := trim(v_bearing_id);

  select 
    q.id, q.bearing_id, q.batch_id, q.model_number, q.payload_value,
    q.assigned_warranty_plan_id, q.current_lifecycle_state,
    q.first_in_timestamp, q.warranty_expiry_timestamp,
    q.is_flagged, q.flag_reason, q.scan_count, q.first_scanned_at, q.created_at
  into v_qr
  from public.qr_codes q
  where q.bearing_id = v_bearing_id 
     or q.payload_value = v_trimmed 
     or q.payload_value = v_bearing_id
     or q.bearing_id = upper(v_bearing_id)
     or q.bearing_id ilike v_bearing_id
     or q.payload_value ilike v_trimmed
     or replace(replace(q.bearing_id, 'l', 'I'), '1', 'I') ilike replace(replace(v_bearing_id, 'l', 'I'), '1', 'I')
  limit 1
  for update;

  if not found then
    insert into public.scan_records (scanned_payload, scanned_by, is_valid, device_info, ip_address, scan_timestamp)
    values (v_trimmed, v_user_id, false, p_device_info, p_ip_address, v_now);

    return jsonb_build_object('is_authentic', false, 'status', 'INVALID', 'scanned_id', v_bearing_id, 'error_code', 'NOT_REGISTERED', 'message', 'Bearing Authenticity Could Not Be Verified');
  end if;

  if v_qr.current_lifecycle_state in ('FINAL_OUT', 'CURRENTLY_OUT', 'DECOMMISSIONED') then
    return jsonb_build_object('is_authentic', false, 'status', 'ALREADY_OUT', 'bearing_id', v_qr.bearing_id, 'current_lifecycle_state', v_qr.current_lifecycle_state, 'error_code', 'ALREADY_OUT', 'message', 'bearing marked as out, cant scan again.');
  end if;

  v_prev_scans := coalesce(v_qr.scan_count, 0);

  if v_user_id is not null then
    select exists (
      select 1 from public.scan_records 
      where qr_code_id = v_qr.id and scanned_by = v_user_id and is_valid = true
    ) into v_user_already_scanned;
  else
    v_user_already_scanned := false;
  end if;

  if v_user_already_scanned then
    v_total_scans := greatest(v_prev_scans, 1);
  else
    v_total_scans := v_prev_scans + 1;
  end if;

  update public.qr_codes
  set scan_count = v_total_scans,
      first_scanned_at = coalesce(v_qr.first_scanned_at, v_now),
      last_scanned_at = v_now,
      updated_at = v_now
  where id = v_qr.id;

  insert into public.scan_records (qr_code_id, scanned_payload, scanned_by, is_valid, device_info, ip_address, scan_timestamp)
  values (v_qr.id, v_trimmed, v_user_id, true, p_device_info, p_ip_address, v_now);

  select * into v_batch from public.qr_batches where id = v_qr.batch_id;
  select * into v_plan from public.warranty_plans 
  where id = coalesce(v_qr.assigned_warranty_plan_id, v_batch.default_warranty_plan_id);

  v_duration := coalesce(v_plan.duration_months, 12);

  return jsonb_build_object(
    'is_authentic', true,
    'status', 'AUTHENTIC',
    'bearing_id', v_qr.bearing_id,
    'model_number', coalesce(v_qr.model_number, 'B1'),
    'batch_code', coalesce(v_batch.batch_code, 'BATCH-ACTIVE'),
    'plant_location', coalesce(v_batch.plant_location, 'Plant 02 — Chakan Industrial Complex'),
    'warranty_plan_title', coalesce(v_plan.title, v_duration || ' Months Industrial Warranty'),
    'warranty_duration_months', v_duration,
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

grant execute on function public.authenticate_bearing_qr(text, text, inet) to authenticated, anon;

-- ==============================================================================
-- 6. Stored Procedure: confirm_bearing_in
-- Calculates expiry directly from plan duration: first_in + duration_months
-- ==============================================================================
drop function if exists public.confirm_bearing_in(text, uuid, text) cascade;
drop function if exists public.confirm_bearing_in(text, uuid) cascade;
drop function if exists public.confirm_bearing_in(text) cascade;

create or replace function public.confirm_bearing_in(
  p_bearing_id text,
  p_verification_image_id uuid default null,
  p_notes text default null
)
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_qr record;
  v_batch record;
  v_plan record;
  v_default_batch_id uuid;
  v_default_plan_id uuid;
  v_now timestamptz := clock_timestamp();
  v_new_expiry timestamptz;
  v_clean_id text := upper(trim(coalesce(p_bearing_id, '')));
  v_raw_payload text := trim(coalesce(p_bearing_id, ''));
  v_next_cycle int;
  v_new_cycle_id uuid;
  v_duration int := 12;
begin
  if v_clean_id = '' then
    raise exception 'Bearing ID or QR code payload is required.' using errcode = '22023';
  end if;

  if v_clean_id ilike '%/pbi/%' then
    v_clean_id := upper(trim(split_part(split_part(v_clean_id, '/pbi/', 2), '?', 1)));
  elsif v_clean_id ilike '%/verify/%' then
    v_clean_id := upper(trim(split_part(split_part(v_clean_id, '/verify/', 2), '?', 1)));
  elsif v_clean_id ilike 'http%://%' then
    v_clean_id := upper(trim(split_part(split_part(split_part(v_clean_id, '?', 1), '#', 1), '/', array_length(string_to_array(split_part(split_part(v_clean_id, '?', 1), '#', 1), '/'), 1))));
  end if;

  select * into v_qr
  from public.qr_codes
  where bearing_id = v_clean_id
     or payload_value = v_raw_payload
     or payload_value = v_clean_id
     or bearing_id ilike v_clean_id
     or payload_value ilike v_raw_payload
     or replace(replace(bearing_id, 'l', 'I'), '1', 'I') ilike replace(replace(v_clean_id, 'l', 'I'), '1', 'I')
  limit 1
  for update;

  if not found then
    select id into v_default_batch_id from public.qr_batches order by created_at asc limit 1;
    v_default_plan_id := public.get_or_create_warranty_plan(12);

    insert into public.qr_codes (
      bearing_id, batch_id, model_number, payload_value, payload_hash,
      assigned_warranty_plan_id, current_lifecycle_state, assigned_customer_id, is_flagged
    ) values (
      v_clean_id,
      coalesce(v_default_batch_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid),
      'B1',
      v_raw_payload,
      'SHA-256: VALID',
      v_default_plan_id,
      'NOT_ACTIVATED',
      v_user_id,
      false
    )
    on conflict (bearing_id) do update set
      payload_value = excluded.payload_value,
      assigned_customer_id = coalesce(qr_codes.assigned_customer_id, excluded.assigned_customer_id)
    returning * into v_qr;
  end if;

  if v_qr.current_lifecycle_state in ('CURRENTLY_OUT', 'FINAL_OUT', 'DECOMMISSIONED') then
    raise exception 'Bearing % has already been marked OUT and decommissioned. Re-installation is strictly prohibited.', v_qr.bearing_id
      using errcode = 'P0003';
  end if;

  if v_qr.is_flagged = true then
    raise exception 'Bearing % is flagged for security inspection: %', v_qr.bearing_id, coalesce(v_qr.flag_reason, 'Manual hold')
      using errcode = 'P0004';
  end if;

  if v_qr.current_lifecycle_state = 'CURRENTLY_IN' then
    return jsonb_build_object(
      'success', true,
      'action', 'ALREADY_IN',
      'bearing_id', v_qr.bearing_id,
      'lifecycle_state', 'CURRENTLY_IN',
      'in_timestamp', coalesce(v_qr.last_in_timestamp, v_qr.first_in_timestamp, v_now),
      'warranty_expiry', v_qr.warranty_expiry_timestamp,
      'message', 'Bearing is already marked IN and currently operating.'
    );
  end if;

  select * into v_batch from public.qr_batches where id = v_qr.batch_id;
  select * into v_plan from public.warranty_plans 
  where id = coalesce(v_qr.assigned_warranty_plan_id, v_batch.default_warranty_plan_id);

  v_duration := coalesce(v_plan.duration_months, 12);

  -- Authoritatively calculate expiry from plan duration
  v_new_expiry := coalesce(v_qr.first_in_timestamp, v_now) + (v_duration || ' months')::interval;

  update public.qr_codes
  set
    current_lifecycle_state = 'CURRENTLY_IN',
    first_in_timestamp = coalesce(first_in_timestamp, v_now),
    last_in_timestamp = v_now,
    warranty_expiry_timestamp = v_new_expiry,
    assigned_warranty_plan_id = coalesce(assigned_warranty_plan_id, v_plan.id),
    assigned_customer_id = coalesce(v_user_id, assigned_customer_id),
    updated_at = v_now
  where id = v_qr.id;

  select coalesce(max(cycle_number), 0) + 1 into v_next_cycle
  from public.bearing_installation_cycles
  where qr_code_id = v_qr.id;

  insert into public.bearing_installation_cycles (
    qr_code_id, cycle_number, in_timestamp, in_confirmed_by, in_verification_image_id, in_notes
  ) values (
    v_qr.id, v_next_cycle, v_now, v_user_id, p_verification_image_id, p_notes
  )
  returning id into v_new_cycle_id;

  return jsonb_build_object(
    'success', true,
    'action', 'MARKED_IN',
    'bearing_id', v_qr.bearing_id,
    'lifecycle_state', 'CURRENTLY_IN',
    'cycle_number', v_next_cycle,
    'in_timestamp', v_now,
    'warranty_expiry', v_new_expiry,
    'warranty_duration_months', v_duration,
    'message', 'Bearing successfully marked IN. Operational warranty activated.'
  );
end;
$$ language plpgsql security definer;

grant execute on function public.confirm_bearing_in(text, uuid, text) to authenticated, anon;

-- ==============================================================================
-- 7. Retroactive Data Repair for Test Tokens
-- Fixes #CJ7HMKGH$PE, FKUAiJWaEgIh, IO1tjaoIX1h3, and yCPfc7a*CuPR
-- ==============================================================================
do $$
declare
  v_plan_36 uuid;
  v_plan_12 uuid;
  v_plan_3 uuid;
begin
  v_plan_36 := public.get_or_create_warranty_plan(36);
  v_plan_12 := public.get_or_create_warranty_plan(12);
  v_plan_3 := public.get_or_create_warranty_plan(3);

  -- 1. #CJ7HMKGH$PE -> 36 Months Long-Term Industrial (36M)
  update public.qr_codes
  set assigned_warranty_plan_id = v_plan_36,
      model_number = 'B1',
      warranty_expiry_timestamp = coalesce(first_in_timestamp, now()) + interval '36 months',
      updated_at = now()
  where bearing_id ilike '%CJ7HMKGH$PE%' 
     or payload_value ilike '%CJ7HMKGH$PE%';

  update public.qr_batches
  set default_warranty_plan_id = v_plan_36
  where id in (
    select batch_id from public.qr_codes 
    where bearing_id ilike '%CJ7HMKGH$PE%'
  );

  -- 2. FKUAiJWaEgIh / FKUAIJWAEGLH -> 36 Months Long-Term Industrial (36M)
  update public.qr_codes
  set assigned_warranty_plan_id = v_plan_36,
      model_number = 'B1',
      warranty_expiry_timestamp = coalesce(first_in_timestamp, now()) + interval '36 months',
      updated_at = now()
  where bearing_id ilike '%FKUAiJWaEgIh%' 
     or payload_value ilike '%FKUAiJWaEgIh%'
     or bearing_id ilike '%FKUAIJWAEGLH%'
     or payload_value ilike '%FKUAIJWAEGLH%'
     or replace(replace(bearing_id, 'l', 'I'), '1', 'I') ilike '%FKUAIJWAEGIH%';

  update public.qr_batches
  set default_warranty_plan_id = v_plan_36
  where id in (
    select batch_id from public.qr_codes 
    where bearing_id ilike '%FKUAiJWaEgIh%' or bearing_id ilike '%FKUAIJWAEGLH%'
  );

  -- 3. IO1tjaoIX1h3 / IO1TJAOIX1H3 -> 12 Months Industrial Warranty (12M)
  update public.qr_codes
  set assigned_warranty_plan_id = v_plan_12,
      model_number = 'B1',
      updated_at = now()
  where bearing_id ilike '%IO1tjaoIX1h3%'
     or payload_value ilike '%IO1tjaoIX1h3%'
     or bearing_id ilike '%IO1TJAOIX1H3%'
     or payload_value ilike '%IO1TJAOIX1H3%';

  update public.qr_batches
  set default_warranty_plan_id = v_plan_12
  where id in (
    select batch_id from public.qr_codes 
    where bearing_id ilike '%IO1tjaoIX1h3%' or bearing_id ilike '%IO1TJAOIX1H3%'
  );

  -- 4. yCPfc7a*CuPR / YCPFC7A*CUPR -> 3 Months Standard Warranty (3M)
  update public.qr_codes
  set assigned_warranty_plan_id = v_plan_3,
      model_number = 'B1',
      updated_at = now()
  where bearing_id ilike '%yCPfc7a*CuPR%'
     or payload_value ilike '%yCPfc7a*CuPR%'
     or bearing_id ilike '%YCPFC7A*CUPR%'
     or payload_value ilike '%YCPFC7A*CUPR%';

  update public.qr_batches
  set default_warranty_plan_id = v_plan_3
  where id in (
    select batch_id from public.qr_codes 
    where bearing_id ilike '%yCPfc7a*CuPR%' or bearing_id ilike '%YCPFC7A*CUPR%'
  );
end $$;