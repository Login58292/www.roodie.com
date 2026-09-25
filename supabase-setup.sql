-- Roodie: Google sign-in automatically matches a pre-linked Roodie worker code.
-- Workers do NOT type the Roodie code.
-- The administrator links each Gmail -> Roodie code before the worker signs in.

create extension if not exists pgcrypto;

create table if not exists public.roodie_email_codes (
  id uuid primary key default gen_random_uuid(),
  worker_email text not null unique,
  worker_code text not null,
  status text not null default 'Active'
    check (status in ('Active','Blocked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.roodie_access_requests (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null,
  worker_email text not null,
  linked_code text,
  status text not null default 'Pending'
    check (status in ('Pending','Approved','Rejected','Blocked')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  last_checked_at timestamptz
);

create index if not exists roodie_access_requests_email_idx
  on public.roodie_access_requests(worker_email);

create index if not exists roodie_access_requests_status_idx
  on public.roodie_access_requests(status);

alter table public.roodie_email_codes enable row level security;
alter table public.roodie_access_requests enable row level security;

revoke all on table public.roodie_email_codes from anon, authenticated;
revoke all on table public.roodie_access_requests from anon, authenticated;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- Admin-only helper: link one verified Gmail to one Roodie code.
create or replace function private.admin_set_roodie_email_code(
  p_email text,
  p_worker_code text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_code text := trim(coalesce(p_worker_code, ''));
  v_id uuid;
begin
  if v_email = '' or position('@' in v_email) < 2 then
    raise exception 'Invalid worker email';
  end if;

  if v_code = '' then
    raise exception 'Worker code is required';
  end if;

  insert into public.roodie_email_codes(worker_email, worker_code, status)
  values(v_email, v_code, 'Active')
  on conflict (worker_email)
  do update set
    worker_code = excluded.worker_code,
    status = 'Active',
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

-- Called automatically after Google sign-in.
-- The browser does not send an email or a code.
-- Both are resolved server-side from the Google-authenticated session and the admin mapping.
create or replace function public.register_roodie_google_signin()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  v_link public.roodie_email_codes%rowtype;
  v_request public.roodie_access_requests%rowtype;
begin
  if v_uid is null or v_email = '' then
    return jsonb_build_object('ok', false, 'status', 'Unauthenticated');
  end if;

  select *
  into v_link
  from public.roodie_email_codes
  where worker_email = v_email
    and status = 'Active'
  limit 1;

  if v_link.id is null then
    return jsonb_build_object(
      'ok', false,
      'status', 'NoCode',
      'worker_email', v_email
    );
  end if;

  select *
  into v_request
  from public.roodie_access_requests
  where worker_email = v_email
    and linked_code = v_link.worker_code
  order by requested_at desc
  limit 1;

  if v_request.id is not null then
    update public.roodie_access_requests
    set last_checked_at = now()
    where id = v_request.id;

    return jsonb_build_object(
      'ok', v_request.status = 'Approved',
      'status', v_request.status,
      'worker_email', v_email,
      'request_id', v_request.id
    );
  end if;

  insert into public.roodie_access_requests(
    auth_user_id,
    worker_email,
    linked_code,
    status,
    requested_at,
    last_checked_at
  )
  values(
    v_uid,
    v_email,
    v_link.worker_code,
    'Pending',
    now(),
    now()
  )
  returning * into v_request;

  return jsonb_build_object(
    'ok', false,
    'status', 'Pending',
    'worker_email', v_email,
    'request_id', v_request.id
  );
end;
$$;

create or replace function public.check_roodie_google_signin()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  v_link public.roodie_email_codes%rowtype;
  v_request public.roodie_access_requests%rowtype;
begin
  if v_uid is null or v_email = '' then
    return jsonb_build_object('ok', false, 'status', 'Unauthenticated');
  end if;

  select *
  into v_link
  from public.roodie_email_codes
  where worker_email = v_email
    and status = 'Active'
  limit 1;

  if v_link.id is null then
    return jsonb_build_object('ok', false, 'status', 'NoCode');
  end if;

  select *
  into v_request
  from public.roodie_access_requests
  where worker_email = v_email
    and linked_code = v_link.worker_code
  order by requested_at desc
  limit 1;

  if v_request.id is null then
    return jsonb_build_object('ok', false, 'status', 'NotFound');
  end if;

  update public.roodie_access_requests
  set last_checked_at = now()
  where id = v_request.id;

  return jsonb_build_object(
    'ok', v_request.status = 'Approved',
    'status', v_request.status,
    'request_id', v_request.id
  );
end;
$$;

revoke all on function private.admin_set_roodie_email_code(text,text) from public, anon, authenticated;
grant execute on function private.admin_set_roodie_email_code(text,text) to service_role;

revoke all on function public.register_roodie_google_signin() from public, anon, authenticated;
grant execute on function public.register_roodie_google_signin() to authenticated;

revoke all on function public.check_roodie_google_signin() from public, anon, authenticated;
grant execute on function public.check_roodie_google_signin() to authenticated;

-- Example: run from Supabase SQL Editor / trusted admin context:
--
-- select private.admin_set_roodie_email_code(
--   'worker@example.com',
--   'ROODIE-001'
-- );
--
-- After that worker signs in with Google:
-- public.roodie_access_requests receives:
--   worker_email = worker@example.com
--   linked_code   = ROODIE-001
--   status        = Pending
--
-- Approve in Table Editor by changing status to Approved.
