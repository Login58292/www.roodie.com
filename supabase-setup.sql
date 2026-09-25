-- Run this only in a NEW Supabase project dedicated to Roodie.
-- This does not use or modify the Soodie project.

create extension if not exists pgcrypto;

create table if not exists public.roodie_worker_requests (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  access_code_hash text not null,
  status text not null default 'Pending'
    check (status in ('Pending','Approved','Rejected','Blocked')),
  requested_at timestamptz not null default now(),
  approved_at timestamptz
);

alter table public.roodie_worker_requests enable row level security;

create or replace function public.register_roodie_worker(
  p_email text,
  p_access_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email text := lower(trim(p_email));
  v_id uuid;
begin
  if v_email is null or v_email = '' or position('@' in v_email) < 2 then
    raise exception 'Invalid email';
  end if;

  if p_access_code is null or length(p_access_code) < 6 then
    raise exception 'Access code too short';
  end if;

  insert into public.roodie_worker_requests(email, access_code_hash)
  values (v_email, crypt(p_access_code, gen_salt('bf')))
  returning id into v_id;

  return jsonb_build_object(
    'ok', true,
    'request_id', v_id,
    'status', 'Pending'
  );
end;
$$;

revoke all on function public.register_roodie_worker(text,text) from public;
grant execute on function public.register_roodie_worker(text,text) to anon, authenticated;

-- Admins can review email/status in Supabase.
-- The Roodie access code is stored only as a one-way bcrypt hash.
-- Do not store Gmail passwords, Google OTPs, recovery codes, or verification codes.
