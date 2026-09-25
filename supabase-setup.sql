-- Roodie worker roster + verified Google sign-in
-- Run this in a SEPARATE Supabase project dedicated to Roodie.
-- Google Auth must be enabled in Supabase before the web flow can sign workers in.

create extension if not exists pgcrypto;

create table if not exists public.roodie_workers (
  id uuid primary key default gen_random_uuid(),
  worker_email text not null unique,
  access_code_hash text not null,
  invite_token_hash text not null unique,
  status text not null default 'Active'
    check (status in ('Active','Blocked')),
  created_at timestamptz not null default now()
);

create table if not exists public.roodie_worker_visits (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references public.roodie_workers(id) on delete cascade,
  worker_email text not null,
  visited_at timestamptz not null default now()
);

create table if not exists public.roodie_worker_logins (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid references public.roodie_workers(id) on delete set null,
  worker_email text not null,
  success boolean not null,
  attempted_at timestamptz not null default now()
);

alter table public.roodie_workers enable row level security;
alter table public.roodie_worker_visits enable row level security;
alter table public.roodie_worker_logins enable row level security;

-- No direct browser access to roster or logs.
revoke all on table public.roodie_workers from anon, authenticated;
revoke all on table public.roodie_worker_visits from anon, authenticated;
revoke all on table public.roodie_worker_logins from anon, authenticated;

-- Admin helper. Run only from Supabase SQL Editor.
-- Use a different long random invite token for every worker.
create or replace function public.admin_add_roodie_worker(
  p_email text,
  p_access_code text,
  p_invite_token text
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email text := lower(trim(p_email));
  v_worker_id uuid;
begin
  if v_email is null or v_email = '' or position('@' in v_email) < 2 then
    raise exception 'Invalid worker email';
  end if;

  if p_access_code is null or length(p_access_code) < 6 then
    raise exception 'Roodie access code must be at least 6 characters';
  end if;

  if p_invite_token is null or length(p_invite_token) < 24 then
    raise exception 'Invite token must be at least 24 characters';
  end if;

  insert into public.roodie_workers(
    worker_email,
    access_code_hash,
    invite_token_hash,
    status
  )
  values(
    v_email,
    crypt(p_access_code, gen_salt('bf')),
    encode(digest(p_invite_token, 'sha256'), 'hex'),
    'Active'
  )
  on conflict (worker_email)
  do update set
    access_code_hash = excluded.access_code_hash,
    invite_token_hash = excluded.invite_token_hash,
    status = 'Active'
  returning id into v_worker_id;

  return v_worker_id;
end;
$$;

-- Called only after a worker has authenticated with Google.
-- The invite token must belong to the same worker email Google verified.
create or replace function public.register_roodie_visit(
  p_invite_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  v_worker public.roodie_workers%rowtype;
begin
  if auth.uid() is null or v_email = '' then
    return jsonb_build_object('ok', false);
  end if;

  if p_invite_token is null or p_invite_token = '' then
    return jsonb_build_object('ok', false);
  end if;

  select *
  into v_worker
  from public.roodie_workers
  where worker_email = v_email
    and invite_token_hash = encode(digest(p_invite_token, 'sha256'), 'hex')
    and status = 'Active'
  limit 1;

  if v_worker.id is null then
    return jsonb_build_object('ok', false);
  end if;

  insert into public.roodie_worker_visits(worker_id, worker_email)
  values(v_worker.id, v_email);

  return jsonb_build_object('ok', true);
end;
$$;

-- Verify the Roodie-issued code against the email from the authenticated
-- Google/Supabase session. The client is not allowed to supply an email.
drop function if exists public.register_roodie_worker(text, text);

create or replace function public.register_roodie_worker(
  p_access_code text,
  p_invite_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  v_worker public.roodie_workers%rowtype;
  v_ok boolean := false;
begin
  if auth.uid() is null or v_email = '' then
    return jsonb_build_object('ok', false);
  end if;

  select *
  into v_worker
  from public.roodie_workers
  where worker_email = v_email
    and status = 'Active'
  limit 1;

  if v_worker.id is not null and p_access_code is not null then
    v_ok := crypt(p_access_code, v_worker.access_code_hash) = v_worker.access_code_hash;

    -- If a personalized invite link is present, it must belong to this worker.
    if v_ok and p_invite_token is not null and p_invite_token <> '' then
      v_ok := v_worker.invite_token_hash =
        encode(digest(p_invite_token, 'sha256'), 'hex');
    end if;
  end if;

  insert into public.roodie_worker_logins(worker_id, worker_email, success)
  values(v_worker.id, v_email, v_ok);

  if v_ok then
    return jsonb_build_object('ok', true, 'worker_email', v_email);
  end if;

  return jsonb_build_object('ok', false);
end;
$$;

-- PostgreSQL grants EXECUTE to PUBLIC on new functions by default.
-- Remove that and allow only the intended caller.
revoke all on function public.admin_add_roodie_worker(text,text,text) from public;
revoke all on function public.register_roodie_visit(text) from public;
revoke all on function public.register_roodie_worker(text,text) from public;

grant execute on function public.register_roodie_visit(text) to authenticated;
grant execute on function public.register_roodie_worker(text,text) to authenticated;

-- Example provisioning:
--
-- select public.admin_add_roodie_worker(
--   'worker1@gmail.com',
--   'ROODIE-CODE-001',
--   'A_LONG_RANDOM_UNIQUE_TOKEN_FOR_WORKER_1'
-- );
--
-- Personalized worker link:
-- https://YOUR-ROODIE-SITE/?invite=A_LONG_RANDOM_UNIQUE_TOKEN_FOR_WORKER_1
--
-- Flow:
-- 1. Worker opens Roodie.
-- 2. Worker chooses/approves a Google account.
-- 3. Google/Supabase provides the verified email to Roodie.
-- 4. Worker enters only the Roodie-issued access code.
-- 5. This function checks that verified email + Roodie code match the roster.
--
-- Roodie never requests or stores Gmail passwords, Google OTPs,
-- backup codes, or 2-step-verification codes.
