-- Migration: Fix reward point logical conditions
-- 1. Rewarding points does NOT require supplier info
-- 2. Redeeming points DOES require supplier info (mandatory supplier name & contact)
-- 3. Blocked reward toggle prevents user from receiving or seeing reward points

-- Add supplier details to reward_redemptions if not present
alter table public.reward_redemptions 
add column if not exists supplier_name text,
add column if not exists supplier_contact text;

-- 1. Update claim_bearing_scan_reward: Remove mandatory supplier details
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

  if not v_is_eligible then
    return jsonb_build_object(
      'reward_awarded', false,
      'is_user_blocked', true,
      'error_code', 'USER_REWARDS_BLOCKED',
      'message', 'Reward points are currently inactive for this customer account.'
    );
  end if;

  -- Normalize bearing ID
  if v_trimmed ilike '%/pbi/%' then
    v_bearing_clean := split_part(split_part(v_trimmed, '/pbi/', 2), '?', 1);
  elsif v_trimmed ilike '%/verify/%' then
    v_bearing_clean := split_part(split_part(v_trimmed, '/verify/', 2), '?', 1);
  elsif v_trimmed ilike 'http%://%' then
    v_bearing_clean := split_part(split_part(split_part(v_trimmed, '?', 1), '#', 1), '/', array_length(string_to_array(split_part(split_part(v_trimmed, '?', 1), '#', 1), '/'), 1));
  else
    v_bearing_clean := v_trimmed;
  end if;
  v_bearing_clean := upper(trim(v_bearing_clean));

  -- 1. Check if global reward program is enabled
  select * into v_settings from public.reward_settings where id = 1;
  if not found or not v_settings.is_reward_system_enabled then
    return jsonb_build_object(
      'reward_awarded', false,
      'error_code', 'PROGRAM_PAUSED',
      'message', 'Reward points program is currently paused.'
    );
  end if;

  v_pts := coalesce(v_settings.points_per_first_scan, 10);
  v_base_unit := greatest(coalesce(v_settings.points_base_unit, 10), 1);
  v_inr_per_base := coalesce(v_settings.inr_per_base_unit, 10.00);
  v_rate_multiplier := v_inr_per_base / v_base_unit;
  v_amount_inr := round((v_pts * v_rate_multiplier), 2);

  -- 2. Daily scan velocity check
  select count(*) into v_scans_today
  from public.reward_transactions
  where user_id = v_user_id
    and transaction_type = 'SCAN_CREDIT'
    and created_at >= v_today_start;

  if v_scans_today >= coalesce(v_settings.max_daily_scans_per_user, 10) then
    return jsonb_build_object(
      'reward_awarded', false,
      'error_code', 'DAILY_LIMIT_REACHED',
      'message', 'Daily scan reward limit reached (' || v_settings.max_daily_scans_per_user || ' scans/day).'
    );
  end if;

  -- 3. Find and lock QR code row
  select * into v_qr
  from public.qr_codes
  where upper(trim(bearing_id)) = v_bearing_clean
     or upper(trim(payload_value)) = v_bearing_clean
     or upper(trim(payload_value)) = upper(v_trimmed)
  for update;

  if not found then
    return jsonb_build_object(
      'reward_awarded', false,
      'error_code', 'UNREGISTERED_BEARING',
      'message', 'Bearing code is not registered in Pivot Bearings ledger.'
    );
  end if;

  -- 4. Check if already claimed
  if v_qr.is_reward_claimed then
    return jsonb_build_object(
      'reward_awarded', false,
      'already_claimed', true,
      'bearing_id', v_qr.bearing_id,
      'message', 'First-scan reward points have already been claimed for this bearing.'
    );
  end if;

  -- 5. Mark QR as claimed (optional supplier metadata recorded if provided)
  update public.qr_codes
  set is_reward_claimed = true,
      reward_claimed_by = v_user_id,
      reward_claimed_at = v_now,
      supplier_name = nullif(trim(p_supplier_name), ''),
      supplier_contact = nullif(trim(p_supplier_contact), '')
  where id = v_qr.id;

  -- 6. Ensure user wallet exists and credit points
  insert into public.user_reward_wallets (user_id, current_balance_points, total_points_earned, updated_at)
  values (v_user_id, v_pts, v_pts, v_now)
  on conflict (user_id) do update
  set current_balance_points = public.user_reward_wallets.current_balance_points + v_pts,
      total_points_earned = public.user_reward_wallets.total_points_earned + v_pts,
      updated_at = v_now
  returning current_balance_points into v_new_balance;

  -- 7. Log ledger credit
  insert into public.reward_transactions (
    user_id,
    qr_code_id,
    bearing_id,
    transaction_type,
    points,
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
    'SCAN_CREDIT',
    v_pts,
    v_amount_inr,
    p_source_module,
    'Scan reward for bearing ' || v_qr.bearing_id,
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
    'new_balance', v_new_balance,
    'message', '+' || v_pts || ' Reward Points Credited!'
  );
