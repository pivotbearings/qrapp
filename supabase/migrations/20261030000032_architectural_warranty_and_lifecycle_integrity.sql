-- Pivot Bearings India - Database Migration: 20261030000032_architectural_warranty_and_lifecycle_integrity.sql
-- Description: Eliminates the entire class of warranty duration defects permanently.
-- 1. Freezes warranty_duration_months directly on qr_codes.
-- 2. Single source of truth: Expiry is calculated ONCE on server at Mark IN and is IMMUTABLE.
-- 3. Drops all ambiguous overloads of verify_bearing_qr, confirm_bearing_in, confirm_bearing_out, generate_qr_batch.
-- 4. Shared authoritative get_bearing_lifecycle_summary RPC.
-- 5. Eliminates all phantom auto-creation on Mark IN/OUT.
-- 6. Repaired data for juVjDjzKJwY2, HWMOnqek2w4p, and all test records.

-- ==============================================================================
-- 1. Ensure public.warranty_plans has all standard tiers
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
-- 2. Schema Guard: Add and Freeze warranty_duration_months on qr_codes
-- ==============================================================================
-- Temporarily drop pre-existing triggers so backfill and data repair can run
drop trigger if exists trg_qr_codes_duration_guard on public.qr_codes;
drop trigger if exists trg_protect_qr_code_warranty on public.qr_codes;
drop trigger if exists trg_guard_qr_code_warranty on public.qr_codes;
drop trigger if exists trg_qr_codes_warranty_guard on public.qr_codes;
drop function if exists public.trg_qr_codes_duration_guard() cascade;
drop function if exists public.protect_qr_code_warranty_integrity() cascade;

do $$
begin
  if not exists (
    select 1 from information_schema.columns 
    where table_schema = 'public' and table_name = 'qr_codes' and column_name = 'warranty_duration_months'
  ) then
    alter table public.qr_codes add column warranty_duration_months integer;
  end if;

  if not exists (
    select 1 from information_schema.columns 
    where table_schema = 'public' and table_name = 'bearing_installation_cycles' and column_name = 'was_warranty_active_at_out'
  ) then
    alter table public.bearing_installation_cycles add column was_warranty_active_at_out boolean default true;
  end if;
end $$;

-- Backfill warranty_duration_months from assigned plan or batch plan
update public.qr_codes q
set warranty_duration_months = coalesce(
  (select p.duration_months from public.warranty_plans p where p.id = q.assigned_warranty_plan_id),
  (select bp.duration_months from public.qr_batches b join public.warranty_plans bp on bp.id = b.default_warranty_plan_id where b.id = q.batch_id),
  12
)
where q.warranty_duration_months is null;

-- Ensure not null default constraint
alter table public.qr_codes alter column warranty_duration_months set default 12;

-- ==============================================================================
-- 3. Stored Procedure: get_or_create_warranty_plan
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
-- 4. Drop ALL Ambiguous Overloads (Prevents PostgREST PGRST203 forever)
-- ==============================================================================
drop function if exists public.verify_bearing_qr(text, inet, text, text) cascade;
drop function if exists public.verify_bearing_qr(text, text, text, text) cascade;
drop function if exists public.verify_bearing_qr(text, text, text) cascade;
drop function if exists public.verify_bearing_qr(text, inet) cascade;
drop function if exists public.verify_bearing_qr(text, text) cascade;
drop function if exists public.verify_bearing_qr(text) cascade;

drop function if exists public.confirm_bearing_in(text, uuid, text, integer) cascade;
drop function if exists public.confirm_bearing_in(text, uuid, text) cascade;
drop function if exists public.confirm_bearing_in(text, uuid) cascade;
drop function if exists public.confirm_bearing_in(text) cascade;

drop function if exists public.confirm_bearing_out(text, uuid, text) cascade;
drop function if exists public.confirm_bearing_out(text, uuid) cascade;
drop function if exists public.confirm_bearing_out(text) cascade;

drop function if exists public.generate_qr_batch(text, text, integer, text, uuid, integer) cascade;
drop function if exists public.generate_qr_batch(text, text, integer, text, uuid) cascade;
drop function if exists public.generate_qr_batch(text, text, integer, text) cascade;
drop function if exists public.generate_qr_batch(text, text, integer) cascade;

drop function if exists public.get_bearing_lifecycle_summary(text) cascade;

