-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261010000003_seed_data.sql
-- Seed baseline data for company settings, warranty horizons, and batches
-- ==============================================================================

-- 1. Insert Company Settings
insert into public.company_settings (
  company_name,
  gst_number,
  address,
  contact_email,
  contact_phone,
  website,
  logo_storage_path
) values (
  'Pivot Bearings India',
  '27AABCP1234F1ZQ',
  'Plot 42, Sector 10, PCMC Industrial Zone, Pune, Maharashtra 411019, India',
  'pivotbearings@gmail.com',
  '+91 98988 57198',
  'https://www.pivotbearingsindia.com/',
  'assets/webappicon.png'
)
on conflict do nothing;

-- 2. Insert Standard Warranty Plans
insert into public.warranty_plans (id, plan_code, title, duration_months, description)
values 
  ('11111111-1111-1111-1111-111111111111', 'WP-3M', '3 Months Standard Warranty', 3, 'Standard factory replacement warranty for light radial loads'),
  ('22222222-2222-2222-2222-222222222222', 'WP-6M', '6 Months Heavy Duty Warranty', 6, 'Standard factory warranty for deep groove and cylindrical roller assemblies'),
  ('33333333-3333-3333-3333-333333333333', 'WP-12M', '12 Months Industrial Warranty', 12, 'High-tolerance engineering assurance for continuous operating environments'),
  ('44444444-4444-4444-4444-444444444444', 'WP-24M', '24 Months Extended Mining Warranty', 24, 'Extended protection for severe vibratory, mining, and wind generator equipment')
on conflict (plan_code) do update set
  title = excluded.title,
  duration_months = excluded.duration_months;

-- 3. Insert Application Settings
insert into public.app_settings (setting_key, setting_value, description, is_public)
values
  ('telemetry_refresh_interval_seconds', '10'::jsonb, 'Dashboard synchronization frequency', true),
  ('qr_scan_rate_limit_per_minute', '60'::jsonb, 'Rate limit per IP address for optical validation', false),
  ('max_verification_image_size_bytes', '5242880'::jsonb, 'Maximum proof photo upload size (5MB)', false),
  ('cryptographic_hash_standard', '"SHA-256"'::jsonb, 'Tamper-evident checksum standard', true)
on conflict (setting_key) do update set
  setting_value = excluded.setting_value;

-- 4. Insert Seed Production Batch
insert into public.qr_batches (
  id,
  batch_code,
  plant_location,
  lot_date,
  total_quantity,
  default_warranty_plan_id,
  status
) values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'BATCH-2026-OCT-A',
  'Plant 02 — Chakan Industrial Complex',
  '2026-10-24',
  10000,
  '22222222-2222-2222-2222-222222222222',
  'ACTIVE'
)
on conflict (batch_code) do nothing;

-- 5. Insert Seed Bearing QR Assets
-- Notice: We store string payloads and hashes ONLY. No QR image files are stored.
insert into public.qr_codes (
  id,
  bearing_id,
  batch_id,
  model_number,
  payload_value,
  payload_hash,
  assigned_warranty_plan_id,
  current_lifecycle_state
) values 
  (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0001',
    'PB-9402-XJ',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'PBI-6204-ZZ',
    'https://verify.pivotbearings.com/pbi/PB-9402-XJ?batch=BATCH-2026-OCT-A&m=PBI-6204-ZZ&w=6',
    'SHA-256: 4F92E389B01A9402',
    '22222222-2222-2222-2222-222222222222',
    'NOT_ACTIVATED'
  ),
  (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0002',
    'PB-8812-KR',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'PBI-6309-2RS',
    'https://verify.pivotbearings.com/pbi/PB-8812-KR?batch=BATCH-2026-OCT-A&m=PBI-6309-2RS&w=12',
    'SHA-256: 9C82A109D45E8812',
    '33333333-3333-3333-3333-333333333333',
    'CURRENTLY_OUT'
  ),
  (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbb0003',
    'PB-7701-AB',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'PBI-7210-BECBM',
    'https://verify.pivotbearings.com/pbi/PB-7701-AB?batch=BATCH-2026-OCT-A&m=PBI-7210-BECBM&w=3',
    'SHA-256: 3D11F982C89A7701',
    '11111111-1111-1111-1111-111111111111',
    'CURRENTLY_IN'
  )
on conflict (bearing_id) do nothing;
