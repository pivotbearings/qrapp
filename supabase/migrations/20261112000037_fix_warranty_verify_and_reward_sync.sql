-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261112000037_fix_warranty_verify_and_reward_sync.sql
-- Fixes URL/special-character extraction & NOT_FOUND status handling in
-- get_bearing_lifecycle_summary / verify_bearing_qr and hardens claim_bearing_scan_reward.
-- ==============================================================================

-- 1. Shared URL / Bearing ID normalizer (matches Flutter _extractBearingId behavior)
create or replace function public._pbi_extract_bearing_id(p_raw text)
returns text as $$
declare
  v_clean text := trim(coalesce(p_raw, ''));
begin
  if v_clean = '' then
    return '';
  end if;

  if v_clean ilike '%/pbi/%' then
    v_clean := split_part(split_part(split_part(split_part(v_clean, '/pbi/', 2), '?', 1), '&', 1), '#', 1);
  elsif v_clean ilike '%/verify/%' then
    v_clean := split_part(split_part(split_part(split_part(v_clean, '/verify/', 2), '?', 1), '&', 1), '#', 1);
  elsif v_clean ilike 'http%://%' then
    v_clean := split_part(split_part(split_part(v_clean, '?', 1), '&', 1), '#', 1);
    v_clean := rtrim(v_clean, '/');
    v_clean := split_part(v_clean, '/', array_length(string_to_array(v_clean, '/'), 1));
  end if;

  v_clean := rtrim(trim(v_clean), '/');
  v_clean := replace(v_clean, '%23', '#');
  v_clean := replace(v_clean, '%5D', ']');
  v_clean := replace(v_clean, '%5d', ']');
  v_clean := replace(v_clean, '%5B', '[');
  v_clean := replace(v_clean, '%5b', '[');
  v_clean := replace(v_clean, '%20', ' ');
  v_clean := replace(v_clean, '%2A', '*');
  v_clean := replace(v_clean, '%2a', '*');
  v_clean := replace(v_clean, '%40', '@');
  v_clean := replace(v_clean, '%24', '$');
  v_clean := replace(v_clean, '%2B', '+');
  v_clean := replace(v_clean, '%2b', '+');
  return trim(v_clean);
end;
$$ language plpgsql immutable;

-- 2. Fix get_bearing_lifecycle_summary to decode URLs, support look-alikes, and keep all notes
create or replace function public.get_bearing_lifecycle_summary(
  p_scanned_payload text
)
returns jsonb as $$
declare
  v_raw text := trim(coalesce(p_scanned_payload, ''));
  v_clean text := public._pbi_extract_bearing_id(v_raw);
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
  if v_raw = '' or v_clean = '' then
    return jsonb_build_object('success', false, 'error', 'Payload is empty');
  end if;

  select * into v_qr
  from public.qr_codes
  where bearing_id = v_clean
     or bearing_id = v_raw
     or upper(bearing_id) = upper(v_clean)
     or payload_value = v_raw
     or payload_value = v_clean
     or upper(payload_value) = upper(v_raw)
     or upper(payload_value) = upper(v_clean)
  limit 1;

  if v_qr.id is null then
    select * into v_qr
    from public.qr_codes
    where replace(replace(upper(trim(bearing_id)), 'L', 'I'), '1', 'I') = replace(replace(upper(v_clean), 'L', 'I'), '1', 'I')
       or replace(replace(upper(trim(payload_value)), 'L', 'I'), '1', 'I') = replace(replace(upper(v_clean), 'L', 'I'), '1', 'I')
    limit 1;
  end if;

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

  if coalesce(v_qr.is_flagged, false) then
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
    'is_flagged', coalesce(v_qr.is_flagged, false),
    'flag_reason', v_qr.flag_reason,
    'in_notes', coalesce(v_qr.in_notes, v_cycle.in_notes, v_cycle.notes),
    'out_notes', coalesce(v_qr.out_notes, v_cycle.out_notes)
  );
end;
$$ language plpgsql security definer;

-- 3. Drop any previous overloads of verify_bearing_qr & recreate cleanly
do $$
declare
  r record;
begin
  for r in (
    select oid::regprocedure as func_signature
    from pg_proc
    where proname in ('verify_bearing_qr', 'claim_bearing_scan_reward')
      and pronamespace = 'public'::regnamespace
  ) loop
    execute 'drop function if exists ' || r.func_signature || ' cascade;';
  end loop;