drop function if exists public.track_bearing_scan(text, text) cascade;
drop function if exists public.track_bearing_scan(text) cascade;

-- ==============================================================================
-- 5. Unified Stored Procedure: generate_qr_batch (Freezes Duration on QR)
-- ==============================================================================
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
  v_duration integer := p_warranty_duration_months;
  v_generated_count integer := 0;
  v_max_attempts integer := p_quantity * 20;
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

  -- Resolve authoritative plan and frozen duration
  if v_duration is not null then
    v_plan_id := public.get_or_create_warranty_plan(v_duration);
  elsif v_plan_id is not null then
    select duration_months into v_duration from public.warranty_plans where id = v_plan_id;
    if v_duration is null then
      v_duration := 12;
    end if;
  else
    v_duration := 12;
    v_plan_id := public.get_or_create_warranty_plan(12);
  end if;

  -- Validate input consistency: plan duration must match supplied duration
  declare
    v_check_dur integer;
  begin
    select duration_months into v_check_dur from public.warranty_plans where id = v_plan_id;
    if v_check_dur is not null and v_check_dur != v_duration then
      raise exception 'Plan duration (%) contradicts supplied warranty duration (%).', v_check_dur, v_duration
        using errcode = '22023';
    end if;
  end;

  -- Create or retrieve batch
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

  -- Generation loop with frozen warranty_duration_months
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
        warranty_duration_months,
        current_lifecycle_state,
        is_flagged
      ) values (
        v_qr_value,
        v_batch_id,
        coalesce(p_model_number, 'B1'),
        v_qr_value,
        v_hash,
        v_plan_id,
        v_duration,
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
    'warranty_plan_id', v_plan_id,
    'warranty_duration_months', v_duration
  );
end;
$$ language plpgsql security definer;

grant execute on function public.generate_qr_batch(text, text, integer, text, uuid, integer) to authenticated, anon;

-- ==============================================================================
-- 6. Authoritative Shared Resolver: get_bearing_lifecycle_summary
-- Resolves bearing deterministically; computes exact duration and expiry once.
-- ==============================================================================
create or replace function public.get_bearing_lifecycle_summary(
  p_scanned_payload text
)
returns jsonb as $$
declare
  v_raw text := trim(coalesce(p_scanned_payload, ''));
  v_clean text := v_raw;
  v_matches_count integer := 0;
  v_qr record;
  v_batch record;
  v_plan record;
  v_dur integer;
  v_now timestamptz := clock_timestamp();
  v_in_time timestamptz;
  v_out_time timestamptz;
  v_expiry timestamptz;
  v_op_seconds bigint := 0;
  v_formatted_op text;
  v_days integer;
  v_hours integer;
  v_mins integer;
  v_secs integer;
  v_rem_days integer;
  v_is_under_warranty boolean := false;
  v_status text;
