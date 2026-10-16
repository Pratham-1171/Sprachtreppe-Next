-- Password authentication replaced the former OTP-only student signup flow.
-- Student full names now come from Supabase Auth user metadata during signUp().

begin;

drop function if exists public.complete_student_signup(text);

commit;
