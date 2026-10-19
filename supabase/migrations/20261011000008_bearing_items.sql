-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261011000008_bearing_items.sql
-- Bearing Item Master Catalog schema, RLS policies, and standard seed catalog
-- ==============================================================================

-- 1. Create BEARING_ITEMS Table
create table if not exists public.bearing_items (
  item_code text primary key,
  item_name text not null,
  category text not null default 'Ball Bearing',
  default_warranty_months integer not null default 6 check (default_warranty_months > 0),
  description text default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2. Trigger for Automatic updated_at Maintenance
drop trigger if exists tr_bearing_items_updated_at on public.bearing_items;
create trigger tr_bearing_items_updated_at
  before update on public.bearing_items
  for each row execute function public.handle_updated_at();

-- 3. Enable Row Level Security (RLS)
alter table public.bearing_items enable row level security;

-- 4. RLS Policies
-- All authenticated users and public verification can query the item master
drop policy if exists "Anyone can read bearing items" on public.bearing_items;
create policy "Anyone can read bearing items"
  on public.bearing_items for select
  using (true);

-- Only ADMIN operators can insert, update, or remove items
drop policy if exists "Admins can insert bearing items" on public.bearing_items;
create policy "Admins can insert bearing items"
  on public.bearing_items for insert
  with check (public.is_admin());

drop policy if exists "Admins can update bearing items" on public.bearing_items;
create policy "Admins can update bearing items"
  on public.bearing_items for update
  using (public.is_admin());

drop policy if exists "Admins can delete bearing items" on public.bearing_items;
create policy "Admins can delete bearing items"
  on public.bearing_items for delete
  using (public.is_admin());

-- 5. Seed Initial Standard Industrial Bearing Models
insert into public.bearing_items (item_code, item_name, category, default_warranty_months, description)
values
  (
    'PBI-6204-ZZ',
    'Deep Groove Ball Bearing 6204 (Dual Metal Shielded)',
    'Ball Bearing',
    6,
    '20mm bore x 47mm OD x 14mm width. High speed, standard industrial electric motors.'
  ),
  (
    'PBI-6205-2RS',
    'Deep Groove Ball Bearing 6205 (Dual Rubber Sealed)',
    'Ball Bearing',
    6,
    '25mm bore x 52mm OD x 15mm width. Contaminant-resistant, conveyor and pump duty.'
  ),
  (
    'PBI-6309-2RS',
    'Heavy Duty Deep Groove Ball Bearing 6309',
    'Ball Bearing',
    12,
    '45mm bore x 100mm OD x 25mm width. High dynamic load capacity for heavy industrial gearboxes.'
  ),
  (
    'PBI-22216-E',
    'Spherical Roller Bearing 22216 (Self-Aligning)',
    'Roller Bearing',
    18,
    '80mm bore x 140mm OD x 33mm width. Heavy industrial vibration, mining, and shaft deflection duty.'
  ),
  (
    'PBI-30206-CR',
    'Single Row Tapered Roller Bearing 30206',
    'Tapered Roller',
    12,
    '30mm bore x 62mm OD x 17.25mm width. Combined heavy radial and axial thrust loads.'
  ),
  (
    'PBI-NU208-ECP',
    'Cylindrical Roller Bearing NU208',
    'Cylindrical Roller',
    12,
    '40mm bore x 80mm OD x 18mm width. High radial load capacity, reinforced polyamide cage.'
  ),
  (
    'PBI-7208-BECBP',
    'Angular Contact Ball Bearing 7208 (40° Angle)',
    'Angular Contact',
    12,
    '40mm bore x 80mm OD x 18mm width. High precision spindle drives and centrifugal pumps.'
  ),
  (
    'PBI-51105',
    'Single Direction Thrust Ball Bearing 51105',
    'Thrust Bearing',
    6,
    '25mm bore x 42mm OD x 11mm width. Pure axial load support for vertical jacks and crane hooks.'
  )
on conflict (item_code) do update set
  item_name = excluded.item_name,
  category = excluded.category,
  default_warranty_months = excluded.default_warranty_months,
  description = excluded.description;