end;
$$ language plpgsql security definer;


-- 2. Update request_reward_redemption: Enforce mandatory supplier name & contact
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

  -- Mandatory Supplier Details when REDEEMING points
  if v_supp_name = '' or v_supp_contact = '' then
    return jsonb_build_object(
      'success', false,
      'message', 'Supplier Name and Contact Number are mandatory to redeem points.'
    );
  end if;

  -- Validate payout method
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

  -- 1. Fetch current settings
  select * into v_settings from public.reward_settings where id = 1;
  if not found or not v_settings.is_reward_system_enabled then
    return jsonb_build_object('success', false, 'message', 'Reward redemption is currently paused.');
  end if;

  if p_points < v_settings.min_redemption_points then
    return jsonb_build_object(
      'success', false,
      'message', 'Minimum redemption threshold is ' || v_settings.min_redemption_points || ' points.'
    );
  end if;

  v_base_unit := greatest(coalesce(v_settings.points_base_unit, 10), 1);
  v_inr_per_base := coalesce(v_settings.inr_per_base_unit, 10.00);
  v_rate_multiplier := v_inr_per_base / v_base_unit;
  v_amount_inr := round((p_points * v_rate_multiplier), 2);

  -- 2. Lock user wallet row FOR UPDATE
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

  if v_wallet.is_frozen then
    return jsonb_build_object(
      'success', false,
      'message', 'Your reward wallet is frozen. Please contact administrator.'
    );
  end if;

  -- 3. Escrow points atomically
  update public.user_reward_wallets
  set current_balance_points = current_balance_points - p_points,
      pending_redemption_points = pending_redemption_points + p_points,
      updated_at = v_now
  where user_id = v_user_id;

  -- 4. Create request number
  v_req_num := 'RED-' || to_char(v_now, 'YYYYMMDD') || '-' || lpad((floor(random() * 9000) + 1000)::text, 4, '0');

  -- 5. Insert into reward_redemptions
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
    nullif(upper(trim(p_bank_ifsc)), ''),
    nullif(trim(p_bank_holder_name), ''),
    nullif(trim(p_bank_name), ''),
    v_supp_name,
    v_supp_contact,
    'PENDING',
    v_now,
    v_now
  ) returning id into v_redemption_id;

  -- 6. Log to immutable ledger
  insert into public.reward_transactions (
    user_id,
    redemption_id,
    transaction_type,
    points,
    inr_value,
    description,
    balance_after,
    supplier_name,
    supplier_contact,
    created_at
  ) values (
    v_user_id,
    v_redemption_id,
    'REDEMPTION_HOLD',
    p_points,
    v_amount_inr,
    'Payout request ' || v_req_num || ' for ₹' || v_amount_inr || ' (Supplier: ' || v_supp_name || ')',
    (v_wallet.current_balance_points - p_points),
    v_supp_name,
    v_supp_contact,
    v_now
  );

  return jsonb_build_object(
    'success', true,
    'redemption_id', v_redemption_id,
    'request_number', v_req_num,
    'points_escrowed', p_points,
    'amount_in_inr', v_amount_inr,
    'message', 'Redemption request submitted! Escrowed ' || p_points || ' points (₹' || v_amount_inr || ').'
  );
end;
$$ language plpgsql security definer;

