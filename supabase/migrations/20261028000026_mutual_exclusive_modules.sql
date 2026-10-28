-- Pivot Bearings India - Database Migration: 20261028000026_mutual_exclusive_modules.sql
-- Strictly enforces mutual exclusivity between Warranty Module and Track Your Bearing Module.

-- 1. Resolve any existing accounts that currently have both modules enabled (Warranty takes precedence)
update public.profiles
set has_track_bearing_access = false
where has_warranty_access = true and has_track_bearing_access = true;

-- 2. Add table check constraint to prevent both being enabled simultaneously
alter table public.profiles
  drop constraint if exists check_mutual_exclusive_modules;

alter table public.profiles
  add constraint check_mutual_exclusive_modules
  check (not (has_warranty_access = true and has_track_bearing_access = true));

-- 3. Update admin_update_user_module_permissions stored procedure to enforce mutual exclusivity
create or replace function public.admin_update_user_module_permissions(
  p_target_user_id uuid,
  p_has_warranty boolean,
  p_has_track_bearing boolean
)
returns jsonb as $$
declare
  v_admin_id uuid := auth.uid();
  v_safe_warranty boolean := coalesce(p_has_warranty, false);
  v_safe_track boolean := coalesce(p_has_track_bearing, false);
begin
  -- Enforce Administrator role
  if not public.is_admin(v_admin_id) then
    raise exception 'Unauthorized: Only administrators can update user module permissions.'
      using errcode = '42501';
  end if;

  -- Mutual exclusivity: only one module may be active at any given time
  if v_safe_warranty and v_safe_track then
    v_safe_track := false;
  end if;

  update public.profiles
  set has_warranty_access = v_safe_warranty,
      has_track_bearing_access = v_safe_track,
      updated_at = now()
  where id = p_target_user_id;

  return jsonb_build_object(
    'success', true,
    'user_id', p_target_user_id,
    'has_warranty_access', v_safe_warranty,
    'has_track_bearing_access', v_safe_track
  );
end;
$$ language plpgsql security definer;

