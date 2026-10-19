-- ==============================================================================
-- Pivot Bearings India - Migration: 20261011000013_multi_tenant_isolation.sql
-- Enforces Strict Multi-Tenant Data Isolation and Tenant-Level Analytics
-- ==============================================================================

-- 1. Ensure foreign key column and tenant indexing on qr_codes
alter table if exists public.qr_codes
  add column if not exists assigned_customer_id uuid references public.profiles(id) on delete set null;

create index if not exists idx_qr_codes_assigned_customer_lifecycle
  on public.qr_codes (assigned_customer_id, current_lifecycle_state);

-- 2. Enhanced Multi-Tenant Row Level Security on QR Codes
alter table public.qr_codes enable row level security;

drop policy if exists "QrCodes: Read access for verification and ownership" on public.qr_codes;
drop policy if exists "QrCodes: Multi-tenant isolated read" on public.qr_codes;
drop policy if exists "Tenant: View assigned bearings" on public.qr_codes;

create policy "QrCodes: Multi-tenant isolated read"
  on public.qr_codes for select
  using (
    -- System Administrators have overarching fleet visibility
    public.is_admin(auth.uid())
    -- Authenticated tenant operators see their assigned inventory
    or assigned_customer_id = auth.uid()
    -- Unassigned or public serials can be verified
    or assigned_customer_id is null
  );

-- 3. Multi-Tenant Stored Function: Get Tenant Isolated Dashboard Metrics
create or replace function public.get_tenant_isolated_metrics(p_customer_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_target_id uuid;
  v_total int := 0;
  v_in_count int := 0;
  v_out_count int := 0;
  v_not_activated int := 0;
  v_active_warranty int := 0;
begin
  -- If not provided, resolve from active auth caller
  v_target_id := coalesce(p_customer_id, auth.uid());

  if v_target_id is null and not public.is_admin(auth.uid()) then
    return jsonb_build_object(
      'total', 0,
      'currently_in', 0,
      'currently_out', 0,
      'not_activated', 0,
      'active_warranty', 0
    );
  end if;

  if public.is_admin(auth.uid()) and p_customer_id is null then
    -- Admin global rollup
    select
      count(*),
      count(*) filter (where current_lifecycle_state = 'CURRENTLY_IN'),
      count(*) filter (where current_lifecycle_state = 'CURRENTLY_OUT'),
      count(*) filter (where current_lifecycle_state = 'NOT_ACTIVATED'),
      count(*) filter (where warranty_expiry_timestamp > now() and current_lifecycle_state != 'NOT_ACTIVATED')
    into v_total, v_in_count, v_out_count, v_not_activated, v_active_warranty
    from public.qr_codes;
  else
    -- Strict tenant isolated rollup
    select
      count(*),
      count(*) filter (where current_lifecycle_state = 'CURRENTLY_IN'),
      count(*) filter (where current_lifecycle_state = 'CURRENTLY_OUT'),
      count(*) filter (where current_lifecycle_state = 'NOT_ACTIVATED'),
      count(*) filter (where warranty_expiry_timestamp > now() and current_lifecycle_state != 'NOT_ACTIVATED')
    into v_total, v_in_count, v_out_count, v_not_activated, v_active_warranty
    from public.qr_codes
    where assigned_customer_id = v_target_id;
  end if;

  return jsonb_build_object(
    'total', coalesce(v_total, 0),
    'currently_in', coalesce(v_in_count, 0),
    'currently_out', coalesce(v_out_count, 0),
    'not_activated', coalesce(v_not_activated, 0),
    'active_warranty', coalesce(v_active_warranty, 0)
  );
end;
$$;

-- 4. Stored Procedure: Assign Bearing To Tenant Account
create or replace function public.assign_bearing_to_tenant(
  p_bearing_id text,
  p_customer_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Unauthorized: Only system administrators can allocate bearings to tenants.';
  end if;

  update public.qr_codes
  set assigned_customer_id = p_customer_id,
      updated_at = now()
  where upper(bearing_id) = upper(p_bearing_id);

  return found;
end;
$$;

-- 5. Lifecycle Events Tenant Isolation (only if bearing_lifecycle_events exists)
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'bearing_lifecycle_events') then
    alter table public.bearing_lifecycle_events enable row level security;
    drop policy if exists "Lifecycle: Tenant isolated read" on public.bearing_lifecycle_events;
    create policy "Lifecycle: Tenant isolated read"
      on public.bearing_lifecycle_events for select
      using (
        public.is_admin(auth.uid())
        or exists (
          select 1 from public.qr_codes
          where public.qr_codes.id = public.bearing_lifecycle_events.qr_code_id
            and (public.qr_codes.assigned_customer_id = auth.uid() or public.qr_codes.assigned_customer_id is null)
        )
      );
  end if;
end $$;

-- 6. Grant permissions
grant execute on function public.get_tenant_isolated_metrics(uuid) to authenticated, anon;
grant execute on function public.assign_bearing_to_tenant(text, uuid) to authenticated;

-- 7. Seed Allocation of Bearings to Known Tenant (user@gmail.com) if present
do $$
declare
  v_user_id uuid;
begin
  select id into v_user_id from auth.users where lower(email) = 'user@gmail.com';
  if v_user_id is not null then
    -- Allocate up to 5 unassigned bearings to user@gmail.com for immediate tenant isolation demo
    update public.qr_codes
    set assigned_customer_id = v_user_id
    where id in (
      select id from public.qr_codes
      where assigned_customer_id is null
      limit 5
    );
  end if;
end $$;
