-- ==============================================================================
-- Pivot Bearings India - Lifecycle State Machine & Warranty Test Suite
-- Tests for: First IN, Duplicate IN, OUT before IN, Normal OUT, Duplicate OUT,
-- Re-installation, Cycle History Preservation, OUT After Expiry, and Leap Years.
-- ==============================================================================

begin;

-- Create pgTAP extension
create extension if not exists pgtap;

-- Set up test plan: 15 targeted invariants
select plan(15);

-- 1. Setup authenticated test operator
set local role postgres;

-- Ensure migration column exists
alter table public.bearing_installation_cycles 
  add column if not exists was_warranty_active_at_out boolean;

insert into auth.users (id, email)
values ('30000000-0000-0000-0000-000000000003', 'operator@factory.com')
on conflict (id) do nothing;

insert into public.profiles (id, full_name, company_name)
values ('30000000-0000-0000-0000-000000000003', 'Field Operator', 'Tata Steel')
on conflict (id) do nothing;

insert into public.user_roles (user_id, role)
values ('30000000-0000-0000-0000-000000000003', 'USER')
on conflict do nothing;

-- Switch to Operator
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"30000000-0000-0000-0000-000000000003","role":"authenticated"}'::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000003', true);

-- ------------------------------------------------------------------------------
-- TEST 1: OUT Before First IN is Strictly Rejected
-- ------------------------------------------------------------------------------
select throws_ok(
  $$ select public.confirm_bearing_out('PB-9402-XJ') $$,
  '55002',
  'Cannot record OUT event before first IN',
  'Invariant 1: OUT before first IN is strictly rejected'
);

-- ------------------------------------------------------------------------------
-- TEST 2: First Confirmed IN Activates Warranty and Starts Cycle 1
-- ------------------------------------------------------------------------------
select ok(
  (select (public.confirm_bearing_in('PB-9402-XJ'))->>'is_first_activation' = 'true'),
  'Invariant 2: First IN sets is_first_activation = true'
);

select is(
  (select current_lifecycle_state from public.qr_codes where bearing_id = 'PB-9402-XJ'),
  'CURRENTLY_IN',
  'Invariant 3: Lifecycle state transitioned to CURRENTLY_IN'
);

select ok(
  (select first_in_timestamp is not null and warranty_expiry_timestamp is not null 
   from public.qr_codes where bearing_id = 'PB-9402-XJ'),
  'Invariant 4: Warranty start and expiry timestamps successfully anchored'
);

-- ------------------------------------------------------------------------------
-- TEST 3: Duplicate IN Attempt is Strictly Rejected
-- ------------------------------------------------------------------------------
select throws_ok(
  $$ select public.confirm_bearing_in('PB-9402-XJ') $$,
  '55001',
  'already marked IN and currently operating',
  'Invariant 5: Duplicate IN rejected while bearing is operating'
);

-- ------------------------------------------------------------------------------
-- TEST 4: Confirmed OUT Closes Cycle 1 and Calculates Duration
-- ------------------------------------------------------------------------------
select ok(
  (select (public.confirm_bearing_out('PB-9402-XJ'))->>'action' = 'MARKED_OUT'),
  'Invariant 6: OUT confirmation returns action MARKED_OUT'
);

select is(
  (select current_lifecycle_state from public.qr_codes where bearing_id = 'PB-9402-XJ'),
  'CURRENTLY_OUT',
  'Invariant 7: Lifecycle state transitioned to CURRENTLY_OUT'
);

select is(
  (select is_cycle_closed from public.bearing_installation_cycles 
   where qr_code_id = (select id from public.qr_codes where bearing_id = 'PB-9402-XJ') and cycle_number = 1),
  true,
  'Invariant 8: Installation cycle 1 is officially closed'
);

-- ------------------------------------------------------------------------------
-- TEST 5: Duplicate OUT Attempt is Strictly Rejected
-- ------------------------------------------------------------------------------
select throws_ok(
  $$ select public.confirm_bearing_out('PB-9402-XJ') $$,
  '55003',
  'not currently marked IN',
  'Invariant 9: Duplicate OUT rejected when bearing is already removed'
);

-- ------------------------------------------------------------------------------
-- TEST 6: Re-installation (Subsequent IN) Opens Cycle 2 and Preserves Anchor
-- ------------------------------------------------------------------------------
select ok(
  (select (public.confirm_bearing_in('PB-9402-XJ'))->>'cycle_number' = '2'),
  'Invariant 10: Re-installation successfully creates cycle 2'
);

select is(
  (select count(*)::int from public.bearing_installation_cycles 
   where qr_code_id = (select id from public.qr_codes where bearing_id = 'PB-9402-XJ')),
  2,
  'Invariant 11: History preserved: Both cycle 1 and cycle 2 exist simultaneously'
);

-- ------------------------------------------------------------------------------
-- TEST 7: Calendar Month & Leap Year Arithmetic Validation
-- ------------------------------------------------------------------------------
-- Leap Year End of Feb: 2024-02-29 + 12 months = 2025-02-28
select is(
  ('2024-02-29 10:00:00+00'::timestamptz + (12 || ' months')::interval)::date,
  '2025-02-28'::date,
  'Invariant 12: Leap year end-of-Feb 12-month interval accurately resolves to Feb 28'
);

-- Month-end arithmetic: 2024-01-31 + 1 month = 2024-02-29 (leap year Feb)
select is(
  ('2024-01-31 10:00:00+00'::timestamptz + (1 || ' months')::interval)::date,
  '2024-02-29'::date,
  'Invariant 13: January 31 + 1 month accurately resolves to February 29 in leap year'
);

-- ------------------------------------------------------------------------------
-- TEST 8: OUT Remains Fully Possible After Warranty Expiry
-- ------------------------------------------------------------------------------
-- Artificially simulate warranty expiration by updating expiry anchor in test transaction
set local role postgres;
update public.qr_codes 
set warranty_expiry_timestamp = now() - interval '10 days'
where bearing_id = 'PB-9402-XJ';

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"30000000-0000-0000-0000-000000000003","role":"authenticated"}'::text, true);

select ok(
  (select (public.confirm_bearing_out('PB-9402-XJ'))->>'success' = 'true'),
  'Invariant 14: Confirmed OUT succeeds seamlessly even when warranty is expired'
);

select is(
  (select was_warranty_active_at_out from public.bearing_installation_cycles 
   where qr_code_id = (select id from public.qr_codes where bearing_id = 'PB-9402-XJ') and cycle_number = 2),
  false,
  'Invariant 15: Cycle 2 accurately recorded was_warranty_active_at_out = false'
);

select * from finish();
rollback;
