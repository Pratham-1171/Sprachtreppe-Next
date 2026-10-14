-- Revoke anonymous execution from protected SECURITY DEFINER functions.
-- Preserve authenticated execution for the signed-in app and its RLS policy helpers.
revoke execute on function public.admin_students_overview() from public, anon;
revoke execute on function public.assign_student_to_teacher(uuid, uuid) from public, anon;
revoke execute on function public.create_class(text) from public, anon;
revoke execute on function public.create_class_invite(bigint, text, timestamp with time zone, integer) from public, anon;
revoke execute on function public.is_staff() from public, anon;
revoke execute on function public.is_teacher() from public, anon;
revoke execute on function public.join_class_with_code(text) from public, anon;
revoke execute on function public.mark_notification_read(bigint) from public, anon;
revoke execute on function public.my_students() from public, anon;
revoke execute on function public.remove_my_student(uuid) from public, anon;
revoke execute on function public.remove_student_from_teacher(uuid, uuid) from public, anon;
revoke execute on function public.staff_audit(integer) from public, anon;

-- This function is trigger-only, never an API RPC.
revoke all on function public.notify_submission_event()
from public, anon, authenticated;
