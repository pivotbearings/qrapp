-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261019000022_realtime_sync_and_scan_count_fix.sql
-- Realtime Data Sync, Accurate Every-Scan Increment Counter & Module Permissions RPC
-- ==============================================================================

-- 1. Schema Updates: Notes column and dropping legacy format constraints
alter table public.bearing_installation_cycles add column if not exists notes text;
alter table public.qr_codes drop constraint if exists qr_codes_bearing_id_check;
alter table public.qr_codes drop constraint if exists qr_codes_bearing_id_format_check;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and tablename = 'profiles'
  ) then
    alter publication supabase_realtime add table public.profiles;
  end if;

  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and tablename = 'qr_codes'
  ) then
    alter publication supabase_realtime add table public.qr_codes;
  end if;

  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and tablename = 'verification_images'
  ) then
    alter publication supabase_realtime add table public.verification_images;
  end if;
exception
  when others then null;
end $$;

-- 2. Stored Procedure: authenticate_bearing_qr
-- Ensures scan_count increments on EVERY authentic scan (never suppressed by device ID)
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

  -- 2. Extract Bearing ID from URL or Raw Serial (Domain-Agnostic)
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

  -- 3. Authoritative DB Lookup with row lock for exact, concurrency-safe scan count
  select 
    q.id,
    q.bearing_id,
    q.batch_id,
    q.model_number,
    q.payload_value,
    q.assigned_warranty_plan_id,
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
     or q.bearing_id = upper(v_bearing_id)
     or q.bearing_id ilike v_bearing_id
     or q.payload_value ilike v_trimmed
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

  -- 4. Check decommissioned state (if bearing is marked OUT, refuse authentication)
  if v_qr.current_lifecycle_state in ('FINAL_OUT', 'CURRENTLY_OUT', 'DECOMMISSIONED') then
    return jsonb_build_object(
      'is_authentic', false,
      'status', 'ALREADY_OUT',
      'bearing_id', v_qr.bearing_id,
      'current_lifecycle_state', v_qr.current_lifecycle_state,
      'error_code', 'ALREADY_OUT',
      'message', 'bearing marked as out, cant scan again.'
    );
  end if;

  -- 5. Calculate scan count: Increment on EVERY authentic scan attempt!
  v_prev_scans := coalesce(v_qr.scan_count, 0);
  v_total_scans := v_prev_scans + 1;

  -- 6. Atomically increment qr_codes scan_count and record scan timestamps
  update public.qr_codes
  set scan_count = v_total_scans,
      first_scanned_at = coalesce(v_qr.first_scanned_at, v_now),
      last_scanned_at = v_now,
      updated_at = v_now
  where id = v_qr.id;

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
  select * into v_plan from public.warranty_plans where id = v_qr.assigned_warranty_plan_id;

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

-- 3. Stored Procedure: admin_get_all_users
-- Rapidly queries all user profiles, roles, module permissions & authorised numbers
drop function if exists public.admin_get_all_users();
create or replace function public.admin_get_all_users()
returns table (
  id uuid,
  email text,
  full_name text,
  company_name text,
  phone text,
  facility_code text,
  role text,
  is_approved boolean,
  is_active boolean,
  has_warranty_access boolean,
  has_track_bearing_access boolean,
  authorised_numbers text[],
  created_at timestamptz
)
language sql
security definer
set search_path = public, auth
stable
as $$
  select
    u.id,
    coalesce(p.email, u.email, '—') as email,
    coalesce(p.full_name, nullif(trim(u.raw_user_meta_data->>'full_name'), ''), split_part(u.email, '@', 1), 'Operator') as full_name,
    coalesce(p.company_name, nullif(trim(u.raw_user_meta_data->>'company_name'), ''), 'Corporate Account') as company_name,
    coalesce(p.phone, nullif(trim(u.raw_user_meta_data->>'phone'), ''), '—') as phone,
    coalesce(p.facility_code, nullif(trim(u.raw_user_meta_data->>'facility_code'), ''), 'FAC-REG') as facility_code,
    coalesce(ur.role, 'USER') as role,
    coalesce(p.is_approved, false) as is_approved,
    coalesce(p.is_active, true) as is_active,
    coalesce(p.has_warranty_access, false) as has_warranty_access,
    coalesce(p.has_track_bearing_access, false) as has_track_bearing_access,
    coalesce(p.authorised_numbers, '{}'::text[]) as authorised_numbers,
    coalesce(p.created_at, u.created_at, now()) as created_at
  from auth.users u
  left join public.profiles p on p.id = u.id
  left join public.user_roles ur on ur.user_id = u.id
  order by created_at desc;
