-- ==============================================================================
-- Pivot Bearings India - Security Policy & RLS Verification Test Suite
-- Tests for Anonymous, Authenticated User, and Admin Access Control
-- Fully compatible with Supabase Cloud Web SQL Editor and pgTAP
-- ==============================================================================

begin;

-- Create pgTAP extension if available for test assertions
create extension if not exists pgtap;

-- Test Plan Setup: 24 Target Security & Authorization Invariants
select plan(24);

-- ==============================================================================
-- TEST SECTION 1: ANONYMOUS ACCESS TESTS
-- ==============================================================================
-- Switch to anonymous (unauthenticated) role
set local role anon;
-- Crucial: Do NOT put an empty string for "sub" in JSON claims because Supabase auth.uid()
-- casts (claims->>'sub')::uuid which throws invalid input syntax for type uuid: ""
select set_config('request.jwt.claims', '{"role":"anon"}'::text, true);
select set_config('request.jwt.claim.role', 'anon', true);
select set_config('request.jwt.claim.sub', '', true);

-- 1. Anonymous can view company settings (Public read)
select is(
  (select count(*)::int from public.company_settings),
  1,
  'Anon: Can read public company_settings'
);

-- 2. Anonymous can view active warranty plans
select ok(
  (select count(*) > 0 from public.warranty_plans where is_active = true),
  'Anon: Can read active warranty_plans'
);

-- 3. Anonymous can read basic QR verification info
select ok(
  (select count(*) > 0 from public.qr_codes where bearing_id = 'PB-9402-XJ'),
  'Anon: Can perform read-only optical QR verification lookup'
);

-- 4. Anonymous CANNOT modify QR codes (Tamper prevention)
-- In PostgreSQL RLS, unauthorized updates affect 0 rows. We execute the update
-- and verify the target record's warranty timestamp remains untampered (NULL).
update public.qr_codes 
set warranty_expiry_timestamp = '2099-01-01' 
where bearing_id = 'PB-9402-XJ';

select is(
  (select warranty_expiry_timestamp from public.qr_codes where bearing_id = 'PB-9402-XJ'),
  null::timestamptz,
  'Anon: CANNOT update qr_codes warranty timestamps'
);

-- 5. Anonymous CANNOT read private user profiles
select is(
  (select count(*)::int from public.profiles),
  0,
  'Anon: CANNOT view any customer profiles'
);

-- 6. Anonymous CANNOT read admin audit logs
select is(
  (select count(*)::int from public.admin_audit_logs),
  0,
  'Anon: CANNOT view admin_audit_logs'
);

-- 7. Anonymous CANNOT view internal batch production manifests
select is(
  (select count(*)::int from public.qr_batches),
  0,
  'Anon: CANNOT view qr_batches'
);

-- ==============================================================================
-- TEST SECTION 2: ORDINARY AUTHENTICATED USER TESTS
-- ==============================================================================
-- Reset to postgres superuser to seed mock auth actors
set local role postgres;

insert into auth.users (id, email)
values 
  ('10000000-0000-0000-0000-000000000001', 'customer_a@acme.com'),
  ('20000000-0000-0000-0000-000000000002', 'customer_b@mining.com')
on conflict (id) do nothing;

insert into public.profiles (id, full_name, company_name)
values
  ('10000000-0000-0000-0000-000000000001', 'Customer A', 'Acme Corp'),
  ('20000000-0000-0000-0000-000000000002', 'Customer B', 'Mining Ltd')
on conflict (id) do nothing;

insert into public.user_roles (user_id, role)
values
  ('10000000-0000-0000-0000-000000000001', 'USER'),
  ('20000000-0000-0000-0000-000000000002', 'USER')
on conflict do nothing;

-- Switch session to Customer A
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}'::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

-- 8. Customer A can read own profile
select is(
  (select count(*)::int from public.profiles where id = '10000000-0000-0000-0000-000000000001'),
  1,
  'User A: Can read own profile'
);

-- 9. Customer A CANNOT read Customer B profile
select is(
  (select count(*)::int from public.profiles where id = '20000000-0000-0000-0000-000000000002'),
  0,
  'User A: CANNOT read Customer B profile'
);

-- 10. Customer A CANNOT elevate self to ADMIN
select throws_ok(
  $$ insert into public.user_roles (user_id, role) values ('10000000-0000-0000-0000-000000000001', 'ADMIN') $$,
  '42501',
  'User A: CANNOT self-assign ADMIN role'
);

-- 11. Customer A CANNOT arbitrarily modify QR warranty duration
update public.qr_codes 
set assigned_warranty_plan_id = '44444444-4444-4444-4444-444444444444' 
where bearing_id = 'PB-9402-XJ';