begin
  if v_raw = '' then
    raise exception 'Scanned payload or bearing identifier is required.' using errcode = '22023';
  end if;

  -- Strip URL prefixes
  if v_clean ilike '%/pbi/%' then
    v_clean := split_part(split_part(v_clean, '/pbi/', 2), '?', 1);
  elsif v_clean ilike '%/verify/%' then
    v_clean := split_part(split_part(v_clean, '/verify/', 2), '?', 1);
  elsif v_clean ilike 'http%://%' then
    v_clean := split_part(split_part(split_part(v_clean, '?', 1), '#', 1), '/', array_length(string_to_array(split_part(split_part(v_clean, '?', 1), '#', 1), '/'), 1));
  end if;
  v_clean := trim(v_clean);

  -- Step A: Exact Case-Sensitive Match
  select * into v_qr
  from public.qr_codes
  where bearing_id = v_clean or payload_value = v_clean
  limit 1;

  -- Step B: Exact Case-Insensitive Match (must be unique)
  if v_qr.id is null then
    select count(*) into v_matches_count
    from public.qr_codes
    where upper(bearing_id) = upper(v_clean) or upper(payload_value) = upper(v_clean);

    if v_matches_count > 1 then
      raise exception 'Ambiguous bearing identifier: multiple records match %.', v_clean
        using errcode = '21000';
    elsif v_matches_count = 1 then
      select * into v_qr
      from public.qr_codes
      where upper(bearing_id) = upper(v_clean) or upper(payload_value) = upper(v_clean)
      limit 1;
    end if;
  end if;

  -- Step C: Look-alike character tolerance (L vs I vs 1) only if exactly 1 match
  if v_qr.id is null then
    declare
      v_fuzzy_clean text := replace(replace(upper(v_clean), 'L', 'I'), '1', 'I');
    begin
      select count(*) into v_matches_count
      from public.qr_codes
      where replace(replace(upper(bearing_id), 'L', 'I'), '1', 'I') = v_fuzzy_clean;

      if v_matches_count = 1 then
        select * into v_qr
        from public.qr_codes
        where replace(replace(upper(bearing_id), 'L', 'I'), '1', 'I') = v_fuzzy_clean
        limit 1;
      end if;
    end;
  end if;

  -- Strict Guard: NO auto-creation!
  if v_qr.id is null then
    raise exception 'Bearing ID "%" not found in registry.', v_clean
      using errcode = 'P0002';
  end if;

  -- Load relations
  select * into v_batch from public.qr_batches where id = v_qr.batch_id;
  select * into v_plan from public.warranty_plans where id = v_qr.assigned_warranty_plan_id;

  -- Frozen Duration
  v_dur := coalesce(v_qr.warranty_duration_months, v_plan.duration_months, 12);
  v_in_time := coalesce(v_qr.last_in_timestamp, v_qr.first_in_timestamp);
  v_out_time := v_qr.last_out_timestamp;
  v_expiry := v_qr.warranty_expiry_timestamp;

  -- If activated but expiry was null, derive once
  if v_in_time is not null and v_expiry is null then
    v_expiry := v_in_time + (v_dur || ' months')::interval;
  end if;

  -- Operating Duration calculation
  if v_in_time is not null then
    if v_out_time is not null then
      v_op_seconds := extract(epoch from (v_out_time - v_in_time))::bigint;
    else
      v_op_seconds := extract(epoch from (v_now - v_in_time))::bigint;
    end if;
  else
    v_op_seconds := 0;
  end if;

  if v_op_seconds < 0 then
    v_op_seconds := 0;
  end if;

  v_days := (v_op_seconds / 86400)::int;
  v_hours := ((v_op_seconds % 86400) / 3600)::int;
  v_mins := ((v_op_seconds % 3600) / 60)::int;
  v_secs := (v_op_seconds % 60)::int;

  if v_op_seconds < 60 then
    v_formatted_op := v_secs || ' Secs';
  elsif v_op_seconds < 3600 then
    v_formatted_op := v_mins || ' Mins, ' || v_secs || ' Secs';
  elsif v_op_seconds < 86400 then
    v_formatted_op := v_hours || ' Hours, ' || v_mins || ' Mins, ' || v_secs || ' Secs';
  else
    v_formatted_op := v_days || ' Days, ' || v_hours || ' Hours, ' || v_mins || ' Mins';
  end if;

  -- Warranty status evaluated against OUT timestamp if decommissioned, or NOW if active
  if v_expiry is not null then
    if v_qr.current_lifecycle_state in ('CURRENTLY_OUT', 'FINAL_OUT', 'DECOMMISSIONED') and v_out_time is not null then
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
    'product_name', coalesce(v_batch.batch_code, 'Bearing 1(Ball Bearing)'),
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
    'flag_reason', v_qr.flag_reason
  );
end;
$$ language plpgsql security definer;

grant execute on function public.get_bearing_lifecycle_summary(text) to authenticated, anon;

-- ==============================================================================
-- 7. Stored Procedure: verify_bearing_qr (Single Clean Signature)
-- ==============================================================================
create or replace function public.verify_bearing_qr(
  p_scanned_payload text,
  p_ip_address text default null,
  p_user_agent text default null,
  p_device_info text default null
)
returns jsonb as $$
declare
  v_summary jsonb;
