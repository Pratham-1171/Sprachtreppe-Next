-- Guard rails for the canonical Next LMS schema.
begin;
create or replace function public.enforce_student_submission_insert()
returns trigger language plpgsql security definer set search_path=''
as $fn$
begin
 if auth.uid() is null or new.student_id is distinct from auth.uid() or not public.is_approved_student() then
  raise exception 'only an approved student can submit learning progress' using errcode='42501';
 end if;
 return new;
end; $fn$;
drop trigger if exists submissions_student_role_guard on public.submissions;
create trigger submissions_student_role_guard before insert on public.submissions for each row execute function public.enforce_student_submission_insert();
revoke all on function public.enforce_student_submission_insert() from public,anon,authenticated;
do $fn$
begin
 if not exists(select 1 from pg_constraint where conrelid='public.assignment_progress'::regclass and conname='assignment_progress_correct_le_done') then
  alter table public.assignment_progress add constraint assignment_progress_correct_le_done check(correct<=done) not valid;
 end if;
end; $fn$;
alter table public.assignment_progress validate constraint assignment_progress_correct_le_done;
commit;