-- Roodie: Google sign-in + administrator-approved worker PIN flow
-- Google authentication supplies only the verified email/session.
-- The Roodie PIN is a separate app credential entered by the worker.

create extension if not exists pgcrypto;

create table if not exists public.roodie_access_requests (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null,
  worker_email text not null,
  submitted_pin text,
  pin_hash text,
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

alter table public.roodie_access_requests enable row level security;
revoke all on table public.roodie_access_requests from anon, authenticated;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.finalize_roodie_pin_review()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if old.status = 'Pending' and new.status <> 'Pending' then
    if old.submitted_pin is not null and old.submitted_pin <> '' then
      new.pin_hash := crypt(old.submitted_pin, gen_salt('bf'));
    end if;
    new.submitted_pin := null;
    new.reviewed_at := now();
  elsif old.status <> 'Pending' and new.status = 'Pending' then
    raise exception 'Reviewed requests cannot be returned to Pending because the visible PIN has already been cleared';
  end if;

  return new;
end;
$$;

drop trigger if exists roodie_finalize_pin_review on public.roodie_access_requests;
create trigger roodie_finalize_pin_review
before update of status on public.roodie_access_requests
for each row
execute function private.finalize_roodie_pin_review();

create or replace function public.submit_roodie_pin(p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  v_pin text := trim(coalesce(p_pin, ''));
  v_request public.roodie_access_requests%rowtype;
begin
  if v_uid is null or v_email = '' then
    return jsonb_build_object('ok', false, 'status', 'Unauthenticated');
  end if;

  if length(v_pin) < 4 or length(v_pin) > 32 then
    return jsonb_build_object('ok', false, 'status', 'Invalid', 'message', 'PIN must be 4 to 32 characters.');
  end if;

  select *
  into v_request
  from public.roodie_access_requests
  where worker_email = v_email
    and status = 'Pending'
    and submitted_pin = v_pin
  order by requested_at desc
  limit 1;

  if v_request.id is not null then
    update public.roodie_access_requests
    set last_checked_at = now()
    where id = v_request.id;

    return jsonb_build_object('ok', false, 'status', 'Pending', 'request_id', v_request.id);
  end if;

  for v_request in
    select *
    from public.roodie_access_requests
    where worker_email = v_email
      and status <> 'Pending'
      and pin_hash is not null
    order by requested_at desc
  loop
    if crypt(v_pin, v_request.pin_hash) = v_request.pin_hash then
      update public.roodie_access_requests
      set last_checked_at = now()
      where id = v_request.id;

      return jsonb_build_object(
        'ok', v_request.status = 'Approved',
        'status', v_request.status,
        'request_id', v_request.id
      );
    end if;
  end loop;

  insert into public.roodie_access_requests(
    auth_user_id,
    worker_email,
    submitted_pin,
    status
  )
  values(
    v_uid,
    v_email,
    v_pin,
    'Pending'
  )
  returning * into v_request;

  return jsonb_build_object('ok', false, 'status', 'Pending', 'request_id', v_request.id);
end;
$$;

create or replace function public.check_roodie_pin(p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  v_pin text := trim(coalesce(p_pin, ''));
  v_request public.roodie_access_requests%rowtype;
begin
  if v_uid is null or v_email = '' then
    return jsonb_build_object('ok', false, 'status', 'Unauthenticated');
  end if;

  select *
  into v_request
  from public.roodie_access_requests
  where worker_email = v_email
    and status = 'Pending'
    and submitted_pin = v_pin
  order by requested_at desc
  limit 1;

  if v_request.id is not null then
    update public.roodie_access_requests
    set last_checked_at = now()
    where id = v_request.id;

    return jsonb_build_object('ok', false, 'status', 'Pending');
  end if;

  for v_request in
    select *
    from public.roodie_access_requests
    where worker_email = v_email
      and status <> 'Pending'
      and pin_hash is not null
    order by requested_at desc
  loop
    if crypt(v_pin, v_request.pin_hash) = v_request.pin_hash then
      update public.roodie_access_requests
      set last_checked_at = now()
      where id = v_request.id;

      return jsonb_build_object(
        'ok', v_request.status = 'Approved',
        'status', v_request.status
      );
    end if;
  end loop;

  return jsonb_build_object('ok', false, 'status', 'NotFound');
end;
$$;

revoke all on function private.finalize_roodie_pin_review() from public, anon, authenticated;

revoke all on function public.submit_roodie_pin(text) from public, anon, authenticated;
grant execute on function public.submit_roodie_pin(text) to authenticated;

revoke all on function public.check_roodie_pin(text) from public, anon, authenticated;
grant execute on function public.check_roodie_pin(text) to authenticated;

-- ADMIN APPROVAL:
-- Supabase Dashboard -> Table Editor -> roodie_access_requests
-- Change a Pending row's status to Approved.
-- While Pending, submitted_pin is visible to the database administrator.
-- After review, the trigger clears submitted_pin and retains only a bcrypt hash.