begin
  begin
    v_summary := public.get_bearing_lifecycle_summary(p_scanned_payload);
  exception when others then
    return jsonb_build_object(
      'status', 'NOT_FOUND',
      'error_code', 'NOT_FOUND',
      'message', SQLERRM
    );
  end;

  return jsonb_build_object(
    'status', case 
      when (v_summary->>'is_flagged')::boolean then 'FLAGGED'
      when (v_summary->>'current_lifecycle_state') = 'CURRENTLY_OUT' then 'DECOMMISSIONED'
      when (v_summary->>'current_lifecycle_state') = 'NOT_ACTIVATED' then 'VALID_NOT_ACTIVATED'
      when not (v_summary->>'is_under_warranty')::boolean then 'WARRANTY_EXPIRED'
      else 'VALID_WARRANTY_ACTIVE'
    end,
    'bearing_id', v_summary->>'bearing_id',
    'batch_code', v_summary->>'batch_code',
    'plant_location', v_summary->>'plant_location',
    'model_number', v_summary->>'model_number',
    'category', v_summary->>'category',
    'product_name', v_summary->>'product_name',
    'warranty_plan_title', v_summary->>'warranty_plan_title',
    'duration_months', (v_summary->>'warranty_duration_months')::integer,
    'warranty_duration_months', (v_summary->>'warranty_duration_months')::integer,
    'current_lifecycle_state', v_summary->>'current_lifecycle_state',
    'first_in_timestamp', v_summary->>'first_in_timestamp',
    'last_out_timestamp', v_summary->>'last_out_timestamp',
    'warranty_expiry_timestamp', v_summary->>'warranty_expiry_timestamp',
    'is_expired', not (v_summary->>'is_under_warranty')::boolean,
    'can_mark_in', (v_summary->>'can_mark_in')::boolean,
    'can_mark_out', (v_summary->>'can_mark_out')::boolean,
    'operating_duration_formatted', v_summary->>'operating_duration_formatted',
    'message', 'Authentic Pivot Bearing. Registry record verified.'
  );
end;
$$ language plpgsql security definer;

grant execute on function public.verify_bearing_qr(text, text, text, text) to authenticated, anon;

-- ==============================================================================
-- 8. Stored Procedure: confirm_bearing_in (Immutable Expiry Calculation)
-- ==============================================================================
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
  v_expiry timestamptz;
  v_clean text := trim(coalesce(p_bearing_id, ''));
  v_dur integer;
  v_next_cycle integer;
begin
  if v_clean = '' then
    raise exception 'Bearing ID is required.' using errcode = '22023';
  end if;

  -- Normalize URL
  if v_clean ilike '%/pbi/%' then
    v_clean := split_part(split_part(v_clean, '/pbi/', 2), '?', 1);
  end if;

  -- 1. Locate registered bearing (No auto-creation!)
  select * into v_qr
  from public.qr_codes
  where bearing_id = v_clean
     or upper(bearing_id) = upper(v_clean)
     or payload_value = v_clean
     or upper(payload_value) = upper(v_clean)
  limit 1
  for update;

  if v_qr.id is null then
    raise exception 'Bearing % is not registered in system. Activation rejected.', v_clean
      using errcode = 'P0002';
  end if;

  if v_qr.is_flagged = true then
    raise exception 'Bearing % is flagged for security inspection: %', v_qr.bearing_id, coalesce(v_qr.flag_reason, 'Manual hold')
      using errcode = '55000';
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
      'warranty_duration_months', v_qr.warranty_duration_months
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
    updated_at = v_now
  where id = v_qr.id;

  select coalesce(max(cycle_number), 0) + 1 into v_next_cycle
  from public.bearing_installation_cycles
  where qr_code_id = v_qr.id;

  insert into public.bearing_installation_cycles (
    qr_code_id, cycle_number, in_timestamp, in_confirmed_by, in_verification_image_id, notes, updated_at
  ) values (
    v_qr.id, v_next_cycle, v_now, v_user_id, p_verification_image_id, p_notes, v_now
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
    'message', 'Bearing marked IN. Operational warranty activated.'
  );
end;
$$ language plpgsql security definer;

grant execute on function public.confirm_bearing_in(text, uuid, text) to authenticated, anon;

-- ==============================================================================
-- 9. Stored Procedure: confirm_bearing_out (Immutable Duration & Exact Timing)
-- ==============================================================================
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
      'warranty_duration_months', v_qr.warranty_duration_months
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
    'message', 'Bearing marked OUT and decommissioned.'
  );
end;
$$ language plpgsql security definer;

grant execute on function public.confirm_bearing_out(text, uuid, text) to authenticated, anon;

-- ==============================================================================
-- 9B. Stored Procedure: track_bearing_scan (Accurate Timing & Lifecycle Integrity)
-- ==============================================================================
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

  -- 1. TERMINAL STATE: If already marked OUT / decommissioned, block re-scanning and forbid Cycle 2
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
      'cycle_number', v_next_cycle,
      'in_timestamp', v_now,
      'message', 'Bearing In recorded successfully. Tracking started.',
      'notes', p_notes,
      'lifecycle_history', v_history
    );
  end if;
