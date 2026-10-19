-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261010000007_admin_dashboard_metrics_rpc.sql
-- Enterprise Admin Telemetry, Metrics Aggregator & Complete Lifecycle Query RPCs
-- ==============================================================================

-- 1. Function: get_admin_dashboard_metrics
-- Aggregates real database counts across all production tables atomically
create or replace function public.get_admin_dashboard_metrics()
returns jsonb as $$
declare
  v_admin_id uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_total_qr bigint := 0;
  v_unactivated_qr bigint := 0;
  v_currently_in bigint := 0;
  v_currently_out bigint := 0;
  v_active_warranties bigint := 0;
  v_expired_warranties bigint := 0;
  v_total_scans bigint := 0;
  v_invalid_attempts bigint := 0;
  v_total_customers bigint := 0;
  v_total_batches bigint := 0;
  v_total_flagged bigint := 0;
begin
  -- 1. Security Check: Admin Access Control
  if not public.is_admin(v_admin_id) then
    raise exception 'Insufficient privilege: ADMIN role required to access dashboard metrics.'
      using errcode = '42501';
  end if;

  -- 2. Aggregate QR Code Counts
  select
    count(*),
    count(*) filter (where current_lifecycle_state = 'NOT_ACTIVATED'),
    count(*) filter (where current_lifecycle_state = 'CURRENTLY_IN'),
    count(*) filter (where current_lifecycle_state = 'CURRENTLY_OUT'),
    count(*) filter (where first_in_timestamp is not null and warranty_expiry_timestamp > v_now),
    count(*) filter (where first_in_timestamp is not null and warranty_expiry_timestamp <= v_now),
    count(*) filter (where is_flagged = true)
  into
    v_total_qr,
    v_unactivated_qr,
    v_currently_in,
    v_currently_out,
    v_active_warranties,
    v_expired_warranties,
    v_total_flagged
  from public.qr_codes;

  -- 3. Aggregate Scan Records & Invalid Attempts
  select
    count(*),
    count(*) filter (where is_valid = false)
  into
    v_total_scans,
    v_invalid_attempts
  from public.scan_records;

  -- 4. Aggregate Customers & Batches
  select count(*) into v_total_customers from public.profiles;
  select count(*) into v_total_batches from public.qr_batches;

  return jsonb_build_object(
    'total_qr_codes', v_total_qr,
    'unactivated_qr_codes', v_unactivated_qr,
    'currently_in_bearings', v_currently_in,
    'currently_out_bearings', v_currently_out,
    'active_warranties', v_active_warranties,
    'expired_warranties', v_expired_warranties,
    'total_scans', v_total_scans,
    'invalid_attempts', v_invalid_attempts,
    'total_customers', v_total_customers,
    'total_batches', v_total_batches,
    'flagged_bearings', v_total_flagged,
    'queried_at', v_now
  );
end;
$$ language plpgsql security definer set search_path = public;

-- Grant execution
grant execute on function public.get_admin_dashboard_metrics() to authenticated;


-- 2. Function: get_bearing_full_lifecycle_details
-- Fetches comprehensive history including original activation anchor, current state,
-- every installation cycle with usage duration and removal warranty state
create or replace function public.get_bearing_full_lifecycle_details(
  p_bearing_id text
)
returns jsonb as $$
declare
  v_admin_id uuid := auth.uid();
  v_qr record;
  v_clean_id text := upper(trim(coalesce(p_bearing_id, '')));
  v_cycles jsonb := '[]'::jsonb;
  v_events jsonb := '[]'::jsonb;
  v_plan record;
  v_batch record;
  v_customer record;
begin
  -- 1. Security Check: Admin Access Control
  if not public.is_admin(v_admin_id) then
    raise exception 'Insufficient privilege: ADMIN role required.'
      using errcode = '42501';
  end if;

  -- 2. Fetch QR Record
  select * into v_qr
  from public.qr_codes
  where bearing_id = v_clean_id;

  if not found then
    raise exception 'Bearing ID % not found in registry.', v_clean_id
      using errcode = 'P0002';
  end if;

  -- 3. Fetch Plan, Batch, and Customer
  select * into v_plan from public.warranty_plans where id = v_qr.assigned_warranty_plan_id;
  select * into v_batch from public.qr_batches where id = v_qr.batch_id;
  select * into v_customer from public.profiles where id = v_qr.assigned_customer_id;

  -- 4. Aggregate Every Installation Cycle
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'cycle_number', c.cycle_number,
        'in_timestamp', c.in_timestamp,
        'out_timestamp', c.out_timestamp,
        'operating_duration_interval', c.operating_duration_interval::text,
        'operating_duration_seconds', c.operating_duration_seconds,
        'was_warranty_active_at_out', c.was_warranty_active_at_out,
        'in_verification_image', (
          select jsonb_build_object(
            'id', img.id,
            'storage_path', img.storage_path,
            'sha256_hash', img.sha256_hash,
            'file_size_bytes', img.file_size_bytes
          )
          from public.verification_images img
          where img.id = c.in_verification_image_id
        ),
        'out_verification_image', (
          select jsonb_build_object(
            'id', img.id,
            'storage_path', img.storage_path,
            'sha256_hash', img.sha256_hash,
            'file_size_bytes', img.file_size_bytes
          )
          from public.verification_images img
          where img.id = c.out_verification_image_id
        )
      ) order by c.cycle_number asc
    ), '[]'::jsonb
  ) into v_cycles
  from public.bearing_installation_cycles c
  where c.qr_code_id = v_qr.id;

  -- 5. Aggregate Lifecycle Audit Events
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', e.id,
        'event_type', e.event_type,
        'server_timestamp', e.server_timestamp,
        'notes', e.notes,
        'operator_id', e.performed_by,
        'verification_image_id', e.verification_image_id
      ) order by e.server_timestamp desc
    ), '[]'::jsonb
  ) into v_events
  from public.bearing_lifecycle_events e
  where e.qr_code_id = v_qr.id;

  return jsonb_build_object(
    'id', v_qr.id,
    'bearing_id', v_qr.bearing_id,
    'model_number', v_qr.model_number,
    'batch_code', coalesce(v_batch.batch_code, 'N/A'),
    'plant_location', coalesce(v_batch.plant_location, 'N/A'),
    'current_lifecycle_state', v_qr.current_lifecycle_state,
    'is_flagged', v_qr.is_flagged,
    'flag_reason', v_qr.flag_reason,
    'warranty_plan', jsonb_build_object(
      'title', coalesce(v_plan.title, 'Standard'),
      'duration_months', coalesce(v_plan.duration_months, 6)
    ),
    'assigned_customer', jsonb_build_object(
      'full_name', coalesce(v_customer.full_name, 'Unassigned Customer'),
      'company_name', v_customer.company_name,
      'facility_code', v_customer.facility_code
    ),
    'first_in_timestamp', v_qr.first_in_timestamp,
    'warranty_expiry_timestamp', v_qr.warranty_expiry_timestamp,
    'is_warranty_active', (v_qr.first_in_timestamp is not null and v_qr.warranty_expiry_timestamp > clock_timestamp()),
    'installation_cycles', v_cycles,
    'lifecycle_events', v_events
  );
end;
$$ language plpgsql security definer set search_path = public;

-- Grant execution
grant execute on function public.get_bearing_full_lifecycle_details(text) to authenticated;
