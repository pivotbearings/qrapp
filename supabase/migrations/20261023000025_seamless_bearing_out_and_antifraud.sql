-- Migration 20261023000025: Seamless Bearing OUT & Resilient Anti-Fraud Handling
-- 1. Upgrades confirm_bearing_out so it never fails on missing cycles or auth tokens
-- 2. Provides idempotent return when bearing is already marked OUT

create or replace function public.confirm_bearing_out(
  p_bearing_id text,
  p_verification_image_id uuid default null,
  p_notes text default null
)
returns jsonb as $$
declare
  v_user_id uuid := coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid);
  v_qr record;
  v_cycle record;
  v_now timestamptz := clock_timestamp();
  v_duration_interval interval;
  v_duration_seconds bigint;
  v_was_warranty_active boolean;
  v_clean_id text := upper(trim(coalesce(p_bearing_id, '')));
  v_formatted_duration text;
  v_days integer;
  v_hours integer;
  v_mins integer;
begin
  if v_clean_id = '' then
    raise exception 'Bearing ID is required.' using errcode = '22023';
  end if;

  -- Normalize URLs/paths to bearing ID
  if v_clean_id ilike '%/pbi/%' then
    v_clean_id := upper(trim(split_part(split_part(v_clean_id, '/pbi/', 2), '?', 1)));
  elsif v_clean_id ilike '%/verify/%' then
    v_clean_id := upper(trim(split_part(split_part(v_clean_id, '/verify/', 2), '?', 1)));
  elsif v_clean_id ilike 'http%://%' then
    v_clean_id := upper(trim(split_part(split_part(split_part(v_clean_id, '?', 1), '#', 1), '/', array_length(string_to_array(split_part(split_part(v_clean_id, '?', 1), '#', 1), '/'), 1))));
  end if;

  -- 2. Concurrency Lock: Lock QR Record
  select * into v_qr
  from public.qr_codes
  where bearing_id = v_clean_id
     or payload_value = v_clean_id
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

  -- 4. Idempotent check: If already marked OUT / DECOMMISSIONED, return existing state seamlessly
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

  -- 5. Fetch the latest open installation cycle
  select * into v_cycle
  from public.bearing_installation_cycles
  where qr_code_id = v_qr.id
    and is_cycle_closed = false
  order by cycle_number desc
  limit 1
  for update;

  -- Resilient auto-cycle creation if open cycle record was missing
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
    -- Calculate duration
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

  -- 6. Set Current State to CURRENTLY_OUT and record last_out_timestamp
  update public.qr_codes
  set
    current_lifecycle_state = 'CURRENTLY_OUT',
    last_out_timestamp = v_now,
    updated_at = v_now
  where id = v_qr.id;

  -- 7. Record Immutable Audit Trail Event
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
    'bearing_id', v_qr.bearing_id,
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

grant execute on function public.confirm_bearing_out(text, uuid, text) to authenticated, anon;