end $$;

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
  v_summary := public.get_bearing_lifecycle_summary(p_scanned_payload);

  if coalesce((v_summary->>'success')::boolean, false) = false then
    return jsonb_build_object(
      'status', 'NOT_FOUND',
      'error_code', 'NOT_FOUND',
      'message', coalesce(v_summary->>'error', 'Cryptographic identifier not registered with Pivot Bearings India.')
    );
  end if;

  return jsonb_build_object(
    'status', case
      when coalesce((v_summary->>'is_flagged')::boolean, false) then 'FLAGGED'
      when (v_summary->>'current_lifecycle_state') = 'CURRENTLY_OUT' then 'DECOMMISSIONED'
      when (v_summary->>'current_lifecycle_state') = 'NOT_ACTIVATED' then 'VALID_NOT_ACTIVATED'
      when not coalesce((v_summary->>'is_under_warranty')::boolean, true) then 'WARRANTY_EXPIRED'
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
    'is_expired', not coalesce((v_summary->>'is_under_warranty')::boolean, true),
    'can_mark_in', coalesce((v_summary->>'can_mark_in')::boolean, false),
    'can_mark_out', coalesce((v_summary->>'can_mark_out')::boolean, false),
    'operating_duration_formatted', v_summary->>'operating_duration_formatted',
    'message', 'Authentic Pivot Bearing. Registry record verified.'
  );
end;
$$ language plpgsql security definer;

-- 4. Harden claim_bearing_scan_reward with shared URL/percent normalizer
create or replace function public.claim_bearing_scan_reward(
  p_bearing_id text,
  p_source_module text default 'AUTHENTICATE_BEARING',
  p_supplier_name text default null,
  p_supplier_contact text default null
)
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_trimmed text := trim(coalesce(p_bearing_id, ''));
  v_bearing_clean text := public._pbi_extract_bearing_id(v_trimmed);
  v_qr record;
  v_settings record;
  v_pts integer;
  v_base_unit integer;
  v_inr_per_base numeric(10, 2);
  v_amount_inr numeric(10, 2);
  v_rate_multiplier numeric(10, 4);
  v_today_start timestamptz := date_trunc('day', now());
  v_scans_today integer := 0;
  v_now timestamptz := now();
  v_new_balance integer := 0;
  v_is_eligible boolean := true;
