begin;

create or replace function public.sync_learning_answer_events(p_events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_events is null or jsonb_typeof(p_events) <> 'array' then
    raise exception 'answer events must be a JSON array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_events) > 500 then
    raise exception 'an answer-event batch may contain at most 500 records' using errcode = '22023';
  end if;
  if octet_length(p_events::text) > 700000 then
    raise exception 'answer-event batch exceeds the 700 KB limit' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_events) item(value)
    where jsonb_typeof(item.value) <> 'object'
      or coalesce(item.value ->> 'id', '') = ''
      or length(item.value ->> 'id') > 160
  ) then
    raise exception 'each answer event must be an object with a stable ID' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = v_user_id and p.role = 'student' and p.approved = true
  ) then
    raise exception 'approved student account required' using errcode = '42501';
  end if;

  v_result := public.sync_learning_state(
    jsonb_build_object('flutter', jsonb_build_object('answerEvents', p_events))
  );

  return jsonb_build_object(
    'revision', v_result -> 'revision',
    'updated_at', v_result -> 'updated_at',
    'eventsTotal', v_result #> '{state,flutter,summary,eventsTotal}'
  );
end;
$function$;

revoke all on function public.sync_learning_answer_events(jsonb) from public, anon;
grant execute on function public.sync_learning_answer_events(jsonb) to authenticated;

commit;