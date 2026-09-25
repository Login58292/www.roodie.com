-- Roodie worker roster + unique-link tracking
-- Run this in a SEPARATE Supabase project dedicated to Roodie.
-- It does not use or modify the Soodie project.

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

-- Admin helper.
-- Run this from the Supabase SQL Editor to provision or update a worker.
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

-- Called automatically when a personalized Roodie link is opened.
-- The link contains only an opaque random invite token.
create or replace function public.register_roodie_visit(
  p_invite_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_worker public.roodie_workers%rowtype;
begin
  if p_invite_token is null or p_invite_token = '' then
    return jsonb_build_object('ok', false);
  end if;

  select *
  into v_worker
  from public.roodie_workers
  where invite_token_hash = encode(digest(p_invite_token, 'sha256'), 'hex')
    and status = 'Active'
  limit 1;

  if v_worker.id is null then
    return jsonb_build_object('ok', false);
  end if;

  insert into public.roodie_worker_visits(worker_id, worker_email)
  values(v_worker.id, v_worker.worker_email);

  return jsonb_build_object(
    'ok', true,
    'worker_email', v_worker.worker_email
  );
end;
$$;

-- Checks the company-issued worker email + Roodie-only access code.
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
  v_worker public.roodie_workers%rowtype;
  v_ok boolean := false;
begin
  select *
  into v_worker
  from public.roodie_workers
  where worker_email = v_email
    and status = 'Active'
  limit 1;

  if v_worker.id is not null and p_access_code is not null then
    v_ok := crypt(p_access_code, v_worker.access_code_hash) = v_worker.access_code_hash;
  end if;

  insert into public.roodie_worker_logins(worker_id, worker_email, success)
  values(v_worker.id, v_email, v_ok);

  return jsonb_build_object('ok', v_ok);
end;
$$;

revoke all on function public.admin_add_roodie_worker(text,text,text) from public;
revoke all on function public.register_roodie_visit(text) from public;
revoke all on function public.register_roodie_worker(text,text) from public;

grant execute on function public.register_roodie_visit(text) to anon, authenticated;
grant execute on function public.register_roodie_worker(text,text) to anon, authenticated;

-- Example provisioning (replace all placeholders, then run from SQL Editor):
--
-- select public.admin_add_roodie_worker(
--   'worker1@example.com',
--   'ROODIE-CODE-001',
--   'A_LONG_RANDOM_UNIQUE_TOKEN_FOR_WORKER_1'
-- );
--
-- Give that worker this personalized link:
-- https://YOUR-ROODIE-SITE/?invite=A_LONG_RANDOM_UNIQUE_TOKEN_FOR_WORKER_1
--
-- When that exact link is opened, the assigned worker email is recorded in
-- public.roodie_worker_visits automatically.
--
-- This does NOT inspect which Gmail account is signed into the phone/browser.
-- Browser privacy prevents a normal website from reading that information.
