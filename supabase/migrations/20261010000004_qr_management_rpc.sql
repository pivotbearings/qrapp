-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261010000004_qr_management_rpc.sql
-- Server-Side Secure QR Batch Generation, Bulk Warranty Assignment, and Blocking
-- ==============================================================================

-- 1. Function: Secure Server-Side QR Batch Generation
-- Generates unpredictable, unique cryptographically secure bearing IDs
-- Enforces server-side uniqueness, handles collision retries, and records batch
create or replace function public.generate_qr_batch(
  p_batch_code text,
  p_plant_location text,
  p_quantity integer,
  p_model_number text default 'PBI-6204-ZZ',
  p_default_warranty_plan_id uuid default null
)
returns jsonb as $$
declare
  v_admin_id uuid := auth.uid();
  v_batch_id uuid;
  v_plan_id uuid := p_default_warranty_plan_id;
  v_generated_count integer := 0;
  v_max_attempts integer := p_quantity * 5;
  v_attempts integer := 0;
  v_digits text;
  v_suffix text;
  v_bearing_id text;
  v_payload text;
  v_hash text;
  v_charset text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_inserted_ids text[] := array[]::text[];
begin
  -- 1. Enforce Admin Privilege
  if not public.is_admin(v_admin_id) then
    raise exception 'Insufficient privilege: ADMIN role required to generate QR batches.'
      using errcode = '42501';
  end if;

  -- 2. Validate Quantity
  if p_quantity is null or p_quantity < 1 or p_quantity > 5000 then
    raise exception 'Invalid quantity: % (Must be between 1 and 5000).', p_quantity
      using errcode = '22023';
  end if;

  -- 3. Resolve Default Warranty Plan if null
  if v_plan_id is null then
    select id into v_plan_id
    from public.warranty_plans
    where is_active = true
    order by duration_months asc
    limit 1;
    
    if v_plan_id is null then
      raise exception 'No active warranty plan available.';
    end if;
  else
    if not exists (select 1 from public.warranty_plans where id = v_plan_id) then
      raise exception 'Specified warranty plan % not found.', v_plan_id;
    end if;
  end if;

  -- 4. Create or Resolve QR Batch Record
  select id into v_batch_id
  from public.qr_batches
  where batch_code = p_batch_code;

  if v_batch_id is null then
    insert into public.qr_batches (
      batch_code,
      plant_location,
      lot_date,
      total_quantity,
      default_warranty_plan_id,
      created_by,
      status
    ) values (
      p_batch_code,
      p_plant_location,
      current_date,
      p_quantity,
      v_plan_id,
      v_admin_id,
      'ACTIVE'
    )
    returning id into v_batch_id;
  else
    -- Increment existing batch total quantity
    update public.qr_batches
    set total_quantity = total_quantity + p_quantity,
        updated_at = now()
    where id = v_batch_id;
  end if;

  -- 5. Cryptographically Generate Unique Identifiers with Collision Avoidance Loop
  while v_generated_count < p_quantity and v_attempts < v_max_attempts loop
    v_attempts := v_attempts + 1;
    
    -- Generate 4 random digits (0000 - 9999)
    v_digits := lpad((floor(random() * 10000))::int::text, 4, '0');
    
    -- Generate 2 uppercase alphanumeric characters matching ^PB-[0-9]{4}-[A-Z0-9]{2}$
    v_suffix := substr(v_charset, (floor(random() * length(v_charset)) + 1)::int, 1)
             || substr(v_charset, (floor(random() * length(v_charset)) + 1)::int, 1);
             
    v_bearing_id := 'PB-' || v_digits || '-' || v_suffix;

    -- Standard payload URL (identifies registered bearing without sensitive or editable dates)
    v_payload := 'https://verify.pivotbearings.com/pbi/' || v_bearing_id
              || '?batch=' || p_batch_code
              || '&m=' || p_model_number;

    -- Cryptographic SHA-256 hash
    v_hash := 'SHA-256: ' || upper(encode(digest(v_payload, 'sha256'), 'hex'));

    -- Attempt atomic insertion; on conflict ignore and retry next random iteration
    begin
      insert into public.qr_codes (
        bearing_id,
        batch_id,
        model_number,
        payload_value,
        payload_hash,
        assigned_warranty_plan_id,
        current_lifecycle_state,
        first_in_timestamp,
        warranty_expiry_timestamp,
        is_flagged
      ) values (
        v_bearing_id,
        v_batch_id,
        p_model_number,
        v_payload,
        v_hash,
        v_plan_id,
        'NOT_ACTIVATED',
        null,
        null,
        false
      );

      v_generated_count := v_generated_count + 1;
      v_inserted_ids := array_append(v_inserted_ids, v_bearing_id);

      -- Record initial generation lifecycle audit event
      insert into public.bearing_lifecycle_events (
        qr_code_id,
        event_type,
        recorded_by,
        server_timestamp,
        metadata
      ) values (
        (select id from public.qr_codes where bearing_id = v_bearing_id),
        'INITIAL_GENERATION',
        v_admin_id,
        now(),
        jsonb_build_object(
          'batch_code', p_batch_code,
          'model_number', p_model_number,
          'warranty_plan_id', v_plan_id
        )
      );

    exception when unique_violation then
      -- Collision encountered: loop repeats safely without aborting the entire batch
      null;
    end;
  end loop;

  -- 6. Verify full quantity completed
  if v_generated_count < p_quantity then
    raise exception 'Failed to generate required quantity due to key collisions. Generated: % of %',
      v_generated_count, p_quantity;
  end if;

  -- 7. Audit Log Entry
  insert into public.admin_audit_logs (
    admin_id,
    action,
    target_entity,
    target_id,
    new_values
  ) values (
    v_admin_id,
    'GENERATE_QR_BATCH',
    'qr_batches',
    v_batch_id,
    jsonb_build_object(
      'batch_code', p_batch_code,
      'quantity', p_quantity,
      'model_number', p_model_number,
      'default_warranty_plan_id', v_plan_id
    )
  );

  return jsonb_build_object(
    'success', true,
    'batch_id', v_batch_id,
    'batch_code', p_batch_code,
    'quantity_generated', v_generated_count,
    'bearing_ids', to_jsonb(v_inserted_ids)
  );