begin
  if v_user_id is null then
    return jsonb_build_object(
      'reward_awarded', false,
      'error_code', 'UNAUTHORIZED',
      'message', 'User must be logged in to claim rewards.'
    );
  end if;

  if v_trimmed = '' or v_bearing_clean = '' then
    return jsonb_build_object(
      'reward_awarded', false,
      'error_code', 'EMPTY_IDENTIFIER',
      'message', 'Invalid bearing identifier.'
    );
  end if;

  select coalesce(is_reward_eligible, true) into v_is_eligible
  from public.profiles
  where id = v_user_id;

  if not coalesce(v_is_eligible, true) then
    return jsonb_build_object(
      'reward_awarded', false,
      'is_user_blocked', true,
      'error_code', 'USER_REWARDS_BLOCKED',
      'message', 'Reward points are currently inactive for this customer account.'
    );
  end if;

  select * into v_settings from public.reward_settings where id = 1;
  v_pts := coalesce(v_settings.points_per_first_scan, 10);
  v_base_unit := greatest(coalesce(v_settings.points_base_unit, 10), 1);
  v_inr_per_base := coalesce(v_settings.inr_per_base_unit, 10.00);
  v_rate_multiplier := v_inr_per_base / v_base_unit;
  v_amount_inr := round((v_pts * v_rate_multiplier), 2);

  if v_settings.is_reward_system_enabled = false then
    return jsonb_build_object(
      'reward_awarded', false,
      'error_code', 'PROGRAM_PAUSED',
      'message', 'Reward points program is currently paused.'
    );
  end if;

  select count(*) into v_scans_today
  from public.reward_transactions
  where user_id = v_user_id
    and transaction_type in ('FIRST_SCAN_REWARD', 'SCAN_CREDIT')
    and created_at >= v_today_start;

  if v_scans_today >= coalesce(v_settings.daily_max_scans_per_user, 50) then
    return jsonb_build_object(
      'reward_awarded', false,
      'error_code', 'DAILY_LIMIT_REACHED',
      'message', 'Daily scan reward limit reached (' || coalesce(v_settings.daily_max_scans_per_user, 50) || ' scans/day).'
    );
  end if;

  select * into v_qr
  from public.qr_codes
  where bearing_id = v_bearing_clean
     or bearing_id = v_trimmed
     or upper(trim(bearing_id)) = upper(v_bearing_clean)
     or upper(trim(bearing_id)) = upper(v_trimmed)
     or payload_value = v_trimmed
     or payload_value = v_bearing_clean
     or upper(trim(payload_value)) = upper(v_trimmed)
     or upper(trim(payload_value)) = upper(v_bearing_clean)
  limit 1
  for update;

  if not found then
    select * into v_qr
    from public.qr_codes
    where replace(replace(upper(trim(bearing_id)), 'L', 'I'), '1', 'I') = replace(replace(upper(v_bearing_clean), 'L', 'I'), '1', 'I')
       or replace(replace(upper(trim(payload_value)), 'L', 'I'), '1', 'I') = replace(replace(upper(v_bearing_clean), 'L', 'I'), '1', 'I')
    limit 1
    for update;
  end if;

  if not found then
    return jsonb_build_object(
      'reward_awarded', false,
      'error_code', 'UNREGISTERED_BEARING',
      'message', 'Bearing code is not registered in Pivot Bearings ledger.'
    );
  end if;

  if coalesce(v_qr.is_flagged, false) then
    return jsonb_build_object(
      'reward_awarded', false,
      'error_code', 'QR_FLAGGED',
      'bearing_id', v_qr.bearing_id,
      'message', 'Flagged bearing is not eligible for reward points.'
    );
  end if;

  if coalesce(v_qr.is_reward_claimed, false) then
    return jsonb_build_object(
      'reward_awarded', false,
      'already_claimed', true,
      'bearing_id', v_qr.bearing_id,
      'message', 'First-scan reward points have already been claimed for this bearing.'
    );
  end if;

  update public.qr_codes
  set is_reward_claimed = true,
      reward_claimed_by = v_user_id,
      reward_claimed_at = v_now,
      reward_source_module = p_source_module,
      supplier_name = nullif(trim(p_supplier_name), ''),
      supplier_contact = nullif(trim(p_supplier_contact), '')
  where id = v_qr.id;

  insert into public.user_reward_wallets (user_id, current_balance_points, total_points_earned, updated_at)
  values (v_user_id, v_pts, v_pts, v_now)
  on conflict (user_id) do update
  set current_balance_points = public.user_reward_wallets.current_balance_points + v_pts,
      total_points_earned = public.user_reward_wallets.total_points_earned + v_pts,
      updated_at = v_now
  returning current_balance_points into v_new_balance;

  insert into public.reward_transactions (
    user_id,
    qr_code_id,
    bearing_id,
    transaction_type,
    points,
    points_base_unit,
    inr_per_base_unit,
    amount_inr,
    inr_value,
    source_module,
    description,
    balance_after,
    supplier_name,
    supplier_contact,
    created_at
  ) values (
    v_user_id,
    v_qr.id,
    v_qr.bearing_id,
    'FIRST_SCAN_REWARD',
    v_pts,
    v_base_unit,
    v_inr_per_base,
    v_amount_inr,
    v_amount_inr,
    p_source_module,
    '1st Scan reward for bearing ' || v_qr.bearing_id,
    v_new_balance,
    nullif(trim(p_supplier_name), ''),
    nullif(trim(p_supplier_contact), ''),
    v_now
  );

  return jsonb_build_object(
    'reward_awarded', true,
    'already_claimed', false,
    'bearing_id', v_qr.bearing_id,
    'points_earned', v_pts,
    'inr_value', v_amount_inr,
    'amount_inr', v_amount_inr,
    'new_balance', v_new_balance,
    'rate_display', v_base_unit || ' Points = ₹' || trim(to_char(v_inr_per_base, '999999990.00')),
    'message', 'Congratulations! +' || v_pts || ' Reward Points Credited!'
  );
end;
$$ language plpgsql security definer;

grant execute on function public.get_bearing_lifecycle_summary(text) to authenticated, anon;
grant execute on function public.verify_bearing_qr(text, text, text, text) to authenticated, anon;
grant execute on function public.claim_bearing_scan_reward(text, text, text, text) to authenticated, anon;

