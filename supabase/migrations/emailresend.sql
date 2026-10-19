-- ==============================================================================
-- Pivot Bearings India - Database Migration: 20261012000022_resend_lifecycle_email.sql
-- Resend Integration for Automated Bearing Out Lifecycle Email Delivery
-- ==============================================================================

-- 1. Enable pg_net extension if available (standard in Supabase for external HTTP calls)
create extension if not exists pg_net with schema extensions;

-- 2. Create secure server-side secrets store (RLS enabled - zero client exposure)
create table if not exists public.app_secrets (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  value text not null,
  description text,
  updated_at timestamptz not null default now()
);

-- Strict RLS: No direct select/update from client anon/authenticated roles
alter table public.app_secrets enable row level security;

-- Only service_role can read/write secrets directly
create policy "Secrets accessible only by service role"
  on public.app_secrets
  for all
  using (auth.role() = 'service_role');

-- Insert Resend defaults (replace with your live resend.dev key)
insert into public.app_secrets (key, value, description)
values
  ('RESEND_API_KEY', 're_replace_with_your_resend_api_key', 'Resend.com Secret API Key'),
  ('RESEND_FROM_EMAIL', 'Pivot Bearings India <onboarding@resend.dev>', 'Verified sender email address')
on conflict (key) do nothing;

-- 3. Create immutable audit table for email dispatches
create table if not exists public.email_dispatch_logs (
  id uuid primary key default gen_random_uuid(),
  bearing_id text not null,
  user_id uuid references public.profiles(id),
  recipient_email text not null,
  subject text not null,
  status text not null default 'QUEUED' check (status in ('QUEUED', 'SENT', 'FAILED')),
  http_response_code integer,
  error_message text,
  metadata jsonb default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.email_dispatch_logs enable row level security;

-- Users can view their own email dispatch history
create policy "Users can view own email dispatch logs"
  on public.email_dispatch_logs
  for select
  using (auth.uid() = user_id or auth.jwt() ->> 'email' = recipient_email);

-- 4. Authoritative RPC: send_bearing_lifecycle_email
-- Automatically called when a user marks Bearing Out and clicks "Email the Information"
create or replace function public.send_bearing_lifecycle_email(
  p_bearing_id text,
  p_html_content text,
  p_subject text default null
)
returns jsonb
language plpgsql
security definer -- Elevates permissions to read app_secrets securely
set search_path = public, extensions
as $$
declare
  v_user_id uuid := auth.uid();
  v_auth_email text := auth.jwt() ->> 'email';
  v_clean_bearing_id text := upper(trim(coalesce(p_bearing_id, '')));
  v_resend_api_key text;
  v_from_email text;
  v_subject text;
  v_recent_count integer;
  v_http_request_id bigint;
begin
  -- 1. Ensure user is authenticated
  if v_user_id is null and v_auth_email is null then
    return jsonb_build_object(
      'success', false,
      'error', 'Authentication required. Please sign in to email lifecycle records.'
    );
  end if;

  -- 2. Retrieve verified user email
  if v_auth_email is null or v_auth_email = '' then
    select email into v_auth_email from public.profiles where id = v_user_id;
  end if;

  if v_auth_email is null or v_auth_email = '' then
    return jsonb_build_object(
      'success', false,
      'error', 'No registered email address found for your account.'
    );
  end if;

  if v_clean_bearing_id = '' then
    return jsonb_build_object('success', false, 'error', 'Bearing ID is required.');
  end if;

  -- 3. Duplicate click guard: prevent multiple identical emails within 15 seconds
  select count(*) into v_recent_count
  from public.email_dispatch_logs
  where bearing_id = v_clean_bearing_id
    and recipient_email = v_auth_email
    and created_at > (now() - interval '15 seconds');

  if v_recent_count > 0 then
    return jsonb_build_object(
      'success', true,
      'message', 'Lifecycle information already sent. Please check your inbox at ' || v_auth_email || '.'
    );
  end if;

  -- 4. Retrieve Resend credentials securely
  select value into v_resend_api_key from public.app_secrets where key = 'RESEND_API_KEY';
  select value into v_from_email from public.app_secrets where key = 'RESEND_FROM_EMAIL';

  if v_resend_api_key is null or v_resend_api_key = '' or v_resend_api_key = 're_replace_with_your_resend_api_key' then
    -- Log configuration issue
    insert into public.email_dispatch_logs (
      bearing_id, user_id, recipient_email, subject, status, error_message
    ) values (
      v_clean_bearing_id, v_user_id, v_auth_email, coalesce(p_subject, 'Bearing Lifecycle Report'), 'FAILED',
      'Resend API key is not configured in app_secrets table.'
    );

    return jsonb_build_object(
      'success', false,
      'error', 'Resend API key is not configured. Please add your Resend API key in the Supabase app_secrets table.'
    );
  end if;

  v_from_email := coalesce(v_from_email, 'Pivot Bearings India <onboarding@resend.dev>');
  v_subject := coalesce(p_subject, 'Pivot Bearings India — Lifecycle Summary for Bearing ' || v_clean_bearing_id);

  -- 5. Dispatch email via Resend API using pg_net
  begin
    v_http_request_id := net.http_post(
      url := 'https://api.resend.com/emails',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || v_resend_api_key,
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object(
        'from', v_from_email,
        'to', jsonb_build_array(v_auth_email),
        'subject', v_subject,
        'html', p_html_content
      )
    );

    -- 6. Log successful queue
    insert into public.email_dispatch_logs (
      bearing_id, user_id, recipient_email, subject, status, metadata
    ) values (
      v_clean_bearing_id, v_user_id, v_auth_email, v_subject, 'SENT',
      jsonb_build_object('net_request_id', v_http_request_id)
    );

    return jsonb_build_object(
      'success', true,
      'message', 'Lifecycle summary sent to ' || v_auth_email,
      'recipient', v_auth_email
    );
  exception when others then
    -- Record error in audit log
    insert into public.email_dispatch_logs (
      bearing_id, user_id, recipient_email, subject, status, error_message
    ) values (
      v_clean_bearing_id, v_user_id, v_auth_email, v_subject, 'FAILED', SQLERRM
    );

    return jsonb_build_object(
      'success', false,
      'error', 'Email delivery failed: ' || SQLERRM
    );
  end;
end;
$$;

-- Grant execution to authenticated users
grant execute on function public.send_bearing_lifecycle_email(text, text, text) to authenticated;
grant execute on function public.send_bearing_lifecycle_email(text, text, text) to anon;
