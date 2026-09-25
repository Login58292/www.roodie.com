-- Roodie: Google sign-in + automatic Google account ID capture
-- Workers only sign in with Google.
-- Roodie records the verified Gmail and Google's unique provider account ID.
-- No manual Gmail-to-code mapping is required.

create table if not exists public.roodie_access_requests (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null,
  worker_email text not null,
  google_account_id text,
  status text not null default 'Pending'
    check (status in ('Pending','Approved','Rejected','Blocked')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  last_checked_at timestamptz
);

alter table public.roodie_access_requests
  add column if not exists google_account_id text;

create index if not exists roodie_access_requests_email_idx
  on public.roodie_access_requests(worker_email);

create index if not exists roodie_access_requests_google_account_id_idx
  on public.roodie_access_requests(google_account_id);

create index if not exists roodie_access_requests_status_idx
  on public.roodie_access_requests(status);

alter table public.roodie_access_requests enable row level security;
revoke all on table public.roodie_access_requests from anon, authenticated;

-- Called automatically after a successful Google OAuth sign-in.
-- The Google account ID is read server-side from auth.identities.provider_id.
create or replace function public.register_roodie_google_signin()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  v_google_account_id text;
  v_request public.roodie_access_requests%rowtype;
begin
  if v_uid is null or v_email = '' then
    return jsonb_build_object('ok', false, 'status', 'Unauthenticated');
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
  order by requested_at desc
  limit 1;

  if v_request.id is not null then
    update public.roodie_access_requests
    set
      worker_email = v_email,
      auth_user_id = v_uid,
      last_checked_at = now()
    where id = v_request.id;

    return jsonb_build_object(
      'ok', v_request.status = 'Approved',
      'status', v_request.status,
      'worker_email', v_email,
      'google_account_id', v_google_account_id,
      'request_id', v_request.id
    );
  end if;

  insert into public.roodie_access_requests(
    auth_user_id,
    worker_email,
    google_account_id,
    status,
    requested_at,
    last_checked_at
  )
  values(
    v_uid,
    v_email,
    v_google_account_id,
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
    'request_id', v_request.id
  );
end;
$$;

create or replace function public.check_roodie_google_signin()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  v_google_account_id text;
  v_request public.roodie_access_requests%rowtype;
begin
  if v_uid is null or v_email = '' then
    return jsonb_build_object('ok', false, 'status', 'Unauthenticated');
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
  order by requested_at desc
  limit 1;

  if v_request.id is null then
    return jsonb_build_object('ok', false, 'status', 'NotFound');
  end if;

  update public.roodie_access_requests
  set
    worker_email = v_email,
    auth_user_id = v_uid,
    last_checked_at = now()
  where id = v_request.id;

  return jsonb_build_object(
    'ok', v_request.status = 'Approved',
    'status', v_request.status,
    'worker_email', v_email,
    'google_account_id', v_google_account_id,
    'request_id', v_request.id
  );
end;
$$;

revoke all on function public.register_roodie_google_signin() from public, anon, authenticated;
grant execute on function public.register_roodie_google_signin() to authenticated;

revoke all on function public.check_roodie_google_signin() from public, anon, authenticated;
grant execute on function public.check_roodie_google_signin() to authenticated;

-- ADMIN REVIEW:
-- Supabase Dashboard -> Table Editor -> roodie_access_requests
--
-- A successful Google sign-in creates or reuses a row containing:
--   worker_email       = verified Gmail from Google
--   google_account_id  = Google's unique provider account ID
--   status             = Pending
--
-- Change status from Pending to Approved to grant access.