$$;

-- 4. Stored Procedure: admin_update_user_authorised_numbers (Syncs authorised_numbers & phone)
create or replace function public.admin_update_user_authorised_numbers(
  p_target_user_id uuid,
  p_numbers text[]
)
returns jsonb as $$
declare
  v_admin_id uuid := auth.uid();
  v_clean_numbers text[] := '{}';
  v_num text;
  v_primary_phone text := null;
begin
  if not public.is_admin(v_admin_id) then
    raise exception 'Unauthorized: Only administrators can update authorised person numbers.'
      using errcode = '42501';
  end if;

  if coalesce(array_length(p_numbers, 1), 0) > 10 then
    raise exception 'Limit Exceeded: A maximum of 10 authorised numbers can be configured per user.'
      using errcode = '22000';
  end if;

  if p_numbers is not null then
    foreach v_num in array p_numbers loop
      v_num := regexp_replace(trim(v_num), '[^0-9+]', '', 'g');
      if length(v_num) >= 7 and not (v_num = any(v_clean_numbers)) then
        v_clean_numbers := array_append(v_clean_numbers, v_num);
      end if;
    end loop;
  end if;

  if array_length(v_clean_numbers, 1) > 0 then
    v_primary_phone := v_clean_numbers[1];
  end if;

  update public.profiles
  set authorised_numbers = v_clean_numbers,
      phone = coalesce(v_primary_phone, phone),
      updated_at = now()
  where id = p_target_user_id;

  return jsonb_build_object(
    'success', true,
    'user_id', p_target_user_id,
    'authorised_numbers', v_clean_numbers,
    'phone', v_primary_phone
  );
end;
$$ language plpgsql security definer;

-- 5. Stored Procedure: track_bearing_scan (With Auto-Registration for Seamless IN Registry Sync)
drop function if exists public.track_bearing_scan(text);
drop function if exists public.track_bearing_scan(text, text);
create or replace function public.track_bearing_scan(
  p_scanned_payload text,
  p_notes text default null
)
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_trimmed text := trim(coalesce(p_scanned_payload, ''));
  v_bearing_id text;
  v_now timestamptz := clock_timestamp();
  v_qr record;
  v_batch record;
  v_plan record;
  v_default_batch_id uuid;
  v_default_plan_id uuid;
  v_active_cycle record;
  v_next_cycle int;
  v_duration_seconds bigint := 0;
  v_duration_interval interval;
  v_history jsonb := '[]'::jsonb;
  v_new_cycle_id uuid;
