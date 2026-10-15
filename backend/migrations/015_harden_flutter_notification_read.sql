-- Keep notification read-marking as SECURITY INVOKER with a column-level grant.

begin;

revoke all on public.notifications from public, anon, authenticated;
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

drop policy if exists notifications_update_read_own on public.notifications;
create policy notifications_update_read_own
  on public.notifications
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create or replace function public.mark_notification_read(p_id bigint)
returns void
language plpgsql
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
