begin;

-- Merge stable-ID array records (especially sessions) by identity, not by full
-- JSON equality. Keep the streak high-water mark but allow a stale current
-- streak to reset after two non-study days.
create or replace function private.merge_learning_state_jsonb(
  p_existing jsonb, p_incoming jsonb, p_path text[] default '{}'::text[]
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $function$
declare
  existing_type text;
  incoming_type text;
  merged jsonb;
  old_status text;
  new_status text;
  old_rank integer;
  new_rank integer;
  existing_study_date date;
  incoming_study_date date;
  study_date_key text;
  item jsonb;
  existing_item jsonb;
  item_id text;
  found_id boolean;
  rebuilt jsonb;
begin
  if p_existing is null or jsonb_typeof(p_existing) = 'null' then
    return coalesce(p_incoming, '{}'::jsonb);
  end if;
  if p_incoming is null or jsonb_typeof(p_incoming) = 'null' then
    return p_existing;
  end if;
  existing_type := jsonb_typeof(p_existing);
  incoming_type := jsonb_typeof(p_incoming);

  if existing_type = 'object' and incoming_type = 'object' then
    select coalesce(
      jsonb_object_agg(k, private.merge_learning_state_jsonb(p_existing -> k, p_incoming -> k, p_path || k)),
      '{}'::jsonb
    )
    into merged
    from (
      select jsonb_object_keys(p_existing) as k
      union
      select jsonb_object_keys(p_incoming) as k
    ) keys;

    if coalesce(p_path[array_length(p_path, 1)], '') = 'streak' then
      study_date_key := case
        when p_existing ? 'lastStudyDate' and p_incoming ? 'lastStudyDate' then 'lastStudyDate'
        when p_existing ? 'lastDate' and p_incoming ? 'lastDate' then 'lastDate'
        else null
      end;

      if study_date_key is not null then
        begin
          existing_study_date := nullif(p_existing ->> study_date_key, '')::date;
        exception when others then
          existing_study_date := null;
        end;
        begin
          incoming_study_date := nullif(p_incoming ->> study_date_key, '')::date;
        exception when others then
          incoming_study_date := null;
        end;
      else
        existing_study_date := null;
        incoming_study_date := null;
      end if;

      if study_date_key is not null
         and existing_study_date is not null
         and incoming_study_date is not null
         and existing_study_date <> incoming_study_date then
        merged := jsonb_set(
          merged,
          array[study_date_key],
          case when incoming_study_date > existing_study_date
            then p_incoming -> study_date_key else p_existing -> study_date_key end,
          false
        );
      end if;

      if jsonb_typeof(p_existing -> 'current') = 'number'
         and jsonb_typeof(p_incoming -> 'current') = 'number' then
        if greatest(coalesce(existing_study_date, incoming_study_date),
                    coalesce(incoming_study_date, existing_study_date)) < current_date - 1 then
          -- A long gap resets today's current streak even if both devices last
          -- saved the same old study date and one contains a stale non-zero value.
          merged := jsonb_set(merged, '{current}', '0'::jsonb, false);
        elsif existing_study_date is not null
           and incoming_study_date is not null
           and existing_study_date <> incoming_study_date then
          if incoming_study_date > existing_study_date then
            merged := jsonb_set(merged, '{current}', p_incoming -> 'current', false);
          else
            merged := jsonb_set(merged, '{current}', p_existing -> 'current', false);
          end if;
        else
          merged := jsonb_set(
            merged, '{current}',
            to_jsonb(greatest((p_existing ->> 'current')::numeric, (p_incoming ->> 'current')::numeric)),
            false
          );
        end if;
      end if;

      if jsonb_typeof(p_existing -> 'longest') = 'number'
         and jsonb_typeof(p_incoming -> 'longest') = 'number' then
        merged := jsonb_set(
          merged, '{longest}',
          to_jsonb(greatest((p_existing ->> 'longest')::numeric, (p_incoming ->> 'longest')::numeric)),
          false
        );
      end if;
    end if;
    return merged;
  end if;

  if existing_type = 'array' and incoming_type = 'array' then
    -- Stable-ID records (notably study sessions) represent one logical item
    -- even when two offline devices have different snapshots of that record.
    merged := '[]'::jsonb;
    for item in
      select value from jsonb_array_elements(p_existing || p_incoming) as rows(value)
    loop
      item_id := case
        when jsonb_typeof(item) = 'object' then nullif(btrim(item ->> 'id'), '')
        else null
      end;
      if item_id is null then
        if not (merged @> jsonb_build_array(item)) then
          merged := merged || jsonb_build_array(item);
        end if;
        continue;
      end if;

      found_id := false;
      rebuilt := '[]'::jsonb;
      for existing_item in select value from jsonb_array_elements(merged) as rows(value)
      loop
        if jsonb_typeof(existing_item) = 'object'
           and nullif(btrim(existing_item ->> 'id'), '') = item_id then
          rebuilt := rebuilt || jsonb_build_array(
            private.merge_learning_state_jsonb(existing_item, item, p_path)
          );
          found_id := true;
        else
          rebuilt := rebuilt || jsonb_build_array(existing_item);
        end if;
      end loop;
      if found_id then
        merged := rebuilt;
      else
        merged := merged || jsonb_build_array(item);
      end if;
    end loop;
    return merged;
  end if;

  if existing_type = 'number' and incoming_type = 'number' then
    return to_jsonb(greatest((p_existing #>> '{}')::numeric, (p_incoming #>> '{}')::numeric));
  end if;
  if existing_type = 'boolean' and incoming_type = 'boolean' then
    return to_jsonb((p_existing #>> '{}')::boolean or (p_incoming #>> '{}')::boolean);
  end if;

  if coalesce(p_path[array_length(p_path, 1)], '') = 'status'
     and existing_type = 'string' and incoming_type = 'string' then
    old_status := upper(p_existing #>> '{}');
    new_status := upper(p_incoming #>> '{}');
    old_rank := case old_status
      when 'MASTERED' then 6 when 'STRONG' then 5 when 'LEARNED' then 5
      when 'FAMILIAR' then 4 when 'LEARNING' then 3 when 'WEAK' then 2
      when 'NEW' then 1 when 'UNKNOWN' then 0 else 0 end;
    new_rank := case new_status
      when 'MASTERED' then 6 when 'STRONG' then 5 when 'LEARNED' then 5
      when 'FAMILIAR' then 4 when 'LEARNING' then 3 when 'WEAK' then 2
      when 'NEW' then 1 when 'UNKNOWN' then 0 else 0 end;
    if new_rank > old_rank then return p_incoming; end if;
    if old_rank > new_rank then return p_existing; end if;
    return p_incoming;
  end if;

  return p_incoming;
end;
$function$;

-- Rebuild event-derived mastery/mistakes and study statistics from canonical
-- events plus the unique merged session history.
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

-- Normalise any existing snapshots, then recompute their denormalised counters.
-- This is idempotent; it does not delete answer events or student state.
update public.learning_state
set state = private.merge_learning_state_jsonb(state, state),
    updated_at = now();

do $block$
declare
  v_user_id uuid;
begin
  for v_user_id in select user_id from public.learning_state loop
    perform private.refresh_learning_state_aggregates(v_user_id);
  end loop;
end;
$block$;

revoke all on function private.merge_learning_state_jsonb(jsonb, jsonb, text[]) from public, anon, authenticated;
revoke all on function private.refresh_learning_state_aggregates(uuid) from public, anon, authenticated;

commit;
