-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261111000036_fix_reward_system_permissions_and_grants.sql
-- High-Integrity Reward Points, RPC Overload Cleanups, Permissions & Security Definer Grants
-- ==============================================================================

-- 1. Ensure reward_settings table and default singleton row exist
create table if not exists public.reward_settings (
  id integer primary key default 1 check (id = 1),
  points_base_unit integer not null default 10,
  inr_per_base_unit numeric(10, 2) not null default 10.00,
  points_per_first_scan integer not null default 10,
  min_redemption_points integer not null default 50,
  is_reward_system_enabled boolean not null default true,
  daily_max_scans_per_user integer not null default 50,
  terms_and_conditions text not null default 'Pivot Bearings reserves the right to modify, adjust, or change the reward point conversion value (Points to INR rate) and program rules at any time without prior notice.',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

alter table public.reward_settings
  add column if not exists daily_max_scans_per_user integer not null default 50,
  add column if not exists terms_and_conditions text default 'Pivot Bearings reserves the right to modify, adjust, or change the reward point conversion value (Points to INR rate) and program rules at any time without prior notice.';

insert into public.reward_settings (
  id,
  points_base_unit,
  inr_per_base_unit,
  points_per_first_scan,
  min_redemption_points,
  is_reward_system_enabled,
  daily_max_scans_per_user,
  terms_and_conditions
) values (
  1,
  10,
  10.00,
  10,
  50,
  true,
  50,
  'Pivot Bearings reserves the right to modify, adjust, or change the reward point conversion value (Points to INR rate) and program rules at any time without prior notice.'
) on conflict (id) do update set
  is_reward_system_enabled = true;

-- 2. Ensure all relevant columns exist across tables
alter table public.qr_codes
  add column if not exists is_reward_claimed boolean not null default false,
  add column if not exists reward_claimed_by uuid references auth.users(id),
  add column if not exists reward_claimed_at timestamptz,
  add column if not exists reward_source_module text,
  add column if not exists supplier_name text,
  add column if not exists supplier_contact text;

alter table public.profiles
  add column if not exists is_reward_eligible boolean not null default true;

-- Ensure reward_transactions has all required columns and relaxed constraint
alter table public.reward_transactions
  add column if not exists inr_value numeric(10, 2),
  add column if not exists balance_after integer,
  add column if not exists supplier_name text,
  add column if not exists supplier_contact text;

-- Drop obsolete check constraint on transaction_type to allow standard types safely
alter table public.reward_transactions drop constraint if exists reward_transactions_transaction_type_check;

-- Ensure reward_redemptions has all required columns
alter table public.reward_redemptions
  add column if not exists supplier_name text,
  add column if not exists supplier_contact text,
  add column if not exists points_base_unit integer not null default 10,
  add column if not exists inr_per_base_unit numeric(10, 2) not null default 10.00;

-- Ensure user_reward_wallets table exists
create table if not exists public.user_reward_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  current_balance_points integer not null default 0 check (current_balance_points >= 0),
  pending_redemption_points integer not null default 0 check (pending_redemption_points >= 0),
  total_points_earned integer not null default 0 check (total_points_earned >= 0),
  total_points_redeemed integer not null default 0 check (total_points_redeemed >= 0),
  is_frozen boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_reward_wallets
  add column if not exists current_balance_points integer not null default 0,
  add column if not exists pending_redemption_points integer not null default 0,
  add column if not exists total_points_earned integer not null default 0,
  add column if not exists total_points_redeemed integer not null default 0,
  add column if not exists is_frozen boolean not null default false;

-- 3. Unambiguously drop ALL previous function overloads (handles 42725 not unique errors)
do $$
declare
  r record;
begin
  for r in (
    select oid::regprocedure as func_signature
    from pg_proc
    where proname in (
      'claim_bearing_scan_reward',
      'get_user_reward_profile',
      'request_reward_redemption',
      'admin_process_redemption',
      'admin_update_reward_settings',
      'admin_update_user_reward_eligibility'
    )
    and pronamespace = 'public'::regnamespace
  ) loop
    execute 'drop function if exists ' || r.func_signature || ' cascade;';
  end loop;
end $$;

-- Explicit drops for standard signatures (as secondary guarantee)
drop function if exists public.request_reward_redemption(integer, text, text, text, text, text, text, text, text) cascade;
drop function if exists public.request_reward_redemption(integer, text, text, text, text, text, text) cascade;
drop function if exists public.admin_process_redemption(uuid, text, text, text, text) cascade;
drop function if exists public.admin_update_reward_settings(integer, numeric, integer, integer, boolean, integer, text) cascade;
drop function if exists public.admin_update_user_reward_eligibility(uuid, boolean) cascade;
drop function if exists public.claim_bearing_scan_reward(text, text, text, text) cascade;
drop function if exists public.claim_bearing_scan_reward(text, text) cascade;
drop function if exists public.claim_bearing_scan_reward(text) cascade;
drop function if exists public.get_user_reward_profile() cascade;

-- ==============================================================================
-- 4. Authoritative claim_bearing_scan_reward RPC
-- ==============================================================================
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
  v_bearing_clean text;
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

  if v_trimmed = '' then
    return jsonb_build_object(
      'reward_awarded', false,
      'error_code', 'EMPTY_IDENTIFIER',
      'message', 'Invalid bearing identifier.'
    );
  end if;

  -- Check if user is individually eligible for rewards
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

  -- Extract clean bearing ID from URLs if present
  if v_trimmed ilike '%/pbi/%' then
    v_bearing_clean := split_part(split_part(split_part(v_trimmed, '/pbi/', 2), '?', 1), '&', 1);
  elsif v_trimmed ilike '%/verify/%' then
    v_bearing_clean := split_part(split_part(split_part(v_trimmed, '/verify/', 2), '?', 1), '&', 1);
  elsif v_trimmed ilike 'http%://%' then
    v_bearing_clean := split_part(split_part(split_part(v_trimmed, '?', 1), '&', 1), '/', array_length(string_to_array(split_part(split_part(v_trimmed, '?', 1), '&', 1), '/'), 1));
  else
    v_bearing_clean := v_trimmed;
  end if;
  v_bearing_clean := trim(v_bearing_clean);

  -- Normalize URL encoded characters if present
  v_bearing_clean := replace(v_bearing_clean, '%23', '#');
  v_bearing_clean := replace(v_bearing_clean, '%5D', ']');
  v_bearing_clean := replace(v_bearing_clean, '%5d', ']');
  v_bearing_clean := replace(v_bearing_clean, '%5B', '[');
  v_bearing_clean := replace(v_bearing_clean, '%5b', '[');
  v_bearing_clean := replace(v_bearing_clean, '%20', ' ');

  -- Fetch reward settings
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

  -- Daily scan limit removed: unlimited scans permitted
  v_scans_today := 0;

  -- Find and lock QR code row with full payload and serial resilience
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

  -- Look-alike character fallback (L vs I vs 1) consistent with authenticate_bearing_qr & verify_bearing_qr
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

  -- Check if already claimed
  if coalesce(v_qr.is_reward_claimed, false) then
    return jsonb_build_object(
      'reward_awarded', false,
      'already_claimed', true,
      'bearing_id', v_qr.bearing_id,
      'message', 'First-scan reward points have already been claimed for this bearing.'
    );
  end if;

  -- Mark QR as claimed
  update public.qr_codes
  set is_reward_claimed = true,
      reward_claimed_by = v_user_id,
      reward_claimed_at = v_now,
      reward_source_module = p_source_module,
      supplier_name = nullif(trim(p_supplier_name), ''),
      supplier_contact = nullif(trim(p_supplier_contact), '')
  where id = v_qr.id;

  -- Ensure wallet exists and credit points
  insert into public.user_reward_wallets (user_id, current_balance_points, total_points_earned, updated_at)
  values (v_user_id, v_pts, v_pts, v_now)
  on conflict (user_id) do update
  set current_balance_points = public.user_reward_wallets.current_balance_points + v_pts,
      total_points_earned = public.user_reward_wallets.total_points_earned + v_pts,
      updated_at = v_now
  returning current_balance_points into v_new_balance;

  -- Log ledger transaction
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

-- ==============================================================================
-- 5. Authoritative get_user_reward_profile RPC
-- ==============================================================================
create or replace function public.get_user_reward_profile()
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_wallet record;
  v_settings record;
  v_base_unit integer;
  v_inr_per_base numeric(10, 2);
  v_rate_multiplier numeric(10, 4);
  v_is_eligible boolean := true;
begin
  if v_user_id is null then
    return jsonb_build_object('authenticated', false);
  end if;

  select * into v_settings from public.reward_settings where id = 1;
  v_base_unit := greatest(coalesce(v_settings.points_base_unit, 10), 1);
  v_inr_per_base := coalesce(v_settings.inr_per_base_unit, 10.00);
  v_rate_multiplier := v_inr_per_base / v_base_unit;

  select coalesce(is_reward_eligible, true) into v_is_eligible
  from public.profiles
  where id = v_user_id;

  select * into v_wallet
  from public.user_reward_wallets
  where user_id = v_user_id;

  return jsonb_build_object(
    'authenticated', true,
    'is_reward_eligible', coalesce(v_is_eligible, true),
    'is_frozen', coalesce(v_wallet.is_frozen, false),
    'current_balance_points', coalesce(v_wallet.current_balance_points, 0),
    'current_balance_inr', round((coalesce(v_wallet.current_balance_points, 0) * v_rate_multiplier), 2),
    'pending_redemption_points', coalesce(v_wallet.pending_redemption_points, 0),
    'pending_redemption_inr', round((coalesce(v_wallet.pending_redemption_points, 0) * v_rate_multiplier), 2),
    'total_points_earned', coalesce(v_wallet.total_points_earned, 0),
    'total_points_redeemed', coalesce(v_wallet.total_points_redeemed, 0),
    'points_base_unit', v_base_unit,
    'inr_per_base_unit', v_inr_per_base,
    'rate_multiplier', v_rate_multiplier,
    'rate_display_string', v_base_unit || ' Points = ₹' || trim(to_char(v_inr_per_base, '999999990.00')),
    'min_redemption_points', coalesce(v_settings.min_redemption_points, 50),
    'min_redemption_inr', round((coalesce(v_settings.min_redemption_points, 50) * v_rate_multiplier), 2),
    'is_enabled', coalesce(v_settings.is_reward_system_enabled, true),
    'terms_and_conditions', coalesce(v_settings.terms_and_conditions, 'Pivot Bearings reserves the right to modify, adjust, or change the reward point conversion value (Points to INR rate) and program rules at any time without prior notice.')
  );
end;
$$ language plpgsql security definer;

-- ==============================================================================
-- 6. Authoritative request_reward_redemption RPC
-- ==============================================================================
create or replace function public.request_reward_redemption(
  p_points integer,
  p_payout_method text,
  p_upi_id text default null,
  p_bank_account text default null,
  p_bank_ifsc text default null,
  p_bank_holder_name text default null,
  p_bank_name text default null,
  p_supplier_name text default null,
  p_supplier_contact text default null
)
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_wallet record;
  v_settings record;
  v_base_unit integer;
  v_inr_per_base numeric(10, 2);
  v_rate_multiplier numeric(10, 4);
  v_amount_inr numeric(10, 2);
  v_req_num text;
  v_now timestamptz := now();
  v_redemption_id uuid;
  v_supp_name text := trim(coalesce(p_supplier_name, ''));
  v_supp_contact text := trim(coalesce(p_supplier_contact, ''));
begin
  if v_user_id is null then
    return jsonb_build_object('success', false, 'message', 'Unauthorized.');
  end if;

  if p_points is null or p_points <= 0 then
    return jsonb_build_object('success', false, 'message', 'Invalid points requested.');
  end if;

  if v_supp_name = '' or v_supp_contact = '' then
    return jsonb_build_object(
      'success', false,
      'message', 'Supplier Name and Contact Number are mandatory to redeem points.'
    );
  end if;

  if p_payout_method = 'UPI' then
    if p_upi_id is null or trim(p_upi_id) = '' then
      return jsonb_build_object('success', false, 'message', 'Please enter a valid UPI ID.');
    end if;
  elsif p_payout_method = 'BANK_TRANSFER' then
    if p_bank_account is null or trim(p_bank_account) = '' or
       p_bank_ifsc is null or trim(p_bank_ifsc) = '' or
       p_bank_holder_name is null or trim(p_bank_holder_name) = '' then
      return jsonb_build_object('success', false, 'message', 'Please complete all bank account details.');
    end if;
  else
    return jsonb_build_object('success', false, 'message', 'Invalid payout method.');
  end if;

  select * into v_settings from public.reward_settings where id = 1;
  v_base_unit := greatest(coalesce(v_settings.points_base_unit, 10), 1);
  v_inr_per_base := coalesce(v_settings.inr_per_base_unit, 10.00);
  v_rate_multiplier := v_inr_per_base / v_base_unit;
  v_amount_inr := round((p_points * v_rate_multiplier), 2);

  if p_points < coalesce(v_settings.min_redemption_points, 50) then
    return jsonb_build_object(
      'success', false,
      'message', 'Minimum redemption threshold is ' || coalesce(v_settings.min_redemption_points, 50) || ' points.'
    );
  end if;

  select * into v_wallet
  from public.user_reward_wallets
  where user_id = v_user_id
  for update;

  if not found or v_wallet.current_balance_points < p_points then
    return jsonb_build_object(
      'success', false,
      'message', 'Insufficient point balance.'
    );
  end if;

  if coalesce(v_wallet.is_frozen, false) then
    return jsonb_build_object(
      'success', false,
      'message', 'Your reward wallet is frozen. Please contact administrator.'
    );
  end if;

  update public.user_reward_wallets
  set current_balance_points = current_balance_points - p_points,
      pending_redemption_points = pending_redemption_points + p_points,
      updated_at = v_now
  where user_id = v_user_id;

  v_req_num := 'RED-' || to_char(v_now, 'YYYYMMDD') || '-' || lpad((floor(random() * 9000) + 1000)::text, 4, '0');

  insert into public.reward_redemptions (
    request_number,
    user_id,
    points_requested,
    points_base_unit,
    inr_per_base_unit,
    amount_in_inr,
    payout_method,
    upi_id,
    bank_account_number,
    bank_ifsc,
    bank_account_holder_name,
    bank_name,
    supplier_name,
    supplier_contact,
    status,
    created_at,
    updated_at
  ) values (
    v_req_num,
    v_user_id,
    p_points,
    v_base_unit,
    v_inr_per_base,
    v_amount_inr,
    p_payout_method,
    nullif(trim(p_upi_id), ''),
    nullif(trim(p_bank_account), ''),
    nullif(trim(p_bank_ifsc), ''),
    nullif(trim(p_bank_holder_name), ''),
    nullif(trim(p_bank_name), ''),
    v_supp_name,
    v_supp_contact,
    'PENDING',
    v_now,
    v_now
  ) returning id into v_redemption_id;

  insert into public.reward_transactions (
    user_id,
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
    v_req_num,
    'REDEMPTION_ESCROW',
    -p_points,
    v_base_unit,
    v_inr_per_base,
    -v_amount_inr,
    -v_amount_inr,
    'REDEMPTION',
    'Payout request #' || v_req_num || ' (' || p_payout_method || ')',
    v_wallet.current_balance_points - p_points,
    v_supp_name,
    v_supp_contact,
    v_now
  );

  return jsonb_build_object(
    'success', true,
    'redemption_id', v_redemption_id,
    'request_number', v_req_num,
    'points_requested', p_points,
    'amount_in_inr', v_amount_inr,
    'status', 'PENDING',
    'message', 'Redemption request submitted successfully!'
  );
end;
$$ language plpgsql security definer;

-- ==============================================================================
-- 7. Authoritative admin_process_redemption RPC
-- ==============================================================================
create or replace function public.admin_process_redemption(
  p_redemption_id uuid,
  p_action text,
  p_payment_ref_id text default null,
  p_payment_mode text default null,
  p_notes text default null
)
returns jsonb as $$
declare
  v_admin_id uuid := auth.uid();
  v_redemption record;
  v_now timestamptz := now();
  v_is_admin boolean := false;
begin
  select exists (
    select 1 from public.user_roles where user_id = v_admin_id and role = 'ADMIN'
  ) into v_is_admin;

  if not v_is_admin then
    return jsonb_build_object('success', false, 'message', 'Unauthorized. Admin privilege required.');
  end if;

  select * into v_redemption
  from public.reward_redemptions
  where id = p_redemption_id
  for update;

  if not found then
    return jsonb_build_object('success', false, 'message', 'Redemption request not found.');
  end if;

  if v_redemption.status != 'PENDING' and v_redemption.status != 'PROCESSING' then
    return jsonb_build_object(
      'success', false,
      'message', 'Request is already finalized (' || v_redemption.status || ').'
    );
  end if;

  if p_action = 'APPROVE' then
    update public.reward_redemptions
    set status = 'COMPLETED',
        payment_reference_id = nullif(trim(p_payment_ref_id), ''),
        payment_mode = nullif(trim(p_payment_mode), ''),
        admin_notes = nullif(trim(p_notes), ''),
        actioned_by = v_admin_id,
        actioned_at = v_now,
        updated_at = v_now
    where id = p_redemption_id;

    update public.user_reward_wallets
    set pending_redemption_points = greatest(pending_redemption_points - v_redemption.points_requested, 0),
        total_points_redeemed = total_points_redeemed + v_redemption.points_requested,
        updated_at = v_now
    where user_id = v_redemption.user_id;

    insert into public.reward_transactions (
      user_id,
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
      created_at
    )
    select
      v_redemption.user_id,
      v_redemption.request_number,
      'REDEMPTION_COMPLETED',
      -v_redemption.points_requested,
      coalesce(v_redemption.points_base_unit, 10),
      coalesce(v_redemption.inr_per_base_unit, 10.00),
      -v_redemption.amount_in_inr,
      -v_redemption.amount_in_inr,
      'ADMIN_PAYOUT',
      'Payout #' || v_redemption.request_number || ' approved. Ref: ' || coalesce(p_payment_ref_id, 'N/A'),
      w.current_balance_points,
      v_now
    from public.user_reward_wallets w
    where w.user_id = v_redemption.user_id;

    return jsonb_build_object('success', true, 'status', 'COMPLETED', 'message', 'Payout request #' || v_redemption.request_number || ' marked as completed.');
  elsif p_action = 'REJECT' then
    update public.reward_redemptions
    set status = 'REJECTED',
        admin_notes = coalesce(nullif(trim(p_notes), ''), 'Administrative decision'),
        actioned_by = v_admin_id,
        actioned_at = v_now,
        updated_at = v_now
    where id = p_redemption_id;

    update public.user_reward_wallets
    set current_balance_points = current_balance_points + v_redemption.points_requested,
        pending_redemption_points = greatest(pending_redemption_points - v_redemption.points_requested, 0),
        updated_at = v_now
    where user_id = v_redemption.user_id;

    insert into public.reward_transactions (
      user_id,
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
      created_at
    )
    select
      v_redemption.user_id,
      v_redemption.request_number,
      'REDEMPTION_REVERTED',
      v_redemption.points_requested,
      coalesce(v_redemption.points_base_unit, 10),
      coalesce(v_redemption.inr_per_base_unit, 10.00),
      v_redemption.amount_in_inr,
      v_redemption.amount_in_inr,
      'ADMIN_PAYOUT',
      'Points restored for payout #' || v_redemption.request_number || '. Reason: ' || coalesce(p_notes, 'Administrative decision'),
      w.current_balance_points,
      v_now
    from public.user_reward_wallets w
    where w.user_id = v_redemption.user_id;

    return jsonb_build_object('success', true, 'status', 'REJECTED', 'message', 'Payout request #' || v_redemption.request_number || ' rejected. Points restored.');
  else
    return jsonb_build_object('success', false, 'message', 'Invalid action: ' || p_action);
  end if;
end;
$$ language plpgsql security definer;

-- ==============================================================================
-- 8. Authoritative admin_update_reward_settings RPC
-- ==============================================================================
create or replace function public.admin_update_reward_settings(
  p_points_base_unit integer,
  p_inr_per_base_unit numeric(10, 2),
  p_points_per_first_scan integer,
  p_min_redemption_points integer,
  p_is_enabled boolean,
  p_daily_max_scans integer,
  p_terms_and_conditions text default null
)
returns jsonb as $$
declare
  v_admin_id uuid := auth.uid();
  v_is_admin boolean := false;
  v_now timestamptz := now();
begin
  select exists (
    select 1 from public.user_roles where user_id = v_admin_id and role = 'ADMIN'
  ) into v_is_admin;

  if not v_is_admin then
    return jsonb_build_object('success', false, 'message', 'Unauthorized. Admin privilege required.');
  end if;

  update public.reward_settings
  set points_base_unit = greatest(coalesce(p_points_base_unit, 10), 1),
      inr_per_base_unit = greatest(coalesce(p_inr_per_base_unit, 10.00), 0.01),
      points_per_first_scan = greatest(coalesce(p_points_per_first_scan, 10), 1),
      min_redemption_points = greatest(coalesce(p_min_redemption_points, 50), 1),
      is_reward_system_enabled = coalesce(p_is_enabled, true),
      daily_max_scans_per_user = greatest(coalesce(p_daily_max_scans, 50), 1),
      terms_and_conditions = coalesce(
        nullif(trim(p_terms_and_conditions), ''),
        'Pivot Bearings reserves the right to modify, adjust, or change the reward point conversion value (Points to INR rate) and program rules at any time without prior notice.'
      ),
      updated_at = v_now,
      updated_by = v_admin_id
  where id = 1;

  return jsonb_build_object(
    'success', true,
    'message', 'Reward system settings updated successfully.'
  );
end;
$$ language plpgsql security definer;

-- ==============================================================================
-- 9. Authoritative admin_update_user_reward_eligibility RPC
-- ==============================================================================
create or replace function public.admin_update_user_reward_eligibility(
  p_target_user_id uuid,
  p_is_eligible boolean
)
returns jsonb as $$
declare
  v_admin_id uuid := auth.uid();
  v_is_admin boolean := false;
begin
  select exists (
    select 1 from public.user_roles where user_id = v_admin_id and role = 'ADMIN'
  ) into v_is_admin;

  if not v_is_admin then
    return jsonb_build_object('success', false, 'message', 'Unauthorized. Admin privilege required.');
  end if;

  update public.profiles
  set is_reward_eligible = coalesce(p_is_eligible, true),
      updated_at = now()
  where id = p_target_user_id;

  update public.user_reward_wallets
  set is_frozen = not coalesce(p_is_eligible, true),
      updated_at = now()
  where user_id = p_target_user_id;

  return jsonb_build_object(
    'success', true,
    'user_id', p_target_user_id,
    'is_reward_eligible', coalesce(p_is_eligible, true)
  );
end;
$$ language plpgsql security definer;

-- ==============================================================================
-- 10. Explicit Grants for execution
-- ==============================================================================
grant execute on function public.claim_bearing_scan_reward(text, text, text, text) to authenticated, anon;
grant execute on function public.get_user_reward_profile() to authenticated, anon;
grant execute on function public.request_reward_redemption(integer, text, text, text, text, text, text, text, text) to authenticated;
grant execute on function public.admin_process_redemption(uuid, text, text, text, text) to authenticated;
grant execute on function public.admin_update_reward_settings(integer, numeric, integer, integer, boolean, integer, text) to authenticated;
grant execute on function public.admin_update_user_reward_eligibility(uuid, boolean) to authenticated;

-- ==============================================================================
-- 11. Row Level Security & Explicit Table Permissions
-- ==============================================================================
alter table public.reward_settings enable row level security;
alter table public.user_reward_wallets enable row level security;
alter table public.reward_transactions enable row level security;
alter table public.reward_redemptions enable row level security;

drop policy if exists "Allow select reward_settings for all" on public.reward_settings;
drop policy if exists "Users view own wallet" on public.user_reward_wallets;
drop policy if exists "Users view own transactions" on public.reward_transactions;
drop policy if exists "Users view own redemptions" on public.reward_redemptions;
drop policy if exists "Users insert own redemptions" on public.reward_redemptions;
drop policy if exists "Admins manage reward_settings" on public.reward_settings;
drop policy if exists "Admins manage all wallets" on public.user_reward_wallets;
drop policy if exists "Admins manage all transactions" on public.reward_transactions;
drop policy if exists "Admins manage all redemptions" on public.reward_redemptions;

-- Public read for settings
create policy "Allow select reward_settings for all" on public.reward_settings
  for select using (true);

-- User policies
create policy "Users view own wallet" on public.user_reward_wallets
  for select using (auth.uid() = user_id);

create policy "Users view own transactions" on public.reward_transactions
  for select using (auth.uid() = user_id);

create policy "Users view own redemptions" on public.reward_redemptions
  for select using (auth.uid() = user_id);

create policy "Users insert own redemptions" on public.reward_redemptions
  for insert with check (auth.uid() = user_id);

-- Admin policies
create policy "Admins manage reward_settings" on public.reward_settings
  for all using (
    exists (select 1 from public.user_roles where user_id = auth.uid() and role = 'ADMIN')
  );

create policy "Admins manage all wallets" on public.user_reward_wallets
  for all using (
    exists (select 1 from public.user_roles where user_id = auth.uid() and role = 'ADMIN')
  );

create policy "Admins manage all transactions" on public.reward_transactions
  for all using (
    exists (select 1 from public.user_roles where user_id = auth.uid() and role = 'ADMIN')
  );

create policy "Admins manage all redemptions" on public.reward_redemptions
  for all using (
    exists (select 1 from public.user_roles where user_id = auth.uid() and role = 'ADMIN')
  );

-- Explicit table grants
grant select on public.reward_settings to authenticated, anon;
grant select on public.user_reward_wallets to authenticated;
grant select on public.reward_transactions to authenticated;
grant select, insert on public.reward_redemptions to authenticated;
