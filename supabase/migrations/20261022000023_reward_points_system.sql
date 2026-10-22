-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261022000023_reward_points_system.sql
-- High-Integrity Reward Points, Configurable Conversion Rate & Redemption Engine
-- ==============================================================================

-- 1. Extend qr_codes to track lifetime single-claim reward eligibility
alter table public.qr_codes 
add column if not exists is_reward_claimed boolean not null default false,
add column if not exists reward_claimed_by uuid references auth.users(id),
add column if not exists reward_claimed_at timestamptz,
add column if not exists reward_source_module text;

create index if not exists idx_qr_codes_is_reward_claimed on public.qr_codes(is_reward_claimed);
create index if not exists idx_qr_codes_reward_claimed_by on public.qr_codes(reward_claimed_by);

-- 2. Global Reward System Settings Table (Singleton Row id=1)
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

-- Seed default settings if not exists
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
  points_base_unit = coalesce(public.reward_settings.points_base_unit, 10),
  inr_per_base_unit = coalesce(public.reward_settings.inr_per_base_unit, 10.00),
  terms_and_conditions = 'Pivot Bearings reserves the right to modify, adjust, or change the reward point conversion value (Points to INR rate) and program rules at any time without prior notice.';

-- 3. User Reward Wallets (Point Balances)
create table if not exists public.user_reward_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  current_balance_points integer not null default 0 check (current_balance_points >= 0),
  total_points_earned integer not null default 0 check (total_points_earned >= 0),
  pending_redemption_points integer not null default 0 check (pending_redemption_points >= 0),
  total_points_redeemed integer not null default 0 check (total_points_redeemed >= 0),
  is_frozen boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 4. Reward Transactions (Immutable Financial Ledger)
create table if not exists public.reward_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  qr_code_id uuid references public.qr_codes(id) on delete set null,
  bearing_id text,
  transaction_type text not null check (
    transaction_type in (
      'FIRST_SCAN_REWARD',
      'REDEMPTION_ESCROW',
      'REDEMPTION_COMPLETED',
      'REDEMPTION_REVERTED',
      'ADMIN_ADJUSTMENT'
    )
  ),
  points integer not null, -- positive for credit, negative for debit
  points_base_unit integer not null default 10,
  inr_per_base_unit numeric(10, 2) not null,
  amount_inr numeric(10, 2) not null,
  source_module text not null, -- 'AUTHENTICATE_BEARING', 'TRACK_BEARING', 'WARRANTY_FLOW', 'ADMIN_PORTAL'
  description text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_reward_transactions_user_id on public.reward_transactions(user_id);
create index if not exists idx_reward_transactions_bearing_id on public.reward_transactions(bearing_id);

-- 5. Reward Redemptions (Payout Requests)
create table if not exists public.reward_redemptions (
  id uuid primary key default gen_random_uuid(),
  request_number text not null unique,
  user_id uuid not null references auth.users(id) on delete cascade,
  points_requested integer not null check (points_requested > 0),
  points_base_unit integer not null default 10,
  inr_per_base_unit numeric(10, 2) not null,
  amount_in_inr numeric(10, 2) not null,
  payout_method text not null check (payout_method in ('UPI', 'BANK_TRANSFER')),
  
  -- UPI Details
  upi_id text,
  
  -- Bank Details
  bank_account_number text,
  bank_ifsc text,
  bank_account_holder_name text,
  bank_name text,
  
  -- Lifecycle Status
  status text not null default 'PENDING' check (status in ('PENDING', 'PROCESSING', 'COMPLETED', 'REJECTED')),
  
  -- Settlement & Admin Audit Information
  payment_reference_id text, -- Bank UTR, UPI Ref ID (e.g. 423589123456)
  payment_mode text,          -- GPay, PhonePe, IMPS, NEFT, RTGS
  admin_notes text,           -- Admin payment completion notes or rejection reason
  actioned_by uuid references auth.users(id),
  actioned_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_reward_redemptions_user_id on public.reward_redemptions(user_id);
create index if not exists idx_reward_redemptions_status on public.reward_redemptions(status);

-- 6. Realtime Publication Sync for User Wallets & Redemptions
do $$
begin
  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and tablename = 'user_reward_wallets'
  ) then
    alter publication supabase_realtime add table public.user_reward_wallets;
  end if;

  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and tablename = 'reward_redemptions'
  ) then
    alter publication supabase_realtime add table public.reward_redemptions;
  end if;

  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and tablename = 'reward_settings'
  ) then
    alter publication supabase_realtime add table public.reward_settings;
  end if;
exception
  when others then null;
end $$;

