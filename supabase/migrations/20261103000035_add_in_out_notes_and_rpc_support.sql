-- ==============================================================================
-- Migration: 20261103000035_add_in_out_notes_and_rpc_support.sql
-- Description: Adds separate columns for mark in notes and mark out notes to 
--              qr_codes and bearing_installation_cycles.
--              Updates confirm_bearing_in, confirm_bearing_out, and
--              get_bearing_lifecycle_summary to preserve and return both notes.
-- ==============================================================================

-- 1. Ensure columns exist on public.qr_codes
alter table public.qr_codes 
  add column if not exists in_notes text,
  add column if not exists out_notes text;

-- 2. Ensure columns exist on public.bearing_installation_cycles
alter table public.bearing_installation_cycles 
  add column if not exists in_notes text,
  add column if not exists out_notes text;

-- 3. Update confirm_bearing_in
create or replace function public.confirm_bearing_in(
  p_bearing_id text,
  p_verification_image_id uuid default null,
  p_notes text default null
)
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_qr record;
  v_now timestamptz := clock_timestamp();
  v_dur integer := 12;
  v_expiry timestamptz;
  v_next_cycle integer := 1;
  v_clean text := trim(coalesce(p_bearing_id, ''));
begin
  if v_clean = '' then
    raise exception 'Bearing ID is required.' using errcode = '22023';
  end if;

  if v_clean ilike '%/pbi/%' then
    v_clean := split_part(split_part(v_clean, '/pbi/', 2), '?', 1);
  end if;

  select * into v_qr
  from public.qr_codes
  where bearing_id = v_clean
     or upper(bearing_id) = upper(v_clean)
     or payload_value = v_clean
     or upper(payload_value) = upper(v_clean)
  limit 1
  for update;

  if v_qr.id is null then
    raise exception 'Bearing % is not registered in system.', v_clean
      using errcode = 'P0002';
  end if;

  if v_qr.current_lifecycle_state in ('CURRENTLY_OUT', 'FINAL_OUT', 'DECOMMISSIONED') then
    raise exception 'Bearing % has already been decommissioned. Re-installation prohibited.', v_qr.bearing_id
      using errcode = 'P0003';
  end if;

  if v_qr.current_lifecycle_state = 'CURRENTLY_IN' then
    return jsonb_build_object(
      'success', true,
      'action', 'ALREADY_IN',
      'bearing_id', v_qr.bearing_id,
      'lifecycle_state', 'CURRENTLY_IN',
      'in_timestamp', v_qr.first_in_timestamp,
      'warranty_expiry', v_qr.warranty_expiry_timestamp,
      'warranty_duration_months', v_qr.warranty_duration_months,
      'in_notes', coalesce(v_qr.in_notes, v_qr.notes)
    );
  end if;

  -- Resolve frozen duration
  v_dur := coalesce(v_qr.warranty_duration_months, 12);
  v_expiry := v_now + (v_dur || ' months')::interval;

  -- Write authoritative activation
  update public.qr_codes
  set
    current_lifecycle_state = 'CURRENTLY_IN',
    first_in_timestamp = coalesce(first_in_timestamp, v_now),
    last_in_timestamp = v_now,
    warranty_expiry_timestamp = coalesce(warranty_expiry_timestamp, v_expiry),
    warranty_duration_months = v_dur,
    assigned_customer_id = coalesce(v_user_id, assigned_customer_id),
    in_notes = coalesce(p_notes, in_notes),
    notes = coalesce(p_notes, notes),
    updated_at = v_now
  where id = v_qr.id;

  select coalesce(max(cycle_number), 0) + 1 into v_next_cycle
  from public.bearing_installation_cycles
  where qr_code_id = v_qr.id;

  insert into public.bearing_installation_cycles (
    qr_code_id, cycle_number, in_timestamp, in_confirmed_by, in_verification_image_id, notes, in_notes, updated_at
  ) values (
    v_qr.id, v_next_cycle, v_now, v_user_id, p_verification_image_id, p_notes, p_notes, v_now
  );

  return jsonb_build_object(
    'success', true,
    'action', 'MARKED_IN',
    'bearing_id', v_qr.bearing_id,
    'lifecycle_state', 'CURRENTLY_IN',
    'cycle_number', v_next_cycle,
    'in_timestamp', v_now,
    'warranty_expiry', v_expiry,
    'warranty_duration_months', v_dur,
    'in_notes', p_notes,
    'message', 'Bearing marked IN. Operational warranty activated.'
  );
end;
$$ language plpgsql security definer;

grant execute on function public.confirm_bearing_in(text, uuid, text) to authenticated, anon;

