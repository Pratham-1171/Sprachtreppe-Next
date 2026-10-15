begin;

-- Durable, per-student, idempotent answer ledger. The client cannot read/write
-- this table directly; the guarded SECURITY DEFINER RPCs are the only interface.
create table if not exists public.learning_answer_events (
  user_id uuid not null references public.profiles(id) on delete cascade,
  event_id text not null check (length(event_id) between 1 and 160),
  event_data jsonb not null check (jsonb_typeof(event_data) = 'object'),
  created_at timestamptz not null default now(),
  primary key (user_id, event_id)
);
create index if not exists learning_answer_events_user_created_idx
  on public.learning_answer_events (user_id, created_at desc);
alter table public.learning_answer_events enable row level security;
revoke all on table public.learning_answer_events from public, anon, authenticated;

-- Preserve answer history from earlier JSON-based snapshots before compacting them.
insert into public.learning_answer_events(user_id, event_id, event_data, created_at)
select s.user_id, item.value ->> 'id', item.value, now()
from public.learning_state s
cross join lateral jsonb_array_elements(
  case when jsonb_typeof(s.state #> '{flutter,answerEvents}') = 'array'
    then s.state #> '{flutter,answerEvents}' else '[]'::jsonb end
) item(value)
where jsonb_typeof(item.value) = 'object'
  and coalesce(item.value ->> 'id', '') <> ''
  and length(item.value ->> 'id') <= 160
on conflict (user_id, event_id) do nothing;

update public.learning_state
set state = state #- '{flutter,answerEvents}'
where jsonb_typeof(state #> '{flutter,answerEvents}') = 'array';

create or replace function private.refresh_learning_state_aggregates(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_state jsonb;
  v_flutter jsonb;
  v_vocabulary jsonb;
  v_grammar jsonb;
  v_mistakes jsonb;
  v_summary jsonb;
  v_session_count bigint := 0;
  v_total_questions bigint := 0;
  v_correct_answers bigint := 0;
  v_event_count bigint := 0;
  v_best_streak bigint := 0;
  v_current_streak bigint := 0;
begin
  select state into v_state from public.learning_state where user_id = p_user_id;
  if not found then return; end if;

  if jsonb_typeof(v_state -> 'flutter') <> 'object' then
    v_state := jsonb_set(coalesce(v_state, '{}'::jsonb), '{flutter}', '{}'::jsonb, true);
  end if;
  v_flutter := v_state -> 'flutter';

  select count(*) into v_event_count
  from public.learning_answer_events e where e.user_id = p_user_id;

  select coalesce(jsonb_object_agg(entity_id, jsonb_build_object(
    'attempts', attempts, 'correct', correct_count,
    'status', case
      when attempts >= 3 and correct_count::numeric / greatest(attempts, 1) >= 0.85 then 'MASTERED'
      when correct_count::numeric / greatest(attempts, 1) >= 0.6 then 'STRONG'
      when correct_count > 0 then 'LEARNING'
      else 'WEAK'
    end
  )), '{}'::jsonb)
  into v_vocabulary
  from (
    select e.event_data ->> 'entityId' as entity_id,
      count(*) as attempts,
      count(*) filter (where e.event_data ->> 'correct' = 'true') as correct_count
    from public.learning_answer_events e
    where e.user_id = p_user_id
      and coalesce(e.event_data ->> 'entityId', '') <> ''
      and coalesce(e.event_data ->> 'entityType', 'vocabulary') <> 'grammar'
    group by e.event_data ->> 'entityId'
  ) vocabulary;

  select coalesce(jsonb_object_agg(entity_id, jsonb_build_object(
    'attempts', attempts, 'correct', correct_count, 'completed', true
  )), '{}'::jsonb)
  into v_grammar
  from (
    select e.event_data ->> 'entityId' as entity_id,
      count(*) as attempts,
      count(*) filter (where e.event_data ->> 'correct' = 'true') as correct_count
    from public.learning_answer_events e
    where e.user_id = p_user_id
      and coalesce(e.event_data ->> 'entityId', '') <> ''
      and e.event_data ->> 'entityType' = 'grammar'
    group by e.event_data ->> 'entityId'
  ) grammar;

  select coalesce(jsonb_object_agg(entity_id, jsonb_build_object(
    'count', wrong_count, 'topic', topic
  )), '{}'::jsonb)
  into v_mistakes
  from (
    select e.event_data ->> 'entityId' as entity_id,
      count(*) as wrong_count,
      coalesce((array_agg(e.event_data ->> 'topic')
        filter (where coalesce(e.event_data ->> 'topic', '') <> ''))[1], '') as topic
    from public.learning_answer_events e
    where e.user_id = p_user_id
      and coalesce(e.event_data ->> 'entityId', '') <> ''
      and e.event_data ->> 'correct' is distinct from 'true'
    group by e.event_data ->> 'entityId'
  ) mistakes;

  select count(*),
    coalesce(sum(case when (session.value ->> 'total') ~ '^[0-9]+$'
      then greatest((session.value ->> 'total')::bigint, 0) else 0 end), 0),
    coalesce(sum(least(
      case when (session.value ->> 'correct') ~ '^[0-9]+$'
        then greatest((session.value ->> 'correct')::bigint, 0) else 0 end,
      case when (session.value ->> 'total') ~ '^[0-9]+$'
        then greatest((session.value ->> 'total')::bigint, 0) else 0 end
    )), 0)
  into v_session_count, v_total_questions, v_correct_answers
  from jsonb_array_elements(
    case when jsonb_typeof(v_flutter -> 'sessions') = 'array'
      then v_flutter -> 'sessions' else '[]'::jsonb end
  ) session(value)
  where jsonb_typeof(session.value) = 'object';

  begin
    v_best_streak := greatest(coalesce((v_flutter #>> '{summary,bestStreak}')::bigint, 0), 0);
    v_current_streak := greatest(coalesce((v_flutter #>> '{summary,currentStreak}')::bigint, 0), 0);
  exception when others then
    v_best_streak := 0;
    v_current_streak := 0;
  end;

  v_summary := coalesce(v_flutter -> 'summary', '{}'::jsonb) || jsonb_build_object(
    'totalSessions', v_session_count,
    'totalQuestions', v_total_questions,
    'correctAnswers', v_correct_answers,
    'accuracyPercent', case when v_total_questions = 0 then 0 else round(100.0 * v_correct_answers / v_total_questions) end,
    'eventsTotal', v_event_count,
    'bestStreak', v_best_streak,
    'currentStreak', v_current_streak
  );

  v_flutter := jsonb_set(v_flutter, '{vocabularyMastery}', coalesce(v_vocabulary, '{}'::jsonb), true);
  v_flutter := jsonb_set(v_flutter, '{grammarCompletion}', coalesce(v_grammar, '{}'::jsonb), true);
  v_flutter := jsonb_set(v_flutter, '{mistakes}', coalesce(v_mistakes, '{}'::jsonb), true);
  v_flutter := jsonb_set(v_flutter, '{summary}', v_summary, true);
  v_flutter := v_flutter #- '{answerEvents}';
  v_state := jsonb_set(v_state, '{flutter}', v_flutter, true);
  update public.learning_state set state = v_state where user_id = p_user_id;
end;
$function$;

create or replace function public.sync_learning_state(p_state jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_incoming jsonb;
  v_events jsonb;
  v_state jsonb;
  v_revision bigint;
  v_updated_at timestamptz;
  v_answer_events jsonb;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_state is null or jsonb_typeof(p_state) <> 'object' then
    raise exception 'learning state must be a JSON object' using errcode = '22023';
  end if;
  if octet_length(p_state::text) > 750000 then
    raise exception 'learning state exceeds the 750 KB limit' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = v_user_id and p.role = 'student' and p.approved = true
  ) then
    raise exception 'approved student account required' using errcode = '42501';
  end if;

  v_events := p_state #> '{flutter,answerEvents}';
  if jsonb_typeof(v_events) = 'array' then
    insert into public.learning_answer_events(user_id, event_id, event_data)
    select v_user_id, item.value ->> 'id', item.value
    from jsonb_array_elements(v_events) item(value)
    where jsonb_typeof(item.value) = 'object'
      and coalesce(item.value ->> 'id', '') <> ''
      and length(item.value ->> 'id') <= 160
    on conflict (user_id, event_id) do nothing;
  end if;

  -- The append-only answer ledger is separate from the compact state document.
  v_incoming := p_state #- '{flutter,answerEvents}';
  if jsonb_typeof(v_incoming -> 'flutter') = 'object' then
    v_incoming := jsonb_set(v_incoming, '{flutter}', (v_incoming -> 'flutter') #- '{answerEvents}', true);
  end if;

  insert into public.learning_state as current_state(user_id, state, revision, updated_at)
  values (v_user_id, v_incoming, 1, now())
  on conflict(user_id) do update
    set state = private.merge_learning_state_jsonb(
          current_state.state #- '{flutter,answerEvents}',
          excluded.state #- '{flutter,answerEvents}'
        ),
        revision = current_state.revision + 1,
        updated_at = now()
  returning state, revision, updated_at into v_state, v_revision, v_updated_at;

  perform private.refresh_learning_state_aggregates(v_user_id);
  select state, revision, updated_at into v_state, v_revision, v_updated_at
  from public.learning_state where user_id = v_user_id;

  select coalesce(jsonb_agg(recent.event_data order by recent.sort_timestamp asc, recent.created_at asc), '[]'::jsonb)
  into v_answer_events
  from (
    select e.event_data,
      coalesce(e.event_data ->> 'timestamp', '') as sort_timestamp,
      e.created_at
    from public.learning_answer_events e
    where e.user_id = v_user_id
    order by coalesce(e.event_data ->> 'timestamp', '') desc, e.created_at desc
    limit 500
  ) recent;

  return jsonb_build_object(
    'state', v_state,
    'answer_events', v_answer_events,
    'revision', v_revision,
    'updated_at', v_updated_at
  );
end;
$function$;

create or replace function public.sync_learning_answer_events(p_events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_revision bigint;
  v_updated_at timestamptz;
  v_ids jsonb;
  v_events_total bigint;
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
      or coalesce(item.value ->> 'entityId', '') = ''
      or jsonb_typeof(item.value -> 'correct') <> 'boolean'
  ) then
    raise exception 'each answer event must include a stable ID, entity ID, and boolean result' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = v_user_id and p.role = 'student' and p.approved = true
  ) then
    raise exception 'approved student account required' using errcode = '42501';
  end if;

  insert into public.learning_state(user_id, state, revision, updated_at)
  values (v_user_id, '{"flutter":{}}'::jsonb, 0, now())
  on conflict(user_id) do nothing;

  insert into public.learning_answer_events(user_id, event_id, event_data)
  select v_user_id, item.value ->> 'id', item.value
  from jsonb_array_elements(p_events) item(value)
  on conflict (user_id, event_id) do nothing;

  perform private.refresh_learning_state_aggregates(v_user_id);

  update public.learning_state
  set revision = revision + 1, updated_at = now()
  where user_id = v_user_id
  returning revision, updated_at into v_revision, v_updated_at;

  select coalesce(jsonb_agg(item.value ->> 'id'), '[]'::jsonb)
  into v_ids
  from jsonb_array_elements(p_events) item(value);

  select count(*) into v_events_total
  from public.learning_answer_events where user_id = v_user_id;

  return jsonb_build_object(
    'accepted_ids', v_ids,
    'revision', v_revision,
    'updated_at', v_updated_at,
    'eventsTotal', v_events_total
  );
end;
$function$;

revoke all on function private.refresh_learning_state_aggregates(uuid) from public, anon, authenticated;
revoke all on function public.sync_learning_state(jsonb) from public, anon;
grant execute on function public.sync_learning_state(jsonb) to authenticated;
revoke all on function public.sync_learning_answer_events(jsonb) from public, anon;
grant execute on function public.sync_learning_answer_events(jsonb) to authenticated;

commit;