-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261030000033_strictly_prohibit_cycle_two.sql
-- Description: Strictly prohibits starting Cycle 2 in Track Your Bearing and Warranty modules.
-- Once a bearing is marked OUT, it is permanently decommissioned and can never be marked IN again.
-- ==============================================================================

-- 1. Trigger on qr_codes: Block transitioning from CURRENTLY_OUT to CURRENTLY_IN
create or replace function public.trg_guard_qr_lifecycle_single_use()
returns trigger as $$
begin
  if tg_op = 'UPDATE' and old.current_lifecycle_state in ('CURRENTLY_OUT', 'FINAL_OUT', 'DECOMMISSIONED') then
    if new.current_lifecycle_state = 'CURRENTLY_IN' then
      raise exception 'Terminal lifecycle violation: Bearing % is permanently decommissioned. Re-installation and Cycle 2 are strictly prohibited.', old.bearing_id
        using errcode = '55000';
    end if;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_guard_qr_lifecycle_single_use on public.qr_codes cascade;
create trigger trg_guard_qr_lifecycle_single_use
  before update on public.qr_codes
  for each row
  execute function public.trg_guard_qr_lifecycle_single_use();

-- 2. Trigger on bearing_installation_cycles: Block inserting Cycle 2
create or replace function public.trg_prevent_cycle_two_insert()
returns trigger as $$
begin
  if new.cycle_number > 1 then
    raise exception 'Terminal lifecycle violation: Bearing % cannot have cycle %. Once marked OUT, re-installation is strictly prohibited.',
      new.qr_code_id, new.cycle_number
      using errcode = '55000';
  end if;

  if exists (
    select 1 from public.bearing_installation_cycles 
    where qr_code_id = new.qr_code_id and id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) then
    raise exception 'Terminal lifecycle violation: Bearing % already has an installation cycle. A second cycle is strictly prohibited.',
      new.qr_code_id
      using errcode = '55000';
  end if;

  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_prevent_duplicate_cycles on public.bearing_installation_cycles cascade;
create trigger trg_prevent_duplicate_cycles
  before insert on public.bearing_installation_cycles
  for each row
  execute function public.trg_prevent_cycle_two_insert();

-- 3. Authoritative track_bearing_scan RPC with zero tolerance for Cycle 2
drop function if exists public.track_bearing_scan(text, text) cascade;
drop function if exists public.track_bearing_scan(text) cascade;

create or replace function public.track_bearing_scan(
  p_scanned_payload text,
  p_notes text default null
)
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_raw text := trim(coalesce(p_scanned_payload, ''));
  v_bearing_id text := v_raw;
  v_now timestamptz := clock_timestamp();
  v_qr record;
  v_batch record;
  v_item record;
  v_default_batch_id uuid;
  v_default_plan_id uuid;
  v_active_cycle record;
  v_next_cycle int;
  v_duration_seconds bigint := 0;
  v_duration_interval interval;
  v_history jsonb := '[]'::jsonb;
begin
  if v_raw = '' then
    return jsonb_build_object('is_valid', false, 'status', 'INVALID', 'message', 'Empty payload.');
  end if;

  if v_bearing_id ilike '%/pbi/%' then
    v_bearing_id := split_part(split_part(v_bearing_id, '/pbi/', 2), '?', 1);
  elsif v_bearing_id ilike '%/verify/%' then
    v_bearing_id := split_part(split_part(v_bearing_id, '/verify/', 2), '?', 1);
  elsif v_bearing_id ilike 'http%://%' then
    v_bearing_id := split_part(split_part(split_part(v_bearing_id, '?', 1), '#', 1), '/', array_length(string_to_array(split_part(split_part(v_bearing_id, '?', 1), '#', 1), '/'), 1));
  end if;
  v_bearing_id := trim(v_bearing_id);

  select * into v_qr
  from public.qr_codes q
  where q.bearing_id = v_bearing_id 
     or q.payload_value = v_raw 
     or q.payload_value = v_bearing_id
     or upper(q.bearing_id) = upper(v_bearing_id)
     or upper(q.payload_value) = upper(v_raw)
  order by
    case when q.bearing_id = v_bearing_id then 0
         when upper(q.bearing_id) = upper(v_bearing_id) then 1
         else 2 end
  limit 1
  for update;

  if not found then
    select id into v_default_batch_id from public.qr_batches order by created_at desc limit 1;
    select id into v_default_plan_id from public.warranty_plans where duration_months = 12 limit 1;
    if v_default_plan_id is null then
      select id into v_default_plan_id from public.warranty_plans order by duration_months desc limit 1;
    end if;

    insert into public.qr_codes (
      bearing_id,
      batch_id,
      model_number,
      payload_value,
      payload_hash,
      assigned_warranty_plan_id,
      warranty_duration_months,
      current_lifecycle_state,
      assigned_customer_id,
      is_flagged
    ) values (
      v_bearing_id,
      coalesce(v_default_batch_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid),
      'B1',
      v_raw,
      'SHA-256: VALID',
      coalesce(v_default_plan_id, '33333333-3333-3333-3333-333333333333'::uuid),
      12,
      'NOT_ACTIVATED',
      v_user_id,
      false
    )
    on conflict (bearing_id) do update set
      payload_value = excluded.payload_value,
      assigned_customer_id = coalesce(qr_codes.assigned_customer_id, excluded.assigned_customer_id)
    returning * into v_qr;
  end if;

  select * into v_batch from public.qr_batches where id = v_qr.batch_id;
  select * into v_item from public.bearing_items where item_code = v_qr.model_number;

  -- 1. TERMINAL STATE: If already marked OUT / decommissioned, block re-scanning and strictly forbid Cycle 2
  if v_qr.current_lifecycle_state in ('CURRENTLY_OUT', 'FINAL_OUT', 'DECOMMISSIONED')
     or v_qr.last_out_timestamp is not null
     or exists (select 1 from public.bearing_installation_cycles where qr_code_id = v_qr.id and (is_cycle_closed = true or out_timestamp is not null))
  then
    v_duration_seconds := extract(epoch from (coalesce(v_qr.last_out_timestamp, v_now) - coalesce(v_qr.first_in_timestamp, v_now)))::bigint;
    if v_duration_seconds < 0 then
      v_duration_seconds := 0;
    end if;

    return jsonb_build_object(
      'is_valid', true,
      'action', 'ALREADY_OUT',
      'bearing_id', v_qr.bearing_id,
      'model_number', coalesce(v_qr.model_number, 'B1'),
      'category', coalesce(v_item.category, 'Ball Bearing'),
      'product_name', coalesce(v_item.item_name, 'Bearing 1(Ball Bearing)'),
      'batch_code', coalesce(v_batch.batch_code, 'N/A'),
      'plant_location', coalesce(v_batch.plant_location, 'Pivot Bearings India Plant'),
      'in_timestamp', v_qr.first_in_timestamp,
      'out_timestamp', v_qr.last_out_timestamp,
      'duration_seconds', v_duration_seconds,
      'duration_days', floor(v_duration_seconds / 86400),
      'duration_hours', floor((v_duration_seconds % 86400) / 3600),
      'duration_minutes', floor((v_duration_seconds % 3600) / 60),
      'message', 'This bearing has already completed its lifecycle and is permanently decommissioned. Cycle 2 is strictly prohibited.'
    );
  end if;

  -- 2. ACTIVE IN: Mark bearing OUT and close active cycle
  if v_qr.current_lifecycle_state = 'CURRENTLY_IN' then
    select * into v_active_cycle
    from public.bearing_installation_cycles
    where qr_code_id = v_qr.id and is_cycle_closed = false
    order by cycle_number desc
    limit 1
    for update;

    if not found then
      v_duration_interval := v_now - coalesce(v_qr.last_in_timestamp, v_qr.first_in_timestamp, v_now);
      v_duration_seconds := extract(epoch from v_duration_interval)::bigint;
      if v_duration_seconds < 0 then v_duration_seconds := 0; end if;

      v_next_cycle := 1;

      insert into public.bearing_installation_cycles (
        qr_code_id, cycle_number, in_timestamp, in_confirmed_by,
        out_timestamp, out_confirmed_by, operating_duration_interval,
        operating_duration_seconds, is_cycle_closed, notes
      ) values (
        v_qr.id, 1, coalesce(v_qr.last_in_timestamp, v_qr.first_in_timestamp, v_now),
        v_user_id, v_now, v_user_id, v_duration_interval, v_duration_seconds, true, p_notes
      );
    else
      v_duration_interval := v_now - v_active_cycle.in_timestamp;
      v_duration_seconds := extract(epoch from v_duration_interval)::bigint;
      if v_duration_seconds < 0 then v_duration_seconds := 0; end if;
      v_next_cycle := v_active_cycle.cycle_number;

      update public.bearing_installation_cycles
      set out_timestamp = v_now,
          out_confirmed_by = v_user_id,
          operating_duration_interval = v_duration_interval,
          operating_duration_seconds = v_duration_seconds,
          is_cycle_closed = true,
          notes = coalesce(notes, '') || case when p_notes is not null and p_notes <> '' then ' | Out: ' || p_notes else '' end,
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
      'model_number', coalesce(v_qr.model_number, 'B1'),
      'category', coalesce(v_item.category, 'Ball Bearing'),
      'product_name', coalesce(v_item.item_name, 'Bearing 1(Ball Bearing)'),
      'batch_code', coalesce(v_batch.batch_code, 'N/A'),
      'plant_location', coalesce(v_batch.plant_location, 'Pivot Bearings India Plant'),
      'cycle_number', v_next_cycle,
      'in_timestamp', coalesce(v_active_cycle.in_timestamp, v_qr.last_in_timestamp, v_now),
      'out_timestamp', v_now,
      'duration_seconds', v_duration_seconds,
      'duration_days', floor(v_duration_seconds / 86400),
      'duration_hours', floor((v_duration_seconds % 86400) / 3600),
      'duration_minutes', floor((v_duration_seconds % 3600) / 60),
      'message', 'Bearing Out recorded successfully. Bearing is now decommissioned.',
      'notes', coalesce(v_active_cycle.notes, p_notes),
      'lifecycle_history', v_history
    );
  else
    -- 3. NOT ACTIVATED: Strictly prohibit Cycle 2 (Only Cycle 1 allowed)
    if exists (select 1 from public.bearing_installation_cycles where qr_code_id = v_qr.id)
       or v_qr.first_in_timestamp is not null
       or v_qr.last_out_timestamp is not null
       or v_qr.current_lifecycle_state != 'NOT_ACTIVATED'
    then
      return jsonb_build_object(
        'is_valid', true,
        'action', 'ALREADY_OUT',
        'bearing_id', v_qr.bearing_id,
        'model_number', coalesce(v_qr.model_number, 'B1'),
        'category', coalesce(v_item.category, 'Ball Bearing'),
        'product_name', coalesce(v_item.item_name, 'Bearing 1(Ball Bearing)'),
        'in_timestamp', v_qr.first_in_timestamp,
        'out_timestamp', v_qr.last_out_timestamp,
        'message', 'Terminal lifecycle violation: Bearing has already completed Cycle 1. Cycle 2 is strictly prohibited.'
      );
    end if;

    insert into public.bearing_installation_cycles (
      qr_code_id, cycle_number, in_timestamp, in_confirmed_by, is_cycle_closed, notes
    ) values (
      v_qr.id, 1, v_now, v_user_id, false, p_notes
    );

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
      'model_number', coalesce(v_qr.model_number, 'B1'),
      'category', coalesce(v_item.category, 'Ball Bearing'),
      'product_name', coalesce(v_item.item_name, 'Bearing 1(Ball Bearing)'),
      'batch_code', coalesce(v_batch.batch_code, 'N/A'),
      'plant_location', coalesce(v_batch.plant_location, 'Pivot Bearings India Plant'),
      'cycle_number', 1,
      'in_timestamp', v_now,
      'message', 'Bearing In recorded successfully. Tracking started.',
      'notes', p_notes,
      'lifecycle_history', v_history
    );
  end if;
end;
$$ language plpgsql security definer;

grant execute on function public.track_bearing_scan(text, text) to authenticated, anon;

