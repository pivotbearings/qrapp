-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261012000021_authorised_person_whatsapp.sql
-- Authorised Person Mobile Numbers Configuration for WhatsApp Lifecycle Sharing
-- ==============================================================================

-- 1. Add authorised_numbers column to public.profiles (up to 10 numbers per user)
alter table public.profiles 
add column if not exists authorised_numbers text[] not null default '{}';

-- 2. Populate default authorised number for admin accounts if empty
update public.profiles
set authorised_numbers = array['+919898857198']
where (email = 'abc@gmail.com' or email like '%admin%')
  and (authorised_numbers is null or cardinality(authorised_numbers) = 0);

-- 3. Stored Procedure: admin_update_user_authorised_numbers
-- Allows administrators to configure up to 10 authorised numbers for any user
create or replace function public.admin_update_user_authorised_numbers(
  p_target_user_id uuid,
  p_numbers text[]
)
returns jsonb as $$
declare
  v_admin_id uuid := auth.uid();
  v_clean_numbers text[] := '{}';
  v_num text;
begin
  -- Enforce Administrator role
  if not public.is_admin(v_admin_id) then
    raise exception 'Unauthorized: Only administrators can update authorised person numbers.'
      using errcode = '42501';
  end if;

  -- Validate maximum limit of 10 numbers
  if coalesce(array_length(p_numbers, 1), 0) > 10 then
    raise exception 'Limit Exceeded: A maximum of 10 authorised numbers can be configured per user.'
      using errcode = '22000';
  end if;

  -- Clean and sanitize numbers (preserve international format digits and '+')
  if p_numbers is not null then
    foreach v_num in array p_numbers loop
      v_num := regexp_replace(trim(v_num), '[^0-9+]', '', 'g');
      if length(v_num) >= 7 and not (v_num = any(v_clean_numbers)) then
        v_clean_numbers := array_append(v_clean_numbers, v_num);
      end if;
    end loop;
  end if;

  -- Update profiles record
  update public.profiles
  set authorised_numbers = v_clean_numbers,
      updated_at = now()
  where id = p_target_user_id;

  return jsonb_build_object(
    'success', true,
    'user_id', p_target_user_id,
    'authorised_numbers', v_clean_numbers
  );
end;
$$ language plpgsql security definer;

-- 4. Execution Grants
grant execute on function public.admin_update_user_authorised_numbers(uuid, text[]) to authenticated;