end;
$$ language plpgsql security definer;

grant execute on function public.track_bearing_scan(text, text) to authenticated, anon;

-- ==============================================================================
-- 10. Data Repair: Repair juVjDjzKJwY2, HWMOnqek2w4p, FKUAiJWaEgIh, and Existing QRs
-- (Executed before attaching immutability trigger)
-- ==============================================================================
-- Backfill frozen duration from assigned plans
update public.qr_codes q
set warranty_duration_months = coalesce(
  (select p.duration_months from public.warranty_plans p where p.id = q.assigned_warranty_plan_id),
  12
)
where q.assigned_warranty_plan_id is not null;

-- Specifically Repair juVjDjzKJwY2
update public.qr_codes
set
  warranty_duration_months = 36,
  assigned_warranty_plan_id = '66666666-6666-6666-6666-666666666666',
  first_in_timestamp = '2026-10-29 20:10:44+00',
  last_in_timestamp = '2026-10-29 20:10:44+00',
  last_out_timestamp = '2026-10-29 20:12:42.999121+00',
  warranty_expiry_timestamp = '2029-10-29 20:10:44+00',
  current_lifecycle_state = 'CURRENTLY_OUT',
  updated_at = now()
where bearing_id = 'juVjDjzKJwY2' or upper(bearing_id) = 'JUVJDJZKJWY2';

-- Repair HWMOnqek2w4p
update public.qr_codes
set
  warranty_duration_months = 24,
  assigned_warranty_plan_id = '55555555-5555-5555-5555-555555555555',
  warranty_expiry_timestamp = coalesce(first_in_timestamp, now()) + interval '24 months',
  updated_at = now()
where bearing_id ilike '%HWMOnqek2w4p%';

-- Repair FKUAiJWaEgIh
update public.qr_codes
set
  warranty_duration_months = 36,
  assigned_warranty_plan_id = '66666666-6666-6666-6666-666666666666',
  warranty_expiry_timestamp = coalesce(first_in_timestamp, now()) + interval '36 months',
  updated_at = now()
where bearing_id ilike '%FKUAiJWaEgIh%' or bearing_id ilike '%FKUAIJWAEGLH%';

-- ==============================================================================
-- 11. Database Guard Triggers: Protect Frozen Duration, Immutability & Prohibit Cycle 2
-- ==============================================================================
create or replace function public.protect_qr_code_warranty_integrity()
returns trigger as $$
begin
  -- Prevent altering frozen duration
  if tg_op = 'UPDATE' and old.warranty_duration_months is not null then
    if new.warranty_duration_months != old.warranty_duration_months then
      raise exception 'Illegal operation: warranty_duration_months is immutable once frozen on bearing %.', old.bearing_id
        using errcode = '55000';
    end if;
  end if;

  -- Prevent altering expiry once set (except if previously null)
  if tg_op = 'UPDATE' and old.warranty_expiry_timestamp is not null then
    if new.warranty_expiry_timestamp != old.warranty_expiry_timestamp then
      raise exception 'Illegal operation: warranty_expiry_timestamp is immutable once activated on bearing %.', old.bearing_id
        using errcode = '55000';
    end if;
  end if;

  -- Strictly prohibit re-activating / restarting a decommissioned bearing (Cycle 2 Forbidden)
  if tg_op = 'UPDATE' and old.current_lifecycle_state in ('CURRENTLY_OUT', 'FINAL_OUT', 'DECOMMISSIONED') then
    if new.current_lifecycle_state = 'CURRENTLY_IN' then
      raise exception 'Terminal lifecycle violation: Bearing % is permanently decommissioned. Re-installation and Cycle 2 are strictly prohibited.', old.bearing_id
        using errcode = '55000';
    end if;
  end if;

  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_protect_qr_code_warranty on public.qr_codes;
create trigger trg_protect_qr_code_warranty
  before update on public.qr_codes
  for each row
  execute function public.protect_qr_code_warranty_integrity();

-- Guard against Cycle 2 insertion on bearing_installation_cycles
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

drop trigger if exists trg_prevent_duplicate_cycles on public.bearing_installation_cycles;
create trigger trg_prevent_duplicate_cycles
  before insert on public.bearing_installation_cycles
  for each row
  execute function public.trg_prevent_cycle_two_insert();
