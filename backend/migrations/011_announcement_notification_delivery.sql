-- Deliver announcement notifications to the correct approved student audience.
-- The original INSERT is still authorized by announcements RLS:
-- admins can publish school-wide or class-specific notices; teachers are restricted
-- to their own assigned classes. This trigger only fans out the successful insert.
create or replace function public.notify_announcement_recipients()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.class_id is null then
    insert into public.notifications (user_id, kind, title, body, link)
    select
      p.id,
      'announcement',
      left('New announcement: ' || new.title, 180),
      left(coalesce(new.body, ''), 2000),
      '#/notifications'
    from public.profiles p
    where p.role = 'student'
      and p.approved = true;
  else
    insert into public.notifications (user_id, kind, title, body, link)
    select distinct
      p.id,
      'announcement',
      left('New announcement: ' || new.title, 180),
      left(coalesce(new.body, ''), 2000),
      '#/notifications'
    from public.class_members cm
    join public.profiles p on p.id = cm.student_id
    where cm.class_id = new.class_id
      and p.role = 'student'
      and p.approved = true;
  end if;

  return new;
end;
$$;

drop trigger if exists announcements_notify_students on public.announcements;
create trigger announcements_notify_students
after insert on public.announcements
for each row
execute function public.notify_announcement_recipients();

-- Trigger functions aren't RPC endpoints. Keep them unavailable to API roles.
revoke all on function public.notify_announcement_recipients()
from public, anon, authenticated;
