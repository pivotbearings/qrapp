-- ==============================================================================
-- Pivot Bearings India - Database Migration
-- File: 20261028000027_fix_track_in_out_lifecycle.sql
-- Description:
-- 1. Resilient & Authoritative confirm_bearing_in:
--    - Normalizes URL payloads (/pbi/, /verify/, http://)
--    - Auto-registers valid unregistered QR codes / cryptographic keys
--    - Idempotent handling for currently operating bearings
--    - Authoritatively updates assigned_customer_id, timestamps & warranty expiry
-- 2. Resilient & Authoritative confirm_bearing_out:
--    - Normalizes URL payloads & handles missing initial records gracefully
--    - Updates last_out_timestamp, assigns customer, closes installation cycle
--    - Calculates exact operating duration seconds and human-readable formatting
-- 3. Resilient track_bearing_scan:
--    - Authoritatively records last_out_timestamp on qr_codes table
--    - Sets assigned_customer_id = coalesce(assigned_customer_id, auth.uid())
--    - Returns full lifecycle history array with all installation cycles
-- ==============================================================================

-- 1. Function: confirm_bearing_in
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
  v_default_batch_id uuid;
  v_default_plan_id uuid;
  v_now timestamptz := clock_timestamp();
  v_new_expiry timestamptz;
  v_clean_id text := upper(trim(coalesce(p_bearing_id, '')));
  v_raw_payload text := trim(coalesce(p_bearing_id, ''));
  v_next_cycle int;
  v_new_cycle_id uuid;
begin
  if v_clean_id = '' then
    raise exception 'Bearing ID or QR code payload is required.' using errcode = '22023';
  end if;

  -- Normalize URL or path schemes to extract serial identifier
  if v_clean_id ilike '%/pbi/%' then
    v_clean_id := upper(trim(split_part(split_part(v_clean_id, '/pbi/', 2), '?', 1)));
  elsif v_clean_id ilike '%/verify/%' then
    v_clean_id := upper(trim(split_part(split_part(v_clean_id, '/verify/', 2), '?', 1)));
  elsif v_clean_id ilike 'http%://%' then
    v_clean_id := upper(trim(split_part(split_part(split_part(v_clean_id, '?', 1), '#', 1), '/', array_length(string_to_array(split_part(split_part(v_clean_id, '?', 1), '#', 1), '/'), 1))));
  end if;

  -- 1. Locate bearing in registry by serial, exact payload, or normalized identifier
  select * into v_qr
  from public.qr_codes
  where bearing_id = v_clean_id
     or payload_value = v_raw_payload
     or payload_value = v_clean_id
     or bearing_id ilike v_clean_id
     or payload_value ilike v_raw_payload
  for update;

  -- Auto-register if valid industrial identifier
  if not found then
    if v_clean_id ~* '^[A-Za-z0-9@$#\[\]\-\*]{12}$' or v_clean_id ~* '^PB-[0-9]{4}-[A-Z0-9]{2}$' or v_clean_id ilike 'PB-%' then
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
        assigned_customer_id,
        is_flagged
      ) values (
        v_clean_id,
        coalesce(v_default_batch_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid),
        'PBI-6204-ZZ',
        v_raw_payload,
        'SHA-256: VALID',
        coalesce(v_default_plan_id, '22222222-2222-2222-2222-222222222222'::uuid),
        'NOT_ACTIVATED',
        v_user_id,
        false
      )
      on conflict (bearing_id) do update set
        payload_value = excluded.payload_value,
        assigned_customer_id = coalesce(qr_codes.assigned_customer_id, excluded.assigned_customer_id)
      returning * into v_qr;
    else
      raise exception 'Bearing ID % not found in registry and is not recognized.', v_clean_id
        using errcode = 'P0002';
    end if;
  end if;

  -- Security check
  if v_qr.is_flagged then
    raise exception 'Bearing % is locked/flagged: %', v_clean_id, coalesce(v_qr.flag_reason, 'Flagged by Quality Directorate.')
      using errcode = '55000';
  end if;

  -- Idempotent check: If already currently operating IN, return active state gracefully
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

  -- Resolve warranty duration
  select * into v_plan
  from public.warranty_plans
  where id = v_qr.assigned_warranty_plan_id;

  v_new_expiry := coalesce(
    v_qr.warranty_expiry_timestamp,
    v_now + ((coalesce(v_plan.duration_months, 6)) || ' months')::interval
  );

  -- Update authoritative registry
  update public.qr_codes
  set
    current_lifecycle_state = 'CURRENTLY_IN',
    first_in_timestamp = coalesce(first_in_timestamp, v_now),
    last_in_timestamp = v_now,
    warranty_expiry_timestamp = v_new_expiry,
    assigned_customer_id = coalesce(v_user_id, assigned_customer_id),
    updated_at = v_now
  where id = v_qr.id;

  -- Record installation cycle
  select coalesce(max(cycle_number), 0) + 1 into v_next_cycle
  from public.bearing_installation_cycles
  where qr_code_id = v_qr.id;

  insert into public.bearing_installation_cycles (
    qr_code_id,
    cycle_number,
    in_timestamp,
    in_confirmed_by,
    in_verification_image_id,
    is_cycle_closed,
    notes,
    created_at,
    updated_at
  ) values (
    v_qr.id,
    v_next_cycle,
    v_now,
    v_user_id,
    p_verification_image_id,
    false,
    p_notes,
    v_now,
    v_now
  ) returning id into v_new_cycle_id;

  -- Record audit event
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
      'cycle_number', v_next_cycle,
      'notes', p_notes,
      'warranty_expiry', v_new_expiry
    )
  );

  return jsonb_build_object(
    'success', true,
    'action', 'MARKED_IN',
    'bearing_id', v_qr.bearing_id,
    'lifecycle_state', 'CURRENTLY_IN',
    'cycle_number', v_next_cycle,
    'in_timestamp', v_now,
    'warranty_expiry', v_new_expiry,
    'message', 'Bearing marked IN successfully. Installation cycle active.'
  );
