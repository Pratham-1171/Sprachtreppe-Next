-- =====================================================================
--  Sprachtreppe backend (Supabase / PostgreSQL)
--  Run this ONCE in: Supabase Dashboard → SQL Editor → New query → Run.
--
--  Security design
--   * Passwords are handled only by Supabase Auth (bcrypt hashes, rate-limited). Nothing in the app or in this
--     database ever contains a password.
--   * Every table has Row-Level-Security. A student can read ONLY his own rows and can write NOTHING directly;
--     progress is accepted through the submit_progress() function, which validates size / rate / approval.
--   * Roles are never taken from user-editable data. The first administrator is promoted by you, once, in the
--     SQL editor (see the last section). Students cannot change role/approved, not even by editing the app.
-- =====================================================================

-- ---------- profiles ----------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text not null,
  full_name   text not null default '',
  role        text not null default 'student' check (role in ('student','teacher','admin')),
  approved    boolean not null default false,
  created_at  timestamptz not null default now()
);
alter table public.profiles enable row level security;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin' and p.approved);
$$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- role / approved always start as student / false, whatever the sign-up request contained
  insert into public.profiles (id, email, full_name)
  values (new.id, coalesce(new.email, ''), left(coalesce(new.raw_user_meta_data->>'full_name', ''), 80));
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.profiles_guard() returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user in ('anon','authenticated') and
     (new.id is distinct from old.id or new.email is distinct from old.email or new.role is distinct from old.role
      or new.full_name is distinct from old.full_name or new.created_at is distinct from old.created_at) then
    raise exception 'only the approved flag can be changed through the API' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard before update on public.profiles for each row execute function public.profiles_guard();

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.is_admin());
drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update on public.profiles for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------- submissions (the weekly updates sent to the admin) ----------
create table if not exists public.submissions (
  id            bigint generated always as identity primary key,
  student_id    uuid not null references public.profiles(id) on delete cascade,
  client_id     text not null check (char_length(client_id) between 8 and 64),
  created_at    timestamptz not null default now(),          -- SERVER time: the student's clock is irrelevant here
  summary       jsonb not null,
  payload       jsonb not null,
  review_status text not null default 'pending' check (review_status in ('pending','reviewed','flagged')),
  review_note   text check (char_length(review_note) <= 2000),
  rating        smallint check (rating between 1 and 5),
  reviewed_at   timestamptz,
  reviewed_by   uuid references public.profiles(id),
  student_seen  boolean not null default true,
  unique (student_id, client_id)
);
create index if not exists submissions_student_idx on public.submissions (student_id, created_at desc);
create index if not exists submissions_reviewed_by_idx on public.submissions (reviewed_by);
alter table public.submissions enable row level security;

create or replace function public.submissions_guard() returns trigger language plpgsql set search_path = '' as $$
begin
  if new.student_id is distinct from old.student_id or new.client_id is distinct from old.client_id
     or new.created_at is distinct from old.created_at or new.summary is distinct from old.summary
     or new.payload is distinct from old.payload then
    raise exception 'submissions are immutable; only review fields can change' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists submissions_guard on public.submissions;
create trigger submissions_guard before update on public.submissions for each row execute function public.submissions_guard();

drop policy if exists submissions_select on public.submissions;
create policy submissions_select on public.submissions for select to authenticated
  using (student_id = (select auth.uid()) or public.is_admin());
drop policy if exists submissions_admin_update on public.submissions;
create policy submissions_admin_update on public.submissions for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
-- no INSERT / DELETE policy for anyone: inserts only through submit_progress()

-- ---------- table privileges (defence in depth on top of RLS) ----------
revoke all on public.profiles, public.submissions from anon, authenticated;
grant select on public.profiles, public.submissions to authenticated;
grant update (approved) on public.profiles to authenticated;
grant update (review_status, review_note, rating, reviewed_at, reviewed_by, student_seen) on public.submissions to authenticated;

-- ---------- functions used by the app ----------
create or replace function public.submit_progress(p_payload jsonb, p_client_id text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_prof public.profiles;
  v_recent int;
  v_id bigint;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select * into v_prof from public.profiles where id = v_uid;
  if not found or not v_prof.approved then raise exception 'account not approved' using errcode = '42501'; end if;
  if v_prof.role = 'admin' then return jsonb_build_object('ok', true, 'server_time', now(), 'skipped', 'admin', 'feedback', '[]'::jsonb); end if;
  if p_client_id is null or char_length(p_client_id) not between 8 and 64 then raise exception 'bad client id' using errcode = '22023'; end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' or jsonb_typeof(p_payload->'summary') <> 'object' then
    raise exception 'bad payload' using errcode = '22023';
  end if;
  if octet_length(p_payload::text) > 600000 then raise exception 'payload too large' using errcode = '54000'; end if;
  select count(*) into v_recent from public.submissions where student_id = v_uid and created_at > now() - interval '1 day';
  if v_recent >= 48 then raise exception 'too many submissions today' using errcode = '54000'; end if;

  insert into public.submissions (student_id, client_id, summary, payload)
  values (v_uid, p_client_id, p_payload->'summary', p_payload - 'summary')
  on conflict (student_id, client_id) do nothing
  returning id into v_id;

  return jsonb_build_object(
    'ok', true, 'server_time', now(), 'duplicate', v_id is null,
    'feedback', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'status', s.review_status, 'note', s.review_note,
                           'rating', s.rating, 'reviewed_at', s.reviewed_at) order by s.reviewed_at)
                          from public.submissions s where s.student_id = v_uid and s.student_seen = false), '[]'::jsonb));
end $$;

create or replace function public.ack_feedback(p_ids bigint[]) returns void
language sql security definer set search_path = '' as $$
  update public.submissions set student_seen = true where student_id = auth.uid() and id = any(p_ids);
$$;

create or replace function public.server_time() returns timestamptz language sql stable set search_path = '' as $$ select now() $$;

create or replace function public.admin_overview()
returns table (id uuid, email text, full_name text, role text, approved boolean, created_at timestamptz,
               last_sync_at timestamptz, submissions bigint, unreviewed bigint, last_summary jsonb)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return query
    select p.id, p.email, p.full_name, p.role, p.approved, p.created_at,
           max(s.created_at), count(s.id), count(s.id) filter (where s.review_status = 'pending'),
           (select s2.summary from public.submissions s2 where s2.student_id = p.id order by s2.created_at desc limit 1)
    from public.profiles p left join public.submissions s on s.student_id = p.id
    group by p.id
    order by p.created_at desc;
end $$;

revoke all on function public.submit_progress(jsonb, text), public.ack_feedback(bigint[]), public.admin_overview(),
                       public.server_time(), public.is_admin(), public.handle_new_user() from public, anon, authenticated;
grant execute on function public.submit_progress(jsonb, text), public.ack_feedback(bigint[]), public.admin_overview(),
                          public.server_time(), public.is_admin() to authenticated;

-- =====================================================================
--  FIRST ADMINISTRATOR  (run separately, after you created your own account)
--  1. Dashboard → Authentication → Users → "Add user" (email + a long passphrase, tick "Auto Confirm User").
--  2. Then run, with YOUR email:
--
--     update public.profiles set role = 'admin', approved = true where email = 'you@example.com';
--
--  There is intentionally no way to do this from inside the app.
-- =====================================================================
