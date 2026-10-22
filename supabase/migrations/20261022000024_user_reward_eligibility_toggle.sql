-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261022000024_user_reward_eligibility_toggle.sql
-- Admin Reward Points Eligibility Control & Non-Offensive Block Handling
-- ==============================================================================

-- 1. Add is_reward_eligible column to public.profiles (Default TRUE for all existing & new users)
alter table public.profiles 
add column if not exists is_reward_eligible boolean not null default true;

create index if not exists idx_profiles_reward_eligible on public.profiles(is_reward_eligible);

-- 2. Update handle_new_auth_user trigger function to guarantee new users default to is_reward_eligible = true
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_company_name text;
  v_phone text;
  v_full_name text;
  v_facility_code text;
  v_email text;
  v_is_admin boolean;
begin
  -- 1. Extract clean user email
  v_email := lower(trim(coalesce(new.email, '')));
  v_is_admin := (v_email = 'abc@gmail.com' or v_email like '%admin%');

  -- 2. Extract company name and phone from signup metadata
  v_company_name := coalesce(nullif(trim(new.raw_user_meta_data->>'company_name'), ''), 'Corporate Account');
  v_phone := nullif(trim(new.raw_user_meta_data->>'phone'), '');

  -- 3. Extract display full name
  v_full_name := coalesce(
    nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
    nullif(trim(new.raw_user_meta_data->>'company_name'), ''),
    nullif(split_part(v_email, '@', 1), ''),
    'Operator'
  );

  -- 4. Generate facility code
  v_facility_code := coalesce(
    nullif(trim(new.raw_user_meta_data->>'facility_code'), ''),
    concat('FAC-', upper(substring(regexp_replace(coalesce(v_company_name, 'REG'), '[^a-zA-Z0-9]', '', 'g') from 1 for 4)))
  );

  -- 5. Upsert into public.profiles
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
    v_is_admin,
    true,
    v_is_admin,
    v_is_admin,
    true, -- Eligible for rewards by default
    now(),
    now()
  )
  on conflict (id) do update set
    email = coalesce(excluded.email, public.profiles.email),
    full_name = coalesce(nullif(excluded.full_name, ''), public.profiles.full_name),
    phone = coalesce(excluded.phone, public.profiles.phone),
    company_name = coalesce(nullif(excluded.company_name, ''), public.profiles.company_name),
    facility_code = coalesce(nullif(excluded.facility_code, ''), public.profiles.facility_code),
    is_approved = case when v_is_admin then true else public.profiles.is_approved end,
    has_warranty_access = case when v_is_admin then true else public.profiles.has_warranty_access end,
    has_track_bearing_access = case when v_is_admin then true else public.profiles.has_track_bearing_access end,
    is_reward_eligible = coalesce(public.profiles.is_reward_eligible, true),
    updated_at = now();

  -- 6. Guarantee record in public.user_roles
  insert into public.user_roles (user_id, role, assigned_at)
  values (
    new.id,
    case when v_is_admin then 'ADMIN' else 'USER' end,
    now()
  )
  on conflict (user_id) do update set
    role = case
      when public.user_roles.role = 'ADMIN' then 'ADMIN'
      when v_is_admin then 'ADMIN'
      else public.user_roles.role
    end;

  return new;
exception
  when others then
    raise warning 'handle_new_auth_user notice: %', sqlerrm;
    return new;
end;
$$;

-- 3. Stored Procedure: admin_update_user_reward_eligibility
-- Allows administrators to toggle reward points eligibility for any customer from the Customers View
create or replace function public.admin_update_user_reward_eligibility(
  p_target_user_id uuid,
  p_is_eligible boolean
)
returns jsonb as $$
declare
  v_admin_id uuid := auth.uid();
begin
  -- Validate caller has Administrator permissions
  if not public.is_admin(v_admin_id) then
    raise exception 'Unauthorized: Only administrators can update reward points eligibility.'
      using errcode = '42501';
  end if;

  -- Update profiles table
  update public.profiles
  set is_reward_eligible = coalesce(p_is_eligible, true),
      updated_at = now()
  where id = p_target_user_id;

  -- Also update user_reward_wallets frozen state if wallet exists
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

grant execute on function public.admin_update_user_reward_eligibility(uuid, boolean) to authenticated;

-- 4. Update claim_bearing_scan_reward to verify user reward eligibility
create or replace function public.claim_bearing_scan_reward(
  p_bearing_id text,
  p_source_module text default 'AUTHENTICATE_BEARING'
)
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_trimmed text := trim(coalesce(p_bearing_id, ''));
  v_bearing_clean text;
  v_qr record;
  v_settings record;
  v_is_eligible boolean := true;
  v_pts integer;
  v_base_unit integer;
  v_inr_per_base numeric(10, 2);
  v_amount_inr numeric(10, 2);
  v_rate_multiplier numeric(10, 4);
  v_today_start timestamptz := date_trunc('day', now());
  v_scans_today integer := 0;
  v_now timestamptz := now();
  v_new_balance integer := 0;
