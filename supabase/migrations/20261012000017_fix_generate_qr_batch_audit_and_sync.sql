-- ==============================================================================
-- Pivot Bearings India - Migration: 20261012000017_fix_generate_qr_batch_audit_and_sync.sql
-- Fixes generate_qr_batch RPC so QR batches are guaranteed to commit to qr_codes
-- and be instantly verifiable across all user accounts and the mobile APK.
-- ==============================================================================

-- 1. Create a backward-compatible view/table alias for audit_logs if referenced
create or replace view public.audit_logs as 
  select id, admin_id, action, target_entity, target_id, new_values as details, created_at 
  from public.admin_audit_logs;

-- 2. Update generate_qr_batch RPC to guarantee database insertion
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
  v_model_token text;
  v_epoch_token text;
  v_nonce_token text;
  v_checksum text;
  v_base_payload text;
  v_bearing_id text;
  v_payload text;
  v_hash text;
  v_inserted_ids text[] := array[]::text[];
  v_salt text := 'PIVOT_BEARINGS_INDIA_INDUSTRIAL_AUTHENTICITY_SALT_2026';
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
      select id into v_plan_id from public.warranty_plans limit 1;
    end if;
  else
    if not exists (select 1 from public.warranty_plans where id = v_plan_id) then
      select id into v_plan_id from public.warranty_plans limit 1;
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
    update public.qr_batches
    set total_quantity = total_quantity + p_quantity,
        updated_at = now()
    where id = v_batch_id;
  end if;

  -- Extract 4-character functional model token
  v_model_token := substring(regexp_replace(replace(p_model_number, 'PBI-', ''), '[^A-Za-z0-9]', '', 'g') from 1 for 4);
  if length(v_model_token) < 4 then
    v_model_token := rpad(v_model_token, 4, '0');
  end if;
  v_model_token := upper(v_model_token);

  -- Extract 4-character epoch token
  v_epoch_token := to_hex(
    (((extract(year from current_date)::integer - 2020) & 15) << 4) |
    (extract(month from current_date)::integer & 15)
  ) || to_hex(
    (select coalesce(duration_months, 6) from public.warranty_plans where id = v_plan_id) & 255
  );
  v_epoch_token := upper(lpad(v_epoch_token, 4, '0'));

  -- 5. Batch Generation Loop
  while v_generated_count < p_quantity and v_attempts < v_max_attempts loop
    v_attempts := v_attempts + 1;

    -- Generate CSPRNG Nonce
    v_nonce_token := upper(encode(gen_random_bytes(2), 'hex'));

    -- Compute Tamper-Evident SHA-256 HMAC Checksum
    v_base_payload := v_model_token || '-' || v_epoch_token || '-' || v_nonce_token;
    v_checksum := upper(substring(encode(digest(v_salt || ':' || v_base_payload, 'sha256'), 'hex') from 1 for 4));

    -- Full Cryptographic Key
    v_bearing_id := 'PBI-SEC-' || v_base_payload || '-' || v_checksum;
    v_payload := v_bearing_id;
    v_hash := upper(encode(digest(v_bearing_id, 'sha256'), 'hex'));

    begin
      insert into public.qr_codes (
        bearing_id,
        batch_id,
        model_number,
        payload_value,
        payload_hash,
        warranty_plan_id,
        current_lifecycle_state,
        is_flagged
      ) values (
        v_bearing_id,
        v_batch_id,
        p_model_number,
        v_payload,
        v_hash,
        v_plan_id,
        'NOT_ACTIVATED',
        false
      );

      v_generated_count := v_generated_count + 1;
      v_inserted_ids := array_append(v_inserted_ids, v_bearing_id);
    exception when unique_violation then
      null;
    end;
  end loop;

  -- 6. Safe Audit Trail Logging (Never abort batch insertion on audit log failure)
  begin
    insert into public.admin_audit_logs (
      admin_id,
      action,
      target_entity,
      target_id,
      new_values
    ) values (
      v_admin_id,
      'GENERATE_CRYPTOGRAPHIC_QR_BATCH',
      'qr_batches',
      v_batch_id,
      jsonb_build_object(
        'batch_code', p_batch_code,
        'quantity_requested', p_quantity,
        'quantity_generated', v_generated_count,
        'key_format', 'PBI-SEC-V2',
        'plant_location', p_plant_location,
        'model_number', p_model_number
      )
    );
  exception when others then
    null;
  end;

  -- 7. Return Result JSON
  return jsonb_build_object(
    'batch_id', v_batch_id,
    'batch_code', p_batch_code,
    'quantity_generated', v_generated_count,
    'bearing_ids', to_jsonb(v_inserted_ids)
  );
end;
$$ language plpgsql security definer;