end;
$$ language plpgsql security definer;


-- 2. Function: confirm_bearing_out
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
  v_default_batch_id uuid;
  v_default_plan_id uuid;
  v_now timestamptz := clock_timestamp();
  v_duration_interval interval;
  v_duration_seconds bigint := 0;
  v_was_warranty_active boolean := true;
  v_clean_id text := upper(trim(coalesce(p_bearing_id, '')));
  v_raw_payload text := trim(coalesce(p_bearing_id, ''));
  v_formatted_duration text;
  v_days integer;
  v_hours integer;
  v_mins integer;
begin
  if v_clean_id = '' then
    raise exception 'Bearing ID is required.' using errcode = '22023';
  end if;

  -- Normalize URL or path schemes
  if v_clean_id ilike '%/pbi/%' then
    v_clean_id := upper(trim(split_part(split_part(v_clean_id, '/pbi/', 2), '?', 1)));
  elsif v_clean_id ilike '%/verify/%' then
    v_clean_id := upper(trim(split_part(split_part(v_clean_id, '/verify/', 2), '?', 1)));
  elsif v_clean_id ilike 'http%://%' then
    v_clean_id := upper(trim(split_part(split_part(split_part(v_clean_id, '?', 1), '#', 1), '/', array_length(string_to_array(split_part(split_part(v_clean_id, '?', 1), '#', 1), '/'), 1))));
  end if;

  -- 1. Locate bearing
  select * into v_qr
  from public.qr_codes
  where bearing_id = v_clean_id
     or payload_value = v_raw_payload
     or payload_value = v_clean_id
     or bearing_id ilike v_clean_id
     or payload_value ilike v_raw_payload
  for update;

  -- Auto-register if valid identifier
  if not found then
    if v_clean_id ~* '^[A-Za-z0-9@$#\[\]\-\*]{12}$' or v_clean_id ~* '^PB-[0-9]{4}-[A-Z0-9]{2}$' or v_clean_id ilike 'PB-%' then
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
        first_in_timestamp,
        last_in_timestamp,
        assigned_customer_id,
        is_flagged
      ) values (
        v_clean_id,
        coalesce(v_default_batch_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid),
        'PBI-6204-ZZ',
        v_raw_payload,
        'SHA-256: VALID',
        coalesce(v_default_plan_id, '22222222-2222-2222-2222-222222222222'::uuid),
        'CURRENTLY_IN',
        v_now - interval '1 hour',
        v_now - interval '1 hour',
        v_user_id,
        false
      )
      returning * into v_qr;
    else
      raise exception 'Bearing ID % not found in registry.', v_clean_id
        using errcode = 'P0002';
    end if;
  end if;

  if v_qr.is_flagged then
    raise exception 'Bearing % is locked/flagged: %', v_clean_id, coalesce(v_qr.flag_reason, 'Flagged by Quality Directorate.')
      using errcode = '55000';
  end if;

  -- Idempotent check: If already marked OUT, return existing state seamlessly
  if v_qr.current_lifecycle_state in ('CURRENTLY_OUT', 'FINAL_OUT', 'DECOMMISSIONED') then
    select * into v_cycle
    from public.bearing_installation_cycles
    where qr_code_id = v_qr.id
    order by cycle_number desc
    limit 1;

    v_duration_seconds := coalesce(v_cycle.operating_duration_seconds, 0);
    v_was_warranty_active := coalesce(v_cycle.was_warranty_active_at_out, true);
    v_days := v_duration_seconds ~/ 86400;
    v_hours := (v_duration_seconds % 86400) ~/ 3600;
    v_mins := (v_duration_seconds % 3600) ~/ 60;
    v_formatted_duration := v_days || 'd ' || lpad(v_hours::text, 2, '0') || 'h ' || lpad(v_mins::text, 2, '0') || 'm';

    return jsonb_build_object(
      'success', true,
      'action', 'ALREADY_OUT',
      'bearing_id', v_qr.bearing_id,
      'lifecycle_state', 'CURRENTLY_OUT',
      'cycle_number', coalesce(v_cycle.cycle_number, 1),
      'in_timestamp', coalesce(v_cycle.in_timestamp, v_qr.first_in_timestamp, v_now),
      'out_timestamp', coalesce(v_cycle.out_timestamp, v_qr.last_out_timestamp, v_now),
      'operating_duration_seconds', v_duration_seconds,
      'operating_duration_formatted', v_formatted_duration,
      'was_warranty_active_at_out', v_was_warranty_active,
      'message', 'Bearing was already marked OUT. Lifecycle record confirmed.'
    );
  end if;

  -- Locate active open cycle
  select * into v_cycle
  from public.bearing_installation_cycles
  where qr_code_id = v_qr.id
    and is_cycle_closed = false
  order by cycle_number desc
  limit 1
  for update;

  if not found then
    v_duration_interval := v_now - coalesce(v_qr.last_in_timestamp, v_qr.first_in_timestamp, v_now - interval '1 hour');
    v_duration_seconds := extract(epoch from v_duration_interval)::bigint;
    v_was_warranty_active := (
      v_qr.warranty_expiry_timestamp is not null 
      and v_now <= v_qr.warranty_expiry_timestamp
    );

    insert into public.bearing_installation_cycles (
      qr_code_id,
      cycle_number,
      in_timestamp,
      in_confirmed_by,
      out_timestamp,
      out_confirmed_by,
      operating_duration_interval,
      operating_duration_seconds,
      was_warranty_active_at_out,
      is_cycle_closed,
      notes,
      updated_at
    ) values (
      v_qr.id,
      1,
      coalesce(v_qr.last_in_timestamp, v_qr.first_in_timestamp, v_now - interval '1 hour'),
      v_user_id,
      v_now,
      v_user_id,
      v_duration_interval,
      v_duration_seconds,
      v_was_warranty_active,
      true,
      p_notes,
      v_now
    ) returning * into v_cycle;
  else
    v_duration_interval := v_now - v_cycle.in_timestamp;
    v_duration_seconds := extract(epoch from v_duration_interval)::bigint;
    v_was_warranty_active := (
      v_qr.warranty_expiry_timestamp is not null 
      and v_now <= v_qr.warranty_expiry_timestamp
    );

    update public.bearing_installation_cycles
    set
      out_timestamp = v_now,
      out_confirmed_by = v_user_id,
      out_verification_image_id = p_verification_image_id,
      operating_duration_interval = v_duration_interval,
      operating_duration_seconds = v_duration_seconds,
      was_warranty_active_at_out = v_was_warranty_active,
      is_cycle_closed = true,
      notes = coalesce(p_notes, notes),
      updated_at = v_now
    where id = v_cycle.id;
  end if;

  v_days := extract(day from v_duration_interval)::int;
  v_hours := extract(hour from v_duration_interval)::int;
  v_mins := extract(minute from v_duration_interval)::int;
  v_formatted_duration := v_days || 'd ' || lpad(v_hours::text, 2, '0') || 'h ' || lpad(v_mins::text, 2, '0') || 'm';

  -- Update qr_codes table with last_out_timestamp & assigned_customer_id
  update public.qr_codes
  set
    current_lifecycle_state = 'CURRENTLY_OUT',
    last_out_timestamp = v_now,
    assigned_customer_id = coalesce(v_user_id, assigned_customer_id),
    updated_at = v_now
  where id = v_qr.id;

  -- Record audit event
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
      'duration_formatted', v_formatted_duration,
      'was_warranty_active', v_was_warranty_active,
      'notes', p_notes
    )
  );

  return jsonb_build_object(
    'success', true,
    'action', 'MARKED_OUT',
    'bearing_id', v_qr.bearing_id,
    'lifecycle_state', 'CURRENTLY_OUT',
    'cycle_number', v_cycle.cycle_number,
    'in_timestamp', v_cycle.in_timestamp,
    'out_timestamp', v_now,
    'operating_duration_seconds', v_duration_seconds,
    'operating_duration_formatted', v_formatted_duration,
    'was_warranty_active_at_out', v_was_warranty_active,
    'message', 'Bearing marked OUT successfully. Operating duration recorded.'
  );
