-- Shared notification inbox required by the Flutter APK and web app.
-- This minimal migration is intentionally separate from the incompatible LMS phases.

begin;

create table if not exists public.notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null default 'info',
  title text not null check (char_length(trim(title)) between 1 and 180),
  body text not null default '',
  link text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

revoke all on public.notifications from public, anon, authenticated;
grant select on public.notifications to authenticated;

drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own
  on public.notifications
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create or replace function public.mark_notification_read(p_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  update public.notifications
     set read_at = coalesce(read_at, now())
   where id = p_id
     and user_id = auth.uid();
end;
$$;

revoke all on function public.mark_notification_read(bigint) from public, anon;
grant execute on function public.mark_notification_read(bigint) to authenticated;

commit;
