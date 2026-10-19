-- ==============================================================================
-- 14. BEARING_CATEGORIES Table & RLS Policies
-- Dynamic Category Master management for Pivot Bearings Item Master
-- ==============================================================================

create table if not exists public.bearing_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  created_at timestamptz not null default now()
);

-- Index on category name for high speed lookups
create index if not exists idx_bearing_categories_name on public.bearing_categories(name);

-- Standard Seed Categories for Pivot Bearings Catalog
insert into public.bearing_categories (name, description)
values
  ('Ball Bearing', 'Standard and deep groove radial ball bearings'),
  ('Roller Bearing', 'High radial load spherical and cylindrical roller bearings'),
  ('Tapered Roller', 'Combined radial and axial thrust tapered roller bearings'),
  ('Cylindrical Roller', 'Heavy industrial high speed cylindrical roller bearings'),
  ('Angular Contact', 'High precision angular contact machine tool bearings'),
  ('Thrust Bearing', 'Pure axial thrust load vertical shaft bearings'),
  ('Spherical Roller', 'Self-aligning heavy vibration and shock load bearings'),
  ('Needle Roller', 'Compact high capacity needle roller bearings')
on conflict (name) do nothing;

-- Enable Row Level Security (RLS)
alter table public.bearing_categories enable row level security;

-- All authenticated and anonymous users can read categories
create policy "Allow read access to bearing categories"
  on public.bearing_categories for select
  using (true);

-- Admins can insert, update, and delete categories
create policy "Allow admin write access to bearing categories"
  on public.bearing_categories for insert
  with check (public.is_admin());

create policy "Allow admin update access to bearing categories"
  on public.bearing_categories for update
  using (public.is_admin());

create policy "Allow admin delete access to bearing categories"
  on public.bearing_categories for delete
  using (public.is_admin());