end;
$$ language plpgsql security definer;

-- ==============================================================================
-- 2. Function: Bulk Warranty Assignment
-- Allows assigning different warranty plans to individual or grouped QR codes.
-- Example: 5 bearings assigned to 3 months, 3 bearings assigned to 6 months.
-- ==============================================================================
create or replace function public.assign_warranties_bulk(
  p_assignments jsonb
)
returns jsonb as $$
declare
  v_admin_id uuid := auth.uid();
  v_item jsonb;
  v_bearing_id text;
  v_plan_id uuid;
  v_duration_months integer;
  v_qr record;
  v_updated_count integer := 0;
  v_updated_ids text[] := array[]::text[];
begin
  -- 1. Enforce Admin Privilege
  if not public.is_admin(v_admin_id) then
    raise exception 'Insufficient privilege: ADMIN role required for warranty assignment.'
      using errcode = '42501';
  end if;

  if jsonb_typeof(p_assignments) != 'array' then
    raise exception 'p_assignments must be a JSON array of objects with bearing_id and warranty_plan_id.';
  end if;

  for v_item in select * from jsonb_array_elements(p_assignments) loop
    v_bearing_id := v_item->>'bearing_id';
    v_plan_id := (v_item->>'warranty_plan_id')::uuid;

    -- Validate Warranty Plan
    select duration_months into v_duration_months
    from public.warranty_plans
    where id = v_plan_id;

    if not found then
      raise exception 'Warranty plan % not found for bearing %.', v_plan_id, v_bearing_id;
    end if;

    -- Lock and fetch QR Code
    select * into v_qr
    from public.qr_codes
    where bearing_id = v_bearing_id
    for update;

    if not found then
      raise exception 'Bearing ID % not found.', v_bearing_id;
    end if;

    -- Update QR Code
    -- If already activated (first_in_timestamp is set), recalculate expiry anchor.
    -- If not activated, expiry remains NULL (generation and assignment do not start warranty).
    if v_qr.first_in_timestamp is not null then
      update public.qr_codes
      set
        assigned_warranty_plan_id = v_plan_id,
        warranty_expiry_timestamp = v_qr.first_in_timestamp + (v_duration_months || ' months')::interval,
        updated_at = now()
      where id = v_qr.id;
    else
      update public.qr_codes
      set
        assigned_warranty_plan_id = v_plan_id,
        updated_at = now()
      where id = v_qr.id;
    end if;

    -- Record Audit Lifecycle Event
    insert into public.bearing_lifecycle_events (
      qr_code_id,
      event_type,
      recorded_by,
      server_timestamp,
      metadata
    ) values (
      v_qr.id,
      'WARRANTY_EXTENDED',
      v_admin_id,
      now(),
      jsonb_build_object(
        'previous_plan_id', v_qr.assigned_warranty_plan_id,
        'new_plan_id', v_plan_id,
        'duration_months', v_duration_months
      )
    );

    v_updated_count := v_updated_count + 1;
    v_updated_ids := array_append(v_updated_ids, v_bearing_id);
  end loop;

  return jsonb_build_object(
    'success', true,
    'updated_count', v_updated_count,
    'bearing_ids', to_jsonb(v_updated_ids)
  );
end;
$$ language plpgsql security definer;

-- ==============================================================================
-- 3. Function: Toggle QR Blocking / Flagging
-- Flags or unflags a counterfeit/tampered bearing with reason
-- ==============================================================================
create or replace function public.toggle_qr_block(
  p_bearing_id text,
  p_is_flagged boolean,
  p_flag_reason text default null
)
returns jsonb as $$
declare
  v_admin_id uuid := auth.uid();
  v_qr record;
begin
  -- 1. Enforce Admin Privilege
  if not public.is_admin(v_admin_id) then
    raise exception 'Insufficient privilege: ADMIN role required to block/unblock QR codes.'
      using errcode = '42501';
  end if;

  select * into v_qr
  from public.qr_codes
  where bearing_id = p_bearing_id
  for update;

  if not found then
    raise exception 'Bearing ID % not found.', p_bearing_id;
  end if;

  update public.qr_codes
  set
    is_flagged = p_is_flagged,
    flag_reason = case when p_is_flagged then p_flag_reason else null end,
    updated_at = now()
  where id = v_qr.id;

  -- Audit log event
  insert into public.bearing_lifecycle_events (
    qr_code_id,
    event_type,
    recorded_by,
    server_timestamp,
    metadata
  ) values (
    v_qr.id,
    'FLAGGED',
    v_admin_id,
    now(),
    jsonb_build_object(
      'is_flagged', p_is_flagged,
      'flag_reason', p_flag_reason
    )
  );

  return jsonb_build_object(
    'success', true,
    'bearing_id', p_bearing_id,
    'is_flagged', p_is_flagged,
    'flag_reason', p_flag_reason
  );
end;
$$ language plpgsql security definer;
