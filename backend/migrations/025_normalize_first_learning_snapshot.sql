begin;

-- Normalize incoming first-sync snapshots before inserting the first server row.
-- Existing rows are already merged using the same stable-ID rule in migration 024.
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

  -- The first snapshot has no existing row to merge against. Normalize it
  -- against itself so duplicate stable IDs from old/offline clients are
  -- reconciled before the server derives session and streak aggregates.
  v_incoming := private.merge_learning_state_jsonb(v_incoming, v_incoming);

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

revoke all on function public.sync_learning_state(jsonb) from public, anon;
grant execute on function public.sync_learning_state(jsonb) to authenticated;

commit;
