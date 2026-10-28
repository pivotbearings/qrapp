-- ============================================================================
-- Migration: 20261028000028_reward_supplier_details_and_auto_approval.sql
-- Description:
-- 1. Auto-approve all new sign-ups so pending verification is eliminated.
-- 2. Make supplier name and contact number mandatory when claiming reward points.
-- 3. Persist supplier details on qr_codes and reward_transactions.
-- ============================================================================

-- 1. Add supplier columns to qr_codes
alter table public.qr_codes
  add column if not exists supplier_name text,
  add column if not exists supplier_contact text;

-- 2. Add supplier columns to reward_transactions
alter table public.reward_transactions
  add column if not exists supplier_name text,
  add column if not exists supplier_contact text;

-- 3. Auto-approve all existing users and update default on public.profiles
update public.profiles
set is_approved = true
where is_approved is not true;

alter table public.profiles
  alter column is_approved set default true;

-- 4. Update the user sign-up trigger to auto-approve new accounts
create or replace function public.on_auth_user_created_assign_role_and_profile()
returns trigger as $$
declare
  v_email text := trim(lower(coalesce(new.email, '')));
  v_is_admin boolean := false;
  v_company_name text;
  v_phone text;
  v_full_name text;
  v_facility_code text;
begin
  -- 1. Determine admin privileges based on email or metadata
  if v_email in ('abc@gmail.com', 'admin@pivotbearings.com', 'operations@pivotbearings.com')
     or lower(coalesce(new.raw_user_meta_data->>'role', '')) in ('admin', 'super_admin') then
    v_is_admin := true;
  end if;

  -- 2. Clean metadata
  v_company_name := nullif(trim(coalesce(new.raw_user_meta_data->>'company_name', new.raw_user_meta_data->>'company', '')), '');
  v_phone := nullif(trim(coalesce(new.raw_user_meta_data->>'phone', new.raw_user_meta_data->>'contact', '')), '');
  v_full_name := coalesce(nullif(trim(coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', '')), ''), split_part(v_email, '@', 1));

  -- 3. Fallbacks
  if v_company_name is null then
    v_company_name := case when v_is_admin then 'Pivot Bearings India Ltd' else 'Industrial Customer' end;
  end if;
  if v_phone is null then
    v_phone := '+91-9800000000';
  end if;

  -- 4. Facility code
  v_facility_code := coalesce(
    nullif(trim(new.raw_user_meta_data->>'facility_code'), ''),
    concat('FAC-', upper(substring(regexp_replace(coalesce(v_company_name, 'REG'), '[^a-zA-Z0-9]', '', 'g') from 1 for 4)))
  );

  -- 5. Upsert into public.profiles: All users are approved by default!
  insert into public.profiles (
    id,
    email,
    full_name,
    phone,
    company_name,
    facility_code,
    is_approved,
    is_active,
    has_warranty_access,
    has_track_bearing_access,
    is_reward_eligible,
    created_at,
    updated_at
  )
  values (
    new.id,
    v_email,
    v_full_name,
    v_phone,
    v_company_name,
    v_facility_code,
    true, -- Auto-approve so users never get blocked on pending verification
    true,
    false, -- Default mutual exclusivity: toggled by admin
    false,
    true,  -- Eligible for rewards
    now(),
    now()
  )
  on conflict (id) do update set
    email = coalesce(excluded.email, public.profiles.email),
    full_name = coalesce(nullif(excluded.full_name, ''), public.profiles.full_name),
    phone = coalesce(excluded.phone, public.profiles.phone),
    company_name = coalesce(nullif(excluded.company_name, ''), public.profiles.company_name),
    facility_code = coalesce(nullif(excluded.facility_code, ''), public.profiles.facility_code),
    is_approved = true,
    is_active = true,
    updated_at = now();

  -- 6. Upsert public.user_roles
  insert into public.user_roles (user_id, role, assigned_at)
  values (
    new.id,
    case when v_is_admin then 'ADMIN' else 'USER' end,
    now()
  )
  on conflict (user_id) do update set
    role = case when v_is_admin then 'ADMIN' else excluded.role end,
    assigned_at = now();

  return new;
exception
  when others then
    raise warning 'Error in on_auth_user_created_assign_role_and_profile: %', SQLERRM;
    return new;
end;
$$ language plpgsql security definer;

-- 5. Update claim_bearing_scan_reward with mandatory supplier details
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
  v_supp_name text := trim(coalesce(p_supplier_name, ''));
  v_supp_contact text := trim(coalesce(p_supplier_contact, ''));
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

  -- Enforce mandatory supplier details
  if v_supp_name = '' or v_supp_contact = '' then
    return jsonb_build_object(
      'reward_awarded', false,
      'error_code', 'SUPPLIER_DETAILS_REQUIRED',
      'message', 'Supplier Name and Contact Number are mandatory when claiming Reward Points.'
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

  -- 1. Fetch current reward settings
  select * into v_settings from public.reward_settings where id = 1;
  if not found or not v_settings.is_reward_system_enabled then
    return jsonb_build_object(
      'reward_awarded', false,
      'error_code', 'SYSTEM_DISABLED',
      'message', 'Reward points program is currently paused.'
    );
  end if;

  v_pts := coalesce(v_settings.points_per_first_scan, 10);
  v_base_unit := greatest(coalesce(v_settings.points_base_unit, 10), 1);
  v_inr_per_base := coalesce(v_settings.inr_per_base_unit, 10.00);
  v_rate_multiplier := v_inr_per_base / v_base_unit;
  v_amount_inr := round((v_pts * v_rate_multiplier), 2);

  -- 2. Anti-fraud daily scan velocity check
  select count(*) into v_scans_today
  from public.reward_transactions
  where user_id = v_user_id
    and transaction_type = 'FIRST_SCAN_REWARD'
    and created_at >= v_today_start;

  if v_scans_today >= v_settings.daily_max_scans_per_user then
    return jsonb_build_object(
      'reward_awarded', false,
      'error_code', 'DAILY_LIMIT_REACHED',
      'message', 'Daily scan reward limit reached (' || v_settings.daily_max_scans_per_user || ' scans/day).'
    );
  end if;

  -- 3. Row lock on qr_codes
  select * into v_qr
  from public.qr_codes
  where bearing_id = v_bearing_clean
     or payload_value = v_bearing_clean
     or payload_value = v_trimmed
     or bearing_id = upper(v_trimmed)
  for update;

  if not found then
    return jsonb_build_object(
      'reward_awarded', false,
      'error_code', 'BEARING_NOT_FOUND',
      'message', 'Bearing not found in official registry.'
    );
  end if;

  -- 4. Check if reward was already claimed on this bearing
  if v_qr.is_reward_claimed then
    return jsonb_build_object(
      'reward_awarded', false,
      'already_claimed', true,
      'bearing_id', v_qr.bearing_id,
      'claimed_at', v_qr.reward_claimed_at,
      'message', 'First-scan reward has already been claimed for this bearing.'
    );
  end if;

  -- 5. Mark bearing as reward claimed and save supplier details
  update public.qr_codes
  set is_reward_claimed = true,
      reward_claimed_by = v_user_id,
      reward_claimed_at = v_now,
      reward_source_module = p_source_module,
      supplier_name = v_supp_name,
      supplier_contact = v_supp_contact
  where id = v_qr.id;

  -- 6. Upsert user wallet atomically
  insert into public.user_reward_wallets (
    user_id,
    current_balance_points,
    total_points_earned,
    pending_redemption_points,
    total_points_redeemed,
    created_at,
    updated_at
  ) values (
    v_user_id,
    v_pts,
    v_pts,
    0,
    0,
    v_now,
    v_now
  )
  on conflict (user_id) do update set
    current_balance_points = public.user_reward_wallets.current_balance_points + v_pts,
    total_points_earned = public.user_reward_wallets.total_points_earned + v_pts,
    updated_at = v_now
  returning current_balance_points into v_new_balance;

  -- 7. Insert audit ledger entry with supplier details
  insert into public.reward_transactions (
    user_id,
    qr_code_id,
    bearing_id,
    transaction_type,
    points,
    points_base_unit,
    inr_per_base_unit,
    amount_inr,
    source_module,
    description,
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
    p_source_module,
    '1st Scan Reward Points Claimed (Supplier: ' || v_supp_name || ' / ' || v_supp_contact || ')',
    v_supp_name,
    v_supp_contact,
    v_now
  );

  return jsonb_build_object(
    'reward_awarded', true,
    'bearing_id', v_qr.bearing_id,
    'points_awarded', v_pts,
    'inr_value', v_amount_inr,
    'rate_display', v_base_unit || ' Points = ₹' || trim(to_char(v_inr_per_base, '999999990.00')),
    'new_balance', v_new_balance,
    'supplier_name', v_supp_name,
    'supplier_contact', v_supp_contact,
    'message', 'Congratulations! ' || v_pts || ' Reward Points added to your Pivot Wallet.'
  );
end;
$$ language plpgsql security definer;

