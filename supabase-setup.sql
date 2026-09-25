-- Roodie installable worker-verification app
-- Safe verification data only:
--   * Google-verified email
--   * Google provider account ID
--   * Roodie installation ID
-- Gmail passwords, OTPs, recovery codes and browser credentials are never collected.

create table if not exists public.roodie_access_requests (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null,
  worker_email text not null,
  google_account_id text,
  install_id text,
  status text not null default 'Pending'
    check (status in ('Pending','Approved','Rejected','Blocked')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  last_checked_at timestamptz
);

alter table public.roodie_access_requests
  add column if not exists google_account_id text;

alter table public.roodie_access_requests
  add column if not exists install_id text;

create index if not exists roodie_access_requests_email_idx
  on public.roodie_access_requests(worker_email);

create index if not exists roodie_access_requests_google_install_idx
  on public.roodie_access_requests(google_account_id, install_id);

create index if not exists roodie_access_requests_status_idx
  on public.roodie_access_requests(status);

alter table public.roodie_access_requests enable row level security;
revoke all on table public.roodie_access_requests from anon, authenticated;

create or replace function public.register_roodie_installation(p_install_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  v_install_id text := trim(coalesce(p_install_id, ''));
  v_google_account_id text;
  v_request public.roodie_access_requests%rowtype;
begin
  if v_uid is null or v_email = '' then
    return jsonb_build_object('ok', false, 'status', 'Unauthenticated');
  end if;

  if length(v_install_id) < 16 or length(v_install_id) > 128 then
    return jsonb_build_object('ok', false, 'status', 'InvalidInstall');
  end if;

  select i.provider_id
    into v_google_account_id
  from auth.identities i
  where i.user_id = v_uid
    and i.provider = 'google'
  order by i.updated_at desc nulls last, i.created_at desc
  limit 1;

  if v_google_account_id is null or v_google_account_id = '' then
    return jsonb_build_object('ok', false, 'status', 'NoGoogleIdentity');
  end if;

  select *
    into v_request
  from public.roodie_access_requests
  where google_account_id = v_google_account_id
    and install_id = v_install_id
  order by requested_at desc
  limit 1;

  if v_request.id is not null then
    update public.roodie_access_requests
       set worker_email = v_email,
           auth_user_id = v_uid,
           last_checked_at = now()
     where id = v_request.id;

    return jsonb_build_object(
      'ok', v_request.status = 'Approved',
      'status', v_request.status,
      'worker_email', v_email,
      'google_account_id', v_google_account_id,
      'install_id', v_install_id,
      'request_id', v_request.id
    );
  end if;

  insert into public.roodie_access_requests(
    auth_user_id,
    worker_email,
    google_account_id,
    install_id,
    status,
    requested_at,
    last_checked_at
  )
  values(
    v_uid,
    v_email,
    v_google_account_id,
    v_install_id,
    'Pending',
    now(),
    now()
  )
  returning * into v_request;

  return jsonb_build_object(
    'ok', false,
    'status', 'Pending',
    'worker_email', v_email,
    'google_account_id', v_google_account_id,
    'install_id', v_install_id,
    'request_id', v_request.id
  );
end;
$$;

create or replace function public.check_roodie_installation(p_install_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  v_install_id text := trim(coalesce(p_install_id, ''));
  v_google_account_id text;
  v_request public.roodie_access_requests%rowtype;
begin
  if v_uid is null or v_email = '' then
    return jsonb_build_object('ok', false, 'status', 'Unauthenticated');
  end if;

  if length(v_install_id) < 16 or length(v_install_id) > 128 then
    return jsonb_build_object('ok', false, 'status', 'InvalidInstall');
  end if;

  select i.provider_id
    into v_google_account_id
  from auth.identities i
  where i.user_id = v_uid
    and i.provider = 'google'
  order by i.updated_at desc nulls last, i.created_at desc
  limit 1;

  if v_google_account_id is null or v_google_account_id = '' then
    return jsonb_build_object('ok', false, 'status', 'NoGoogleIdentity');
  end if;

  select *
    into v_request
  from public.roodie_access_requests
  where google_account_id = v_google_account_id
    and install_id = v_install_id
  order by requested_at desc
  limit 1;

  if v_request.id is null then
    return jsonb_build_object('ok', false, 'status', 'NotFound');
  end if;

  update public.roodie_access_requests
     set worker_email = v_email,
         auth_user_id = v_uid,
         last_checked_at = now()
   where id = v_request.id;

  return jsonb_build_object(
    'ok', v_request.status = 'Approved',
    'status', v_request.status,
    'worker_email', v_email,
    'google_account_id', v_google_account_id,
    'install_id', v_install_id,
    'request_id', v_request.id
  );
end;
$$;

revoke all on function public.register_roodie_installation(text) from public, anon, authenticated;
grant execute on function public.register_roodie_installation(text) to authenticated;

revoke all on function public.check_roodie_installation(text) from public, anon, authenticated;
grant execute on function public.check_roodie_installation(text) to authenticated;

drop view if exists public.roodie_access_review;

create view public.roodie_access_review
with (security_invoker = true)
as
select
  id,
  worker_email as email,
  google_account_id,
  install_id,
  status,
  requested_at,
  reviewed_at,
  last_checked_at
from public.roodie_access_requests;

revoke all on table public.roodie_access_review from anon, authenticated;

-- ADMIN APPROVAL:
-- Supabase Dashboard -> Table Editor -> roodie_access_requests
-- Find the Gmail + install_id pair and change Pending -> Approved.