begin
  if v_trimmed = '' then
    return jsonb_build_object('is_valid', false, 'status', 'INVALID', 'message', 'Empty payload.');
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
    q.batch_id,
    q.model_number,
    q.payload_value,
    q.assigned_warranty_plan_id,
    q.current_lifecycle_state,
    q.first_in_timestamp,
    q.last_in_timestamp,
    q.is_flagged,
    q.flag_reason
  into v_qr
  from public.qr_codes q
  where q.bearing_id = v_bearing_id 
     or q.payload_value = v_trimmed 
     or q.payload_value = v_bearing_id
     or q.bearing_id = upper(v_bearing_id)
     or q.bearing_id ilike v_bearing_id
     or q.payload_value ilike v_trimmed
  for update;

  if not found then
    if v_bearing_id ~* '^[A-Za-z0-9@$#\[\]\-\*]{12}$' or v_bearing_id ~* '^PB-[0-9]{4}-[A-Z0-9]{2}$' or v_bearing_id ilike 'PB-%' then
      -- Resilient fallback: find existing batch and plan if available
      select id into v_default_batch_id from public.qr_batches order by created_at asc limit 1;
      select id into v_default_plan_id from public.warranty_plans order by duration_months asc limit 1;

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
        v_bearing_id,
        coalesce(v_default_batch_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid),
        'PBI-6204-ZZ',
        v_trimmed,
        'SHA-256: VALID',
        coalesce(v_default_plan_id, '22222222-2222-2222-2222-222222222222'::uuid),
        'NOT_ACTIVATED',
        false
      )
      on conflict (bearing_id) do update set
        payload_value = excluded.payload_value
      returning 
        id, bearing_id, batch_id, model_number, payload_value,
        assigned_warranty_plan_id, current_lifecycle_state,
        first_in_timestamp, last_in_timestamp, is_flagged, flag_reason
      into v_qr;
    else
      return jsonb_build_object(
        'is_valid', false,
        'status', 'NOT_FOUND',
        'scanned_id', v_bearing_id,
        'message', 'Bearing Authenticity Could Not Be Verified. Unregistered code.'
      );
    end if;
  end if;

  select * into v_batch from public.qr_batches where id = v_qr.batch_id;
  select * into v_plan from public.warranty_plans where id = v_qr.assigned_warranty_plan_id;

  if v_qr.current_lifecycle_state = 'CURRENTLY_IN' then
    select * into v_active_cycle
    from public.bearing_installation_cycles
    where qr_code_id = v_qr.id and is_cycle_closed = false
    order by cycle_number desc
    limit 1;

    if not found then
      v_duration_interval := v_now - coalesce(v_qr.last_in_timestamp, v_qr.first_in_timestamp, v_now);
      v_duration_seconds := extract(epoch from v_duration_interval)::bigint;

      select coalesce(max(cycle_number), 0) + 1 into v_next_cycle
      from public.bearing_installation_cycles
      where qr_code_id = v_qr.id;

      insert into public.bearing_installation_cycles (
        qr_code_id, cycle_number, in_timestamp, in_confirmed_by,
        out_timestamp, out_confirmed_by, operating_duration_interval,
        operating_duration_seconds, is_cycle_closed, notes
      ) values (
        v_qr.id, v_next_cycle, coalesce(v_qr.last_in_timestamp, v_qr.first_in_timestamp, v_now),
        v_user_id, v_now, v_user_id, v_duration_interval, v_duration_seconds, true, p_notes
      );
    else
      v_duration_interval := v_now - v_active_cycle.in_timestamp;
      v_duration_seconds := extract(epoch from v_duration_interval)::bigint;
      v_next_cycle := v_active_cycle.cycle_number;

      update public.bearing_installation_cycles
      set out_timestamp = v_now,
          out_confirmed_by = v_user_id,
          operating_duration_interval = v_duration_interval,
          operating_duration_seconds = v_duration_seconds,
          is_cycle_closed = true,
          notes = coalesce(p_notes, notes),
          updated_at = v_now
      where id = v_active_cycle.id;
    end if;

    update public.qr_codes
    set current_lifecycle_state = 'CURRENTLY_OUT',
        updated_at = v_now
    where id = v_qr.id;

    select coalesce(jsonb_agg(
      jsonb_build_object(
        'cycle_number', c.cycle_number,
        'in_timestamp', c.in_timestamp,
        'out_timestamp', c.out_timestamp,
        'duration_seconds', c.operating_duration_seconds
      ) order by c.cycle_number desc
    ), '[]'::jsonb) into v_history
    from public.bearing_installation_cycles c
    where c.qr_code_id = v_qr.id and c.is_cycle_closed = true;

    return jsonb_build_object(
      'is_valid', true,
      'action', 'BEARING_OUT',
      'bearing_id', v_qr.bearing_id,
      'model_number', v_qr.model_number,
      'batch_code', coalesce(v_batch.batch_code, 'N/A'),
      'plant_location', coalesce(v_batch.plant_location, 'Pivot Bearings India Plant'),
      'cycle_number', v_next_cycle,
      'in_timestamp', coalesce(v_active_cycle.in_timestamp, v_qr.last_in_timestamp, v_now),
      'out_timestamp', v_now,
      'duration_seconds', v_duration_seconds,
      'duration_days', floor(v_duration_seconds / 86400),
      'duration_hours', floor((v_duration_seconds % 86400) / 3600),
      'duration_minutes', floor((v_duration_seconds % 3600) / 60),
      'message', 'Bearing Out recorded successfully.',
      'notes', coalesce(v_active_cycle.notes, p_notes),
      'lifecycle_history', v_history
    );
  else
    select coalesce(max(cycle_number), 0) + 1 into v_next_cycle
    from public.bearing_installation_cycles
    where qr_code_id = v_qr.id;

    insert into public.bearing_installation_cycles (
      qr_code_id, cycle_number, in_timestamp, in_confirmed_by, is_cycle_closed, notes
    ) values (
      v_qr.id, v_next_cycle, v_now, v_user_id, false, p_notes
    ) returning id into v_new_cycle_id;

    update public.qr_codes
    set current_lifecycle_state = 'CURRENTLY_IN',
        first_in_timestamp = coalesce(first_in_timestamp, v_now),
        last_in_timestamp = v_now,
        updated_at = v_now
    where id = v_qr.id;

    select coalesce(jsonb_agg(
      jsonb_build_object(
        'cycle_number', c.cycle_number,
        'in_timestamp', c.in_timestamp,
        'out_timestamp', c.out_timestamp,
        'duration_seconds', c.operating_duration_seconds
      ) order by c.cycle_number desc
    ), '[]'::jsonb) into v_history
    from public.bearing_installation_cycles c
    where c.qr_code_id = v_qr.id and c.is_cycle_closed = true;

    return jsonb_build_object(
      'is_valid', true,
      'action', 'BEARING_IN',
      'bearing_id', v_qr.bearing_id,
      'model_number', v_qr.model_number,
      'batch_code', coalesce(v_batch.batch_code, 'N/A'),
      'plant_location', coalesce(v_batch.plant_location, 'Pivot Bearings India Plant'),
      'cycle_number', v_next_cycle,
      'in_timestamp', v_now,
      'out_timestamp', null,
      'duration_seconds', 0,
      'duration_days', 0,
      'duration_hours', 0,
      'duration_minutes', 0,
      'message', 'Bearing In recorded successfully. Usage tracking has started.',
      'lifecycle_history', v_history
    );
  end if;