-- 4. Update confirm_bearing_out
create or replace function public.confirm_bearing_out(
  p_bearing_id text,
  p_verification_image_id uuid default null,
  p_notes text default null
)
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_qr record;
  v_now timestamptz := clock_timestamp();
  v_in_time timestamptz;
  v_op_seconds bigint := 0;
  v_was_active boolean := true;
  v_clean text := trim(coalesce(p_bearing_id, ''));
  v_cycle record;
begin
  if v_clean = '' then
    raise exception 'Bearing ID is required.' using errcode = '22023';
  end if;

  if v_clean ilike '%/pbi/%' then
    v_clean := split_part(split_part(v_clean, '/pbi/', 2), '?', 1);
  end if;

  select * into v_qr
  from public.qr_codes
  where bearing_id = v_clean
     or upper(bearing_id) = upper(v_clean)
     or payload_value = v_clean
     or upper(payload_value) = upper(v_clean)
  limit 1
  for update;

  if v_qr.id is null then
    raise exception 'Bearing % is not registered. Cannot mark OUT.', v_clean
      using errcode = 'P0002';
  end if;

  if v_qr.current_lifecycle_state in ('CURRENTLY_OUT', 'FINAL_OUT', 'DECOMMISSIONED') then
    return jsonb_build_object(
      'success', true,
      'action', 'ALREADY_OUT',
      'bearing_id', v_qr.bearing_id,
      'lifecycle_state', 'CURRENTLY_OUT',
      'in_timestamp', v_qr.first_in_timestamp,
      'out_timestamp', v_qr.last_out_timestamp,
      'warranty_expiry', v_qr.warranty_expiry_timestamp,
      'warranty_duration_months', v_qr.warranty_duration_months,
      'in_notes', coalesce(v_qr.in_notes, v_qr.notes),
      'out_notes', v_qr.out_notes
    );
  end if;

  v_in_time := coalesce(v_qr.last_in_timestamp, v_qr.first_in_timestamp, v_now);
  v_op_seconds := extract(epoch from (v_now - v_in_time))::bigint;
  if v_op_seconds < 0 then
    v_op_seconds := 0;
  end if;

  v_was_active := (v_qr.warranty_expiry_timestamp is not null and v_now <= v_qr.warranty_expiry_timestamp);

  -- Close active cycle
  select * into v_cycle
  from public.bearing_installation_cycles
  where qr_code_id = v_qr.id
  order by cycle_number desc
  limit 1
  for update;

  if v_cycle.id is not null then
    update public.bearing_installation_cycles
    set
      out_timestamp = v_now,
      out_confirmed_by = v_user_id,
      out_verification_image_id = p_verification_image_id,
      operating_duration_seconds = v_op_seconds,
      was_warranty_active_at_out = v_was_active,
      is_cycle_closed = true,
      out_notes = p_notes,
      notes = coalesce(p_notes, notes),
      updated_at = v_now
    where id = v_cycle.id;
  end if;

  -- Decommission bearing
  update public.qr_codes
  set
    current_lifecycle_state = 'CURRENTLY_OUT',
    last_out_timestamp = v_now,
    assigned_customer_id = coalesce(v_user_id, assigned_customer_id),
    out_notes = coalesce(p_notes, out_notes),
    updated_at = v_now
  where id = v_qr.id;

  return jsonb_build_object(
    'success', true,
    'action', 'MARKED_OUT',
    'bearing_id', v_qr.bearing_id,
    'lifecycle_state', 'CURRENTLY_OUT',
    'in_timestamp', v_in_time,
    'out_timestamp', v_now,
    'operating_duration_seconds', v_op_seconds,
    'warranty_duration_months', v_qr.warranty_duration_months,
    'warranty_expiry', v_qr.warranty_expiry_timestamp,
    'was_warranty_active_at_out', v_was_active,
    'in_notes', coalesce(v_qr.in_notes, v_cycle.in_notes, v_cycle.notes),
    'out_notes', p_notes,
    'message', 'Bearing marked OUT and decommissioned.'
  );
end;
$$ language plpgsql security definer;

grant execute on function public.confirm_bearing_out(text, uuid, text) to authenticated, anon;

-- 5. Update get_bearing_lifecycle_summary to include in_notes and out_notes
create or replace function public.get_bearing_lifecycle_summary(
  p_scanned_payload text
)
returns jsonb as $$
declare
  v_clean text := trim(coalesce(p_scanned_payload, ''));
  v_qr record;
  v_batch record;
  v_plan record;
  v_cycle record;
  v_now timestamptz := clock_timestamp();
  v_dur integer := 12;
  v_in_time timestamptz;
  v_out_time timestamptz;
  v_expiry timestamptz;
  v_op_seconds bigint := 0;
  v_formatted_op text := 'Not installed';
  v_is_under_warranty boolean := false;
  v_rem_days integer := 0;
  v_status text;
