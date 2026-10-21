-- Preserve streak values recomputed from merged study-session dates.
-- The previous function recalculated current/best streaks, then immediately
-- overwrote them with stale values from the pre-refresh summary.
begin;

CREATE OR REPLACE FUNCTION private.refresh_learning_state_aggregates(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_session jsonb;
  v_session_date_text text;
  v_study_date date;
  v_previous_study_date date;
  v_last_study_date date;
  v_study_dates date[] := array[]::date[];
  v_run_streak bigint := 0;
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
    'attempts', attempts,
    'correct', correct_count,
    'attempted', true,
    'completed', correct_count > 0
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

  -- Preserve the local calendar date inside each stable study-session record.
  -- Older records fall back to their recorded date/completion timestamp.
  for v_session in
    select session.value
    from jsonb_array_elements(
      case when jsonb_typeof(v_flutter -> 'sessions') = 'array'
        then v_flutter -> 'sessions' else '[]'::jsonb end
    ) session(value)
    where jsonb_typeof(session.value) = 'object'
  loop
    v_session_date_text := coalesce(
      nullif(v_session ->> 'studyDate', ''),
      nullif(v_session ->> 'date', ''),
      nullif(left(v_session ->> 'completedAt', 10), '')
    );
    begin
      v_study_date := nullif(v_session_date_text, '')::date;
    exception when others then
      v_study_date := null;
    end;
    if v_study_date is not null and not (v_study_date = any(v_study_dates)) then
      v_study_dates := array_append(v_study_dates, v_study_date);
    end if;
  end loop;

  select max(d) into v_last_study_date
  from unnest(v_study_dates) as days(d)
  where d <= current_date;

  -- Compute consecutive days from the merged, deduplicated history, while
  -- keeping the previously recorded best streak as a high-water mark.
  begin
    v_best_streak := greatest(
      coalesce((v_flutter #>> '{summary,bestStreak}')::bigint, 0), 0
    );
  exception when others then
    v_best_streak := 0;
  end;

  v_run_streak := 0;
  v_previous_study_date := null;
  for v_study_date in
    select distinct d from unnest(v_study_dates) as days(d) order by d
  loop
    if v_previous_study_date is not null
       and v_study_date = v_previous_study_date + 1 then
      v_run_streak := v_run_streak + 1;
    else
      v_run_streak := 1;
    end if;
    v_best_streak := greatest(v_best_streak, v_run_streak);
    v_previous_study_date := v_study_date;
  end loop;

  v_current_streak := 0;
  if v_last_study_date is not null and v_last_study_date >= current_date - 1 then
    v_run_streak := 0;
    v_previous_study_date := null;
    for v_study_date in
      select distinct d from unnest(v_study_dates) as days(d)
      where d <= current_date
      order by d desc
    loop
      if v_run_streak = 0 then
        if v_study_date >= current_date - 1 then
          v_run_streak := 1;
          v_previous_study_date := v_study_date;
        else
          exit;
        end if;
      elsif v_previous_study_date = v_study_date + 1 then
        v_run_streak := v_run_streak + 1;
        v_previous_study_date := v_study_date;
      else
        exit;
      end if;
    end loop;
    v_current_streak := v_run_streak;
  else
    -- Existing course-engine streaks remain useful for accounts with legacy
    -- state but no native session records yet.
    begin
      v_current_streak := greatest(
        coalesce((v_flutter #>> '{summary,currentStreak}')::bigint, 0), 0
      );
    exception when others then
      v_current_streak := 0;
    end;
  end if;

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
$function$

commit;