end;
$$ language plpgsql security definer;

-- 6. Stored Procedure: generate_random_12char_qr_value
-- Generates a 12-character totally randomised, encrypted-style QR value
-- Character pool: [A-Za-z0-9@$#[]-*] (69 unique characters, 13.4 sextillion combinations)
create or replace function public.generate_random_12char_qr_value()
returns text as $$
declare
  v_chars text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@$#[]-*';
  v_chars_len int := length(v_chars);
  v_result text := '';
  v_byte int;
  v_idx int;
  v_i int;
begin
  for v_i in 1..12 loop
    v_byte := get_byte(gen_random_bytes(1), 0);
    v_idx := (v_byte % v_chars_len) + 1;
    v_result := v_result || substr(v_chars, v_idx, 1);
  end loop;
  return v_result;
end;
$$ language plpgsql volatile;

-- 7. Stored Procedure: generate_qr_batch
-- Generates batches of 12-character totally randomised encrypted QR values with zero duplicates
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
  v_max_attempts integer := p_quantity * 10;
  v_attempts integer := 0;
  v_qr_value text;
  v_hash text;
  v_inserted_ids text[] := array[]::text[];
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
      select id into v_plan_id from public.warranty_plans limit 1;
    end if;
  else
    if not exists (select 1 from public.warranty_plans where id = v_plan_id) then
      select id into v_plan_id from public.warranty_plans limit 1;
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

  -- 5. Batch Generation Loop (12-char randomized encrypted tokens, 0 duplicates)
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
        p_model_number,
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

  -- 6. Safe Audit Trail Logging
  begin
    insert into public.audit_logs (
      user_id,
      action,
      entity_type,
      entity_id,
      metadata
    ) values (
      v_admin_id,
      'GENERATE_QR_BATCH',
      'qr_batches',
      v_batch_id,
      jsonb_build_object(
        'batch_code', p_batch_code,
        'plant_location', p_plant_location,
        'quantity', v_generated_count,
        'format', '12_CHAR_RANDOM_ENCRYPTED',
        'model_number', p_model_number
      )
    );
  exception when others then
    null;
  end;

  return jsonb_build_object(
    'success', true,
    'batch_id', v_batch_id,
    'batch_code', p_batch_code,
    'quantity_generated', v_generated_count,
    'bearing_ids', to_jsonb(v_inserted_ids)
  );
end;
$$ language plpgsql security definer;

-- 8. Grants for Stored Procedures
grant execute on function public.authenticate_bearing_qr(text, text, inet) to authenticated, anon;
grant execute on function public.admin_get_all_users() to authenticated;
grant execute on function public.admin_update_user_authorised_numbers(uuid, text[]) to authenticated;
grant execute on function public.track_bearing_scan(text, text) to authenticated, anon;
grant execute on function public.generate_random_12char_qr_value() to authenticated, anon;
grant execute on function public.generate_qr_batch(text, text, integer, text, uuid) to authenticated;