begin
  if v_clean = '' then
    return jsonb_build_object('success', false, 'error', 'Payload is empty');
  end if;

  if v_clean ilike '%/pbi/%' then
    v_clean := split_part(split_part(v_clean, '/pbi/', 2), '?', 1);
  end if;

  select * into v_qr
  from public.qr_codes
  where bearing_id = v_clean
     or upper(bearing_id) = upper(v_clean)
     or payload_value = v_clean
     or upper(payload_value) = upper(v_clean)
  limit 1;

  if v_qr.id is null then
    return jsonb_build_object(
      'success', false,
      'error', 'Bearing record not found for ' || v_clean,
      'bearing_id', v_clean
    );
  end if;

  select * into v_batch
  from public.qr_batches
  where id = v_qr.batch_id;

  select * into v_plan
  from public.warranty_plans
  where id = coalesce(v_qr.assigned_warranty_plan_id, v_batch.default_warranty_plan_id);

  select * into v_cycle
  from public.bearing_installation_cycles
  where qr_code_id = v_qr.id
  order by cycle_number desc
  limit 1;

  v_dur := coalesce(v_qr.warranty_duration_months, v_plan.duration_months, 12);
  v_in_time := coalesce(v_qr.first_in_timestamp, v_cycle.in_timestamp);
  v_out_time := coalesce(v_qr.last_out_timestamp, v_cycle.out_timestamp);
  v_expiry := v_qr.warranty_expiry_timestamp;

  if v_in_time is not null and v_expiry is null then
    v_expiry := v_in_time + (v_dur || ' months')::interval;
  end if;

  if v_in_time is not null then
    if v_out_time is not null then
      v_op_seconds := extract(epoch from (v_out_time - v_in_time))::bigint;
    else
      v_op_seconds := extract(epoch from (v_now - v_in_time))::bigint;
    end if;
    if v_op_seconds < 0 then
      v_op_seconds := 0;
    end if;
    v_formatted_op := v_op_seconds || ' seconds';
  end if;

  if v_expiry is not null then
    if v_out_time is not null then
      v_is_under_warranty := (v_out_time <= v_expiry);
      v_rem_days := extract(day from (v_expiry - v_out_time))::int;
    else
      v_is_under_warranty := (v_now <= v_expiry);
      v_rem_days := extract(day from (v_expiry - v_now))::int;
    end if;
  else
    v_is_under_warranty := true;
    v_rem_days := v_dur * 30;
  end if;

  if v_qr.is_flagged = true then
    v_status := 'FLAGGED';
  elsif v_qr.current_lifecycle_state in ('CURRENTLY_OUT', 'FINAL_OUT', 'DECOMMISSIONED') then
    v_status := 'CURRENTLY_OUT';
  elsif v_qr.current_lifecycle_state = 'CURRENTLY_IN' then
    v_status := 'CURRENTLY_IN';
  else
    v_status := 'NOT_ACTIVATED';
  end if;

  return jsonb_build_object(
    'success', true,
    'bearing_id', v_qr.bearing_id,
    'batch_code', coalesce(v_batch.batch_code, 'BATCH-ACTIVE'),
    'plant_location', coalesce(v_batch.plant_location, 'Plant 02 — Chakan Industrial Complex'),
    'model_number', coalesce(v_qr.model_number, 'B1'),
    'product_name', 'Bearing 1(Ball Bearing)',
    'category', 'Ball Bearing',
    'warranty_duration_months', v_dur,
    'warranty_plan_title', coalesce(v_plan.title, v_dur || ' Months Industrial Warranty (' || v_dur || 'M)'),
    'current_lifecycle_state', v_status,
    'first_in_timestamp', v_in_time,
    'last_out_timestamp', v_out_time,
    'warranty_expiry_timestamp', v_expiry,
    'operating_duration_seconds', v_op_seconds,
    'operating_duration_formatted', v_formatted_op,
    'is_under_warranty', v_is_under_warranty,
    'remaining_warranty_days', coalesce(v_rem_days, 0),
    'can_mark_in', (v_status = 'NOT_ACTIVATED'),
    'can_mark_out', (v_status = 'CURRENTLY_IN'),
    'is_flagged', v_qr.is_flagged,
    'flag_reason', v_qr.flag_reason,
    'in_notes', coalesce(v_qr.in_notes, v_cycle.in_notes, v_cycle.notes),
    'out_notes', coalesce(v_qr.out_notes, v_cycle.out_notes)
  );
end;
$$ language plpgsql security definer;

grant execute on function public.get_bearing_lifecycle_summary(text) to authenticated, anon;