begin
  if v_user_id is null then
    return jsonb_build_object(
      'reward_awarded', false,
      'is_user_blocked', false,
      'error_code', 'UNAUTHORIZED',
      'message', 'User must be logged in to claim rewards.'
    );
  end if;

  if v_trimmed = '' then
    return jsonb_build_object(
      'reward_awarded', false,
      'is_user_blocked', false,
      'error_code', 'EMPTY_IDENTIFIER',
      'message', 'Invalid bearing identifier.'
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

  -- 1. Check if user is eligible for rewards
  select coalesce(is_reward_eligible, true) into v_is_eligible
  from public.profiles
  where id = v_user_id;

  -- 2. Fetch current reward settings
  select * into v_settings from public.reward_settings where id = 1;
  if not found or not v_settings.is_reward_system_enabled then
    return jsonb_build_object(
      'reward_awarded', false,
      'is_user_blocked', false,
      'error_code', 'SYSTEM_DISABLED',
      'message', 'Reward points program is currently paused.'
    );
  end if;

  v_pts := coalesce(v_settings.points_per_first_scan, 10);
  v_base_unit := greatest(coalesce(v_settings.points_base_unit, 10), 1);
  v_inr_per_base := coalesce(v_settings.inr_per_base_unit, 10.00);
  v_rate_multiplier := v_inr_per_base / v_base_unit;
  v_amount_inr := round((v_pts * v_rate_multiplier), 2);

  -- 3. Row lock on qr_codes to verify bearing existence
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
      'is_user_blocked', false,
      'error_code', 'BEARING_NOT_FOUND',
      'message', 'Bearing not found in official registry.'
    );
  end if;

  -- 4. Check if user is blocked from receiving reward points
  -- Non-offensive, polite response that affirms bearing authenticity while explaining rewards status
  if not coalesce(v_is_eligible, true) then
    return jsonb_build_object(
      'reward_awarded', false,
      'is_user_blocked', true,
      'already_claimed', coalesce(v_qr.is_reward_claimed, false),
      'bearing_id', v_qr.bearing_id,
      'points_earned', 0,
      'amount_inr', 0.00,
      'rate_display', v_base_unit || ' Points = ₹' || trim(to_char(v_inr_per_base, '999999990.00')),
      'message', 'Bearing verified authentic. Promotional reward points are currently inactive for this account profile.'
    );
  end if;

  -- 5. Anti-fraud daily scan velocity check
  select count(*) into v_scans_today
  from public.reward_transactions
  where user_id = v_user_id
    and transaction_type = 'FIRST_SCAN_REWARD'
    and created_at >= v_today_start;

  if v_scans_today >= v_settings.daily_max_scans_per_user then
    return jsonb_build_object(
      'reward_awarded', false,
      'is_user_blocked', false,
      'error_code', 'DAILY_LIMIT_REACHED',
      'message', 'Daily scan reward limit reached (' || v_settings.daily_max_scans_per_user || ' scans/day).'
    );
  end if;

  -- 6. Check if reward was already claimed on this bearing
  if v_qr.is_reward_claimed then
    return jsonb_build_object(
      'reward_awarded', false,
      'is_user_blocked', false,
      'already_claimed', true,
      'bearing_id', v_qr.bearing_id,
      'claimed_at', v_qr.reward_claimed_at,
      'message', 'First-scan reward has already been claimed for this bearing.'
    );
  end if;

  -- 7. Mark bearing as reward claimed
  update public.qr_codes
  set is_reward_claimed = true,
      reward_claimed_by = v_user_id,
      reward_claimed_at = v_now,
      reward_source_module = p_source_module
  where id = v_qr.id;

  -- 8. Upsert user wallet atomically
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

  -- 9. Insert audit ledger entry
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
    '1st scan reward awarded for bearing ' || v_qr.bearing_id || ' via ' || p_source_module,
    v_now
  );

  return jsonb_build_object(
    'reward_awarded', true,
    'is_user_blocked', false,
    'already_claimed', false,
    'bearing_id', v_qr.bearing_id,
    'points_earned', v_pts,
    'amount_inr', v_amount_inr,
    'rate_display', v_base_unit || ' Points = ₹' || trim(to_char(v_inr_per_base, '999999990.00')),
    'new_balance', v_new_balance,
    'message', 'Congratulations! 1st scan reward of ' || v_pts || ' points credited to your wallet.'
  );
end;
$$ language plpgsql security definer;

-- 5. Update get_user_reward_profile to return is_reward_eligible
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

-- 6. Relax duration_months check constraint to allow 0 (No Warranty) and insert '0 Month Warranty' plan
alter table public.warranty_plans 
  drop constraint if exists warranty_plans_duration_months_check;

alter table public.warranty_plans 
  add constraint warranty_plans_duration_months_check check (duration_months >= 0);

insert into public.warranty_plans (id, plan_code, title, duration_months, description)
values ('00000000-0000-0000-0000-000000000000', 'WP-0M', '0 Month Warranty', 0, 'No warranty coverage assigned')
on conflict (plan_code) do update set
  title = excluded.title,
  duration_months = excluded.duration_months;


