begin;

create or replace function public.sync_learning_state(p_state jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_state jsonb;
  v_flutter jsonb;
  v_summary jsonb;
  v_vocabulary jsonb;
  v_grammar jsonb;
  v_mistakes jsonb;
  v_revision bigint;
  v_updated_at timestamptz;
  v_session_count bigint := 0;
  v_total_questions bigint := 0;
  v_correct_answers bigint := 0;
  v_event_count bigint := 0;
  v_best_streak bigint := 0;
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

  insert into public.learning_state as current_state (user_id, state, revision, updated_at)
  values (v_user_id, p_state, 1, now())
  on conflict (user_id) do update
    set state = private.merge_learning_state_jsonb(current_state.state, excluded.state),
        revision = current_state.revision + 1,
        updated_at = now()
  returning state, revision, updated_at into v_state, v_revision, v_updated_at;

  -- Materialize counters from the full server-merged event set, not a device's
  -- last-synced snapshot. Unique event IDs prevent retries and offline merges
  -- from double-counting answers when devices reconnect concurrently.
  if jsonb_typeof(v_state -> 'flutter') = 'object' then
    v_flutter := v_state -> 'flutter';

    select count(*) into v_event_count
    from jsonb_array_elements(
      case when jsonb_typeof(v_flutter -> 'answerEvents') = 'array'
        then v_flutter -> 'answerEvents' else '[]'::jsonb end
    ) event(value)
    where jsonb_typeof(event.value) = 'object'
      and coalesce(event.value ->> 'id', '') <> '';

    select coalesce(jsonb_object_agg(entity_id, jsonb_build_object(
      'attempts', attempts,
      'correct', correct_count,
      'status', case
        when attempts >= 3 and correct_count::numeric / greatest(attempts, 1) >= 0.85 then 'MASTERED'
        when correct_count::numeric / greatest(attempts, 1) >= 0.6 then 'STRONG'
        when correct_count > 0 then 'LEARNING'
        else 'WEAK'
      end
    )), '{}'::jsonb)
    into v_vocabulary
    from (
      select event.value ->> 'entityId' as entity_id,
        count(distinct event.value ->> 'id') as attempts,
        count(distinct event.value ->> 'id') filter (where event.value ->> 'correct' = 'true') as correct_count
      from jsonb_array_elements(
        case when jsonb_typeof(v_flutter -> 'answerEvents') = 'array'
          then v_flutter -> 'answerEvents' else '[]'::jsonb end
      ) event(value)
      where jsonb_typeof(event.value) = 'object'
        and coalesce(event.value ->> 'id', '') <> ''
        and coalesce(event.value ->> 'entityId', '') <> ''
        and coalesce(event.value ->> 'entityType', 'vocabulary') <> 'grammar'
      group by event.value ->> 'entityId'
    ) aggregated_vocab;

    select coalesce(jsonb_object_agg(entity_id, jsonb_build_object(
      'attempts', attempts,
      'correct', correct_count,
      'completed', true
    )), '{}'::jsonb)
    into v_grammar
    from (
      select event.value ->> 'entityId' as entity_id,
        count(distinct event.value ->> 'id') as attempts,
        count(distinct event.value ->> 'id') filter (where event.value ->> 'correct' = 'true') as correct_count
      from jsonb_array_elements(
        case when jsonb_typeof(v_flutter -> 'answerEvents') = 'array'
          then v_flutter -> 'answerEvents' else '[]'::jsonb end
      ) event(value)
      where jsonb_typeof(event.value) = 'object'
        and coalesce(event.value ->> 'id', '') <> ''
        and coalesce(event.value ->> 'entityId', '') <> ''
        and event.value ->> 'entityType' = 'grammar'
      group by event.value ->> 'entityId'
    ) aggregated_grammar;

    select coalesce(jsonb_object_agg(entity_id, jsonb_build_object(
      'count', wrong_count,
      'topic', topic
    )), '{}'::jsonb)
    into v_mistakes
    from (
      select event.value ->> 'entityId' as entity_id,
        count(distinct event.value ->> 'id') as wrong_count,
        coalesce((array_agg(event.value ->> 'topic') filter (where coalesce(event.value ->> 'topic', '') <> ''))[1], '') as topic
      from jsonb_array_elements(
        case when jsonb_typeof(v_flutter -> 'answerEvents') = 'array'
          then v_flutter -> 'answerEvents' else '[]'::jsonb end
      ) event(value)
      where jsonb_typeof(event.value) = 'object'
        and coalesce(event.value ->> 'id', '') <> ''
        and coalesce(event.value ->> 'entityId', '') <> ''
        and event.value ->> 'correct' is distinct from 'true'
      group by event.value ->> 'entityId'
    ) aggregated_mistakes;

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
    exception when others then
      v_best_streak := 0;
    end;

    v_summary := coalesce(v_flutter -> 'summary', '{}'::jsonb) || jsonb_build_object(
      'totalSessions', v_session_count,
      'totalQuestions', v_total_questions,
      'correctAnswers', v_correct_answers,
      'accuracyPercent', case when v_total_questions = 0 then 0 else round(100.0 * v_correct_answers / v_total_questions) end,
      'eventsTotal', v_event_count,
      'bestStreak', v_best_streak
    );
    v_flutter := jsonb_set(v_flutter, '{vocabularyMastery}', coalesce(v_vocabulary, '{}'::jsonb), true);
    v_flutter := jsonb_set(v_flutter, '{grammarCompletion}', coalesce(v_grammar, '{}'::jsonb), true);
    v_flutter := jsonb_set(v_flutter, '{mistakes}', coalesce(v_mistakes, '{}'::jsonb), true);
    v_flutter := jsonb_set(v_flutter, '{summary}', v_summary, true);
    v_state := jsonb_set(v_state, '{flutter}', v_flutter, true);
    update public.learning_state set state = v_state where user_id = v_user_id;
  end if;

  return jsonb_build_object('state', v_state, 'revision', v_revision, 'updated_at', v_updated_at);
end;
$function$;

revoke all on function public.sync_learning_state(jsonb) from public, anon;
grant execute on function public.sync_learning_state(jsonb) to authenticated;

commit;