-- 7. Stored Procedure: claim_bearing_scan_reward
-- Authoritative, atomic, cross-module 1st-scan reward claim engine
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

  -- 3. Row lock on qr_codes to guarantee single lifetime claim
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

  -- 5. Mark bearing as reward claimed
  update public.qr_codes
  set is_reward_claimed = true,
      reward_claimed_by = v_user_id,
      reward_claimed_at = v_now,
      reward_source_module = p_source_module
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

  -- 7. Insert audit ledger entry
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
    'First-scan reward earned on bearing ' || v_qr.bearing_id || ' via ' || p_source_module,
    v_now
  );

  return jsonb_build_object(
    'reward_awarded', true,
    'already_claimed', false,
    'bearing_id', v_qr.bearing_id,
    'points_earned', v_pts,
    'amount_inr', v_amount_inr,
    'points_base_unit', v_base_unit,
    'inr_per_base_unit', v_inr_per_base,
    'rate_display', v_base_unit || ' Points = ₹' || trim(to_char(v_inr_per_base, '999999990.00')),
    'new_balance', v_new_balance,
    'message', 'First-scan reward successfully claimed!'
  );
end;
$$ language plpgsql security definer;

-- 8. Stored Procedure: request_reward_redemption
-- Allows users to submit a withdrawal request, escrowing points atomically
create or replace function public.request_reward_redemption(
  p_points integer,
  p_payout_method text,
  p_upi_id text default null,
  p_bank_account text default null,
  p_bank_ifsc text default null,
  p_bank_holder_name text default null,
  p_bank_name text default null
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
begin
  if v_user_id is null then
    return jsonb_build_object('success', false, 'message', 'Unauthorized.');
  end if;

  if p_points is null or p_points <= 0 then
    return jsonb_build_object('success', false, 'message', 'Invalid points requested.');
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
    'PENDING',
    v_now,
    v_now
  ) returning id into v_redemption_id;

  -- 6. Log to immutable ledger
  insert into public.reward_transactions (
    user_id,
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
    'REDEMPTION_ESCROW',
    -p_points,
    v_base_unit,
    v_inr_per_base,
    v_amount_inr,
    'USER_WALLET',
    'Redemption request ' || v_req_num || ' placed into escrow (' || p_points || ' pts = ₹' || v_amount_inr || ')',
    v_now
  );

  return jsonb_build_object(
    'success', true,
    'request_number', v_req_num,
    'points_requested', p_points,
    'amount_in_inr', v_amount_inr,
    'status', 'PENDING',
    'message', 'Redemption request submitted successfully! An administrator will review and process your payout.'
  );
end;
$$ language plpgsql security definer;

-- 9. Stored Procedure: admin_process_redemption
-- Allows administrators to approve with UTR / Payment notes or reject with mandatory reason
create or replace function public.admin_process_redemption(
  p_redemption_id uuid,
  p_action text, -- 'APPROVE' or 'REJECT'
  p_payment_ref text default null,
  p_payment_mode text default null,
  p_notes text default null
)
returns jsonb as $$
declare
  v_admin_id uuid := auth.uid();
  v_is_admin boolean := false;
  v_redemption record;
  v_now timestamptz := now();
begin
  -- Validate caller is admin
  select (role = 'ADMIN') into v_is_admin
  from public.user_roles
  where user_id = v_admin_id;

  if not coalesce(v_is_admin, false) then
    return jsonb_build_object('success', false, 'message', 'Unauthorized. Admin privilege required.');
  end if;

  select * into v_redemption
  from public.reward_redemptions
  where id = p_redemption_id
  for update;

  if not found then
    return jsonb_build_object('success', false, 'message', 'Redemption request not found.');
  end if;

  if v_redemption.status <> 'PENDING' and v_redemption.status <> 'PROCESSING' then
    return jsonb_build_object('success', false, 'message', 'This request has already been finalized as ' || v_redemption.status || '.');
  end if;

  if upper(p_action) = 'APPROVE' then
    -- Mark Completed
    update public.reward_redemptions
    set status = 'COMPLETED',
        payment_reference_id = nullif(trim(p_payment_ref), ''),
        payment_mode = coalesce(nullif(trim(p_payment_mode), ''), 'DIRECT_TRANSFER'),
        admin_notes = nullif(trim(p_notes), ''),
        actioned_by = v_admin_id,
        actioned_at = v_now,
        updated_at = v_now
    where id = p_redemption_id;

    -- Release escrow points and increment total redeemed
    update public.user_reward_wallets
    set pending_redemption_points = greatest(pending_redemption_points - v_redemption.points_requested, 0),
        total_points_redeemed = total_points_redeemed + v_redemption.points_requested,
        updated_at = v_now
    where user_id = v_redemption.user_id;

    -- Insert ledger record
    insert into public.reward_transactions (
      user_id,
      transaction_type,
      points,
      points_base_unit,
      inr_per_base_unit,
      amount_inr,
      source_module,
      description,
      created_at
    ) values (
      v_redemption.user_id,
      'REDEMPTION_COMPLETED',
      -v_redemption.points_requested,
      v_redemption.points_base_unit,
      v_redemption.inr_per_base_unit,
      v_redemption.amount_in_inr,
      'ADMIN_PORTAL',
      'Payout confirmed for ' || v_redemption.request_number || ' (Ref: ' || coalesce(p_payment_ref, 'N/A') || ')',
      v_now
    );

    return jsonb_build_object(
      'success', true,
      'status', 'COMPLETED',
      'message', 'Payout successfully recorded as completed.'
    );

  elsif upper(p_action) = 'REJECT' then
    if p_notes is null or trim(p_notes) = '' then
      return jsonb_build_object('success', false, 'message', 'Rejection reason note is required.');
    end if;

    update public.reward_redemptions
    set status = 'REJECTED',
        admin_notes = trim(p_notes),
        actioned_by = v_admin_id,
        actioned_at = v_now,
        updated_at = v_now
    where id = p_redemption_id;

    -- Restore points back to current balance from escrow
    update public.user_reward_wallets
    set pending_redemption_points = greatest(pending_redemption_points - v_redemption.points_requested, 0),
        current_balance_points = current_balance_points + v_redemption.points_requested,
        updated_at = v_now
    where user_id = v_redemption.user_id;

    -- Insert ledger record
    insert into public.reward_transactions (
      user_id,
      transaction_type,
      points,
      points_base_unit,
      inr_per_base_unit,
      amount_inr,
      source_module,
      description,
      created_at
    ) values (
      v_redemption.user_id,
      'REDEMPTION_REVERTED',
      v_redemption.points_requested,
      v_redemption.points_base_unit,
      v_redemption.inr_per_base_unit,
      v_redemption.amount_in_inr,
      'ADMIN_PORTAL',
      'Points refunded for rejected request ' || v_redemption.request_number || ' (Reason: ' || trim(p_notes) || ')',
      v_now
    );

    return jsonb_build_object(
      'success', true,
      'status', 'REJECTED',
      'message', 'Redemption request rejected and points refunded to user wallet.'
    );
  else
    return jsonb_build_object('success', false, 'message', 'Unknown action.');
  end if;
end;
$$ language plpgsql security definer;

-- 10. Stored Procedure: admin_update_reward_settings
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
  select (role = 'ADMIN') into v_is_admin
  from public.user_roles
  where user_id = v_admin_id;

  if not coalesce(v_is_admin, false) then
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

-- 11. Stored Procedure: get_user_reward_profile
create or replace function public.get_user_reward_profile()
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_wallet record;
  v_settings record;
  v_base_unit integer;
  v_inr_per_base numeric(10, 2);
  v_rate_multiplier numeric(10, 4);
begin
  if v_user_id is null then
    return jsonb_build_object('authenticated', false);
  end if;

  select * into v_settings from public.reward_settings where id = 1;
  v_base_unit := greatest(coalesce(v_settings.points_base_unit, 10), 1);
  v_inr_per_base := coalesce(v_settings.inr_per_base_unit, 10.00);
  v_rate_multiplier := v_inr_per_base / v_base_unit;

  select * into v_wallet
  from public.user_reward_wallets
  where user_id = v_user_id;

  return jsonb_build_object(
    'authenticated', true,
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

-- 12. RLS Security Policies
alter table public.reward_settings enable row level security;
alter table public.user_reward_wallets enable row level security;
alter table public.reward_transactions enable row level security;
alter table public.reward_redemptions enable row level security;

-- Settings policies
drop policy if exists "Anyone can read reward_settings" on public.reward_settings;
create policy "Anyone can read reward_settings" 
on public.reward_settings for select 
to authenticated 
using (true);

drop policy if exists "Admins can update reward_settings" on public.reward_settings;
create policy "Admins can update reward_settings" 
on public.reward_settings for all 
to authenticated 
using (
  exists (select 1 from public.user_roles where user_id = auth.uid() and role = 'ADMIN')
);

-- Wallets policies
drop policy if exists "Users view own wallet" on public.user_reward_wallets;
create policy "Users view own wallet" 
on public.user_reward_wallets for select 
to authenticated 
using (
  user_id = auth.uid() or 
  exists (select 1 from public.user_roles where user_id = auth.uid() and role = 'ADMIN')
);

-- Transactions policies
drop policy if exists "Users view own transactions" on public.reward_transactions;
create policy "Users view own transactions" 
on public.reward_transactions for select 
to authenticated 
using (
  user_id = auth.uid() or 
  exists (select 1 from public.user_roles where user_id = auth.uid() and role = 'ADMIN')
);

-- Redemptions policies
drop policy if exists "Users view own redemptions" on public.reward_redemptions;
create policy "Users view own redemptions" 
on public.reward_redemptions for select 
to authenticated 
using (
  user_id = auth.uid() or 
  exists (select 1 from public.user_roles where user_id = auth.uid() and role = 'ADMIN')
);

drop policy if exists "Users insert own redemptions" on public.reward_redemptions;
create policy "Users insert own redemptions" 
on public.reward_redemptions for insert 
to authenticated 
with check (user_id = auth.uid());

drop policy if exists "Admins manage all redemptions" on public.reward_redemptions;
create policy "Admins manage all redemptions" 
on public.reward_redemptions for all 
to authenticated 
using (
  exists (select 1 from public.user_roles where user_id = auth.uid() and role = 'ADMIN')
);