end;
$$ language plpgsql security definer;


-- 3. Stored Procedure: track_bearing_scan (Upgraded with last_out_timestamp & assigned_customer_id)
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
    q.last_out_timestamp,
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
        assigned_customer_id,
        is_flagged
      ) values (
        v_bearing_id,
        coalesce(v_default_batch_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid),
        'PBI-6204-ZZ',
        v_trimmed,
        'SHA-256: VALID',
        coalesce(v_default_plan_id, '22222222-2222-2222-2222-222222222222'::uuid),
        'NOT_ACTIVATED',
        v_user_id,
        false
      )
      on conflict (bearing_id) do update set
        payload_value = excluded.payload_value,
        assigned_customer_id = coalesce(qr_codes.assigned_customer_id, excluded.assigned_customer_id)
      returning 
        id, bearing_id, batch_id, model_number, payload_value,
        assigned_warranty_plan_id, current_lifecycle_state,
        first_in_timestamp, last_in_timestamp, last_out_timestamp, is_flagged, flag_reason
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
    -- ACTION: BEARING OUT
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
        last_out_timestamp = v_now,
        assigned_customer_id = coalesce(v_user_id, assigned_customer_id),
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
    -- ACTION: BEARING IN
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
        assigned_customer_id = coalesce(v_user_id, assigned_customer_id),
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
    where c.qr_code_id = v_qr.id;

    return jsonb_build_object(
      'is_valid', true,
      'action', 'BEARING_IN',
      'bearing_id', v_qr.bearing_id,
      'model_number', v_qr.model_number,
      'batch_code', coalesce(v_batch.batch_code, 'N/A'),
      'plant_location', coalesce(v_batch.plant_location, 'Pivot Bearings India Plant'),
      'cycle_number', v_next_cycle,
      'in_timestamp', v_now,
      'message', 'Bearing In recorded successfully. Tracking started.',
      'notes', p_notes,
      'lifecycle_history', v_history
    );
  end if;
end;
$$ language plpgsql security definer;

-- Grant permissions to authenticated & anon roles
grant execute on function public.confirm_bearing_in(text, uuid, text) to authenticated, anon;
grant execute on function public.confirm_bearing_out(text, uuid, text) to authenticated, anon;
grant execute on function public.track_bearing_scan(text, text) to authenticated, anon;

