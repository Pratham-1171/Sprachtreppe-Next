-- Student self-registration support for passwordless Flutter authentication.
-- New Auth users are created by Supabase Auth and the existing trigger always
-- creates them as student + unapproved. This function only lets that pending
-- student set their display name after verifying the email OTP.

begin;

create or replace function public.complete_student_signup(p_full_name text)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles;
  v_name text := left(trim(coalesce(p_full_name, '')), 80);
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode='28000';
  end if;
  if v_name = '' then
    raise exception 'full name is required' using errcode='22023';
  end if;

  update public.profiles
     set full_name = v_name
   where id = v_uid
     and role = 'student'
     and approved = false
   returning * into v_profile;

  if not found then
    raise exception 'student registration is unavailable for this account' using errcode='42501';
  end if;

  return v_profile;
end;
$$;

revoke all on function public.complete_student_signup(text) from public, anon;
grant execute on function public.complete_student_signup(text) to authenticated;

commit;