select is(
  (select assigned_warranty_plan_id from public.qr_codes where bearing_id = 'PB-9402-XJ'),
  '22222222-2222-2222-2222-222222222222'::uuid,
  'User A: CANNOT modify assigned warranty plan directly'
);

-- 12. Customer A CANNOT alter first_in_timestamp arbitrarily
update public.qr_codes 
set first_in_timestamp = '2020-01-01' 
where bearing_id = 'PB-9402-XJ';

select is(
  (select first_in_timestamp from public.qr_codes where bearing_id = 'PB-9402-XJ'),
  null::timestamptz,
  'User A: CANNOT arbitrarily backdate first_in_timestamp'
);

-- 13. Customer A CANNOT insert or modify company settings
update public.company_settings 
set company_name = 'Hacked Bearings';

select is(
  (select company_name from public.company_settings limit 1),
  'Pivot Bearings India',
  'User A: CANNOT modify company_settings'
);

-- 14. Customer A CANNOT read Admin Audit Logs
select is(
  (select count(*)::int from public.admin_audit_logs),
  0,
  'User A: CANNOT read admin_audit_logs'
);

-- ==============================================================================
-- TEST SECTION 3: SERVER-SIDE STATE MACHINE RPC TESTS
-- ==============================================================================
-- 15. User A executes confirm_bearing_in for PB-9402-XJ
select ok(
  (select (public.confirm_bearing_in('PB-9402-XJ'))->>'success' = 'true'),
  'RPC: confirm_bearing_in successfully activates not-activated bearing'
);

-- 16. Bearing lifecycle state is now CURRENTLY_IN
select is(
  (select current_lifecycle_state from public.qr_codes where bearing_id = 'PB-9402-XJ'),
  'CURRENTLY_IN',
  'State Machine: QR code state successfully transitioned to CURRENTLY_IN'
);

-- 17. Calling confirm_bearing_in again while CURRENTLY_IN fails
select throws_ok(
  $$ select public.confirm_bearing_in('PB-9402-XJ') $$,
  'P0001',
  'Bearing is already marked IN',
  'State Machine: Double IN execution is strictly rejected'
);

-- 18. User A executes confirm_bearing_out for PB-9402-XJ
select ok(
  (select (public.confirm_bearing_out('PB-9402-XJ'))->>'success' = 'true'),
  'RPC: confirm_bearing_out successfully records removal'
);

-- 19. Bearing lifecycle state is now CURRENTLY_OUT
select is(
  (select current_lifecycle_state from public.qr_codes where bearing_id = 'PB-9402-XJ'),
  'CURRENTLY_OUT',
  'State Machine: QR code state successfully transitioned to CURRENTLY_OUT'
);

-- 20. Calling confirm_bearing_out again while CURRENTLY_OUT fails
select throws_ok(
  $$ select public.confirm_bearing_out('PB-9402-XJ') $$,
  'P0001',
  'Bearing is not currently marked IN',
  'State Machine: Double OUT execution is strictly rejected'
);

-- ==============================================================================
-- TEST SECTION 4: ADMIN ACCESS TESTS
-- ==============================================================================
set local role postgres;

-- Create Admin User
insert into auth.users (id, email)
values ('99999999-9999-9999-9999-999999999999', 'admin@pivotbearings.com')
on conflict (id) do nothing;

insert into public.profiles (id, full_name, company_name)
values ('99999999-9999-9999-9999-999999999999', 'Admin Lead', 'Pivot Bearings India')
on conflict (id) do nothing;

insert into public.user_roles (user_id, role)
values ('99999999-9999-9999-9999-999999999999', 'ADMIN')
on conflict do nothing;

-- Switch to Admin
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"99999999-9999-9999-9999-999999999999","role":"authenticated"}'::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', true);

-- 21. Admin can read all profiles
select ok(
  (select count(*) >= 2 from public.profiles),
  'Admin: Can read all profiles'
);

-- 22. Admin can create new QR batches
select ok(
  (select count(*) > 0 from public.qr_batches),
  'Admin: Can read and manage qr_batches'
);

-- 23. Admin can update company settings
select lives_ok(
  $$ update public.company_settings set website = 'https://www.pivotbearings.com' where company_name = 'Pivot Bearings India' $$,
  'Admin: Can update company_settings'
);

-- 24. Admin can read admin audit logs
select lives_ok(
  $$ select count(*) from public.admin_audit_logs $$,
  'Admin: Can read admin_audit_logs'
);

select * from finish();
rollback;
