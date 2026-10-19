-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261012000019_track_bearing_lifecycle.sql
-- "Track Your Bearing" Module: Seamless QR-Only IN/OUT Lifecycle State Machine
-- ==============================================================================

-- 1. Ensure bearing_installation_cycles allows standalone tracking without proof images
alter table public.bearing_installation_cycles 
alter column in_confirmed_by drop not null;

alter table public.bearing_installation_cycles 
add column if not exists last_cycle_note text;

-- Add last_in_timestamp to qr_codes if not present
alter table public.qr_codes 
add column if not exists last_in_timestamp timestamptz;

-- 2. Stored Procedure: track_bearing_scan
-- QR-only authoritative IN/OUT lifecycle tracking:
-- - First scan when not in use: records Bearing In entry timestamp, sets CURRENTLY_IN
-- - Subsequent scan when in use: records Bearing Out exit timestamp, sets CURRENTLY_OUT, calculates usage duration
-- - Repeated usage: allows beginning a new cycle, preserving historical completed cycles
create or replace function public.track_bearing_scan(
  p_scanned_payload text
)
returns jsonb as $$
declare
  v_trimmed text := trim(coalesce(p_scanned_payload, ''));
  v_bearing_id text;
  v_user_id uuid := auth.uid();
  v_qr record;
  v_batch record;
  v_plan record;
  v_active_cycle record;
  v_now timestamptz := now();
  v_next_cycle integer := 1;
  v_new_cycle_id uuid;
  v_duration_interval interval;
  v_duration_seconds bigint;
  v_history jsonb := '[]'::jsonb;
begin
  -- 1. Payload validation
  if v_trimmed = '' then
    return jsonb_build_object(
      'is_valid', false,
      'status', 'INVALID',
      'message', 'Scanned payload is empty.'
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

  -- 3. Lookup QR Code in Authoritative Registry with Row Lock
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
    q.last_in_timestamp,
    q.is_flagged,
    q.flag_reason
  into v_qr
  from public.qr_codes q
  where q.bearing_id = v_bearing_id 
     or q.payload_value = v_trimmed 
     or q.payload_value = v_bearing_id
  for update;

  if not found then
    return jsonb_build_object(
      'is_valid', false,
      'status', 'NOT_FOUND',
      'scanned_id', v_bearing_id,
      'message', 'Bearing Authenticity Could Not Be Verified. Unregistered code.'
    );
  end if;

  -- Resolve Batch and Warranty Plan info
  select * into v_batch from public.qr_batches where id = v_qr.batch_id;
  select * into v_plan from public.warranty_plans where id = coalesce(v_qr.assigned_warranty_plan_id, v_qr.warranty_plan_id);

  -- 4. STATE TRANSITION DECISION:
  -- If currently CURRENTLY_IN -> Execute BEARING OUT
  -- If NOT_ACTIVATED or CURRENTLY_OUT -> Execute BEARING IN
  if v_qr.current_lifecycle_state = 'CURRENTLY_IN' then
    -- =========================================================================
    -- ACTION: BEARING OUT
    -- =========================================================================
    -- Locate active open cycle
    select * into v_active_cycle
    from public.bearing_installation_cycles
    where qr_code_id = v_qr.id and is_cycle_closed = false
    order by cycle_number desc
    limit 1;

    if not found then
      -- Fallback: Use last_in_timestamp if cycle record was missing
      v_duration_interval := v_now - coalesce(v_qr.last_in_timestamp, v_qr.first_in_timestamp, v_now);
      v_duration_seconds := extract(epoch from v_duration_interval)::bigint;

      -- Create and immediately close cycle
      select coalesce(max(cycle_number), 0) + 1 into v_next_cycle
      from public.bearing_installation_cycles
      where qr_code_id = v_qr.id;

      insert into public.bearing_installation_cycles (
        qr_code_id,
        cycle_number,
        in_timestamp,
        in_confirmed_by,
        out_timestamp,
        out_confirmed_by,
        operating_duration_interval,
        operating_duration_seconds,
        is_cycle_closed
      ) values (
        v_qr.id,
        v_next_cycle,
        coalesce(v_qr.last_in_timestamp, v_qr.first_in_timestamp, v_now),
        v_user_id,
        v_now,
        v_user_id,
        v_duration_interval,
        v_duration_seconds,
        true
      );
    else
      -- Close active cycle
      v_duration_interval := v_now - v_active_cycle.in_timestamp;
      v_duration_seconds := extract(epoch from v_duration_interval)::bigint;
      v_next_cycle := v_active_cycle.cycle_number;

      update public.bearing_installation_cycles
      set out_timestamp = v_now,
          out_confirmed_by = v_user_id,
          operating_duration_interval = v_duration_interval,
          operating_duration_seconds = v_duration_seconds,
          is_cycle_closed = true,
          updated_at = v_now
      where id = v_active_cycle.id;
    end if;

    -- Update QR Code status to CURRENTLY_OUT (ready for future re-installation)
    update public.qr_codes
    set current_lifecycle_state = 'CURRENTLY_OUT',
        updated_at = v_now
    where id = v_qr.id;

    -- Collect all completed lifecycle history
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
      'lifecycle_history', v_history
    );

  else
    -- =========================================================================
    -- ACTION: BEARING IN
    -- =========================================================================
    -- Calculate next cycle number
    select coalesce(max(cycle_number), 0) + 1 into v_next_cycle
    from public.bearing_installation_cycles
    where qr_code_id = v_qr.id;

    -- Insert new open cycle
    insert into public.bearing_installation_cycles (
      qr_code_id,
      cycle_number,
      in_timestamp,
      in_confirmed_by,
      is_cycle_closed
    ) values (
      v_qr.id,
      v_next_cycle,
      v_now,
      v_user_id,
      false
    ) returning id into v_new_cycle_id;

    -- Update QR Code status to CURRENTLY_IN
    update public.qr_codes
    set current_lifecycle_state = 'CURRENTLY_IN',
        first_in_timestamp = coalesce(first_in_timestamp, v_now),
        last_in_timestamp = v_now,
        updated_at = v_now
    where id = v_qr.id;

    -- Collect previous completed lifecycle history
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
      'message', 'Bearing In recorded successfully. Usage tracking has started.',
      'lifecycle_history', v_history
    );
  end if;
end;
$$ language plpgsql security definer;

-- 3. Grants for Execution
grant execute on function public.track_bearing_scan(text) to authenticated, anon;
grant select, insert, update on public.bearing_installation_cycles to authenticated;
