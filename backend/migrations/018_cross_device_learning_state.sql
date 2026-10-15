begin;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists public.learning_state (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  state jsonb not null default '{}'::jsonb check (jsonb_typeof(state) = 'object'),
  revision bigint not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.learning_state enable row level security;
drop policy if exists learning_state_select_own on public.learning_state;
create policy learning_state_select_own on public.learning_state
  for select to authenticated using ((select auth.uid()) = user_id);
revoke all on public.learning_state from public, anon, authenticated;
grant select on public.learning_state to authenticated;

create or replace function private.merge_learning_state_jsonb(
  p_existing jsonb, p_incoming jsonb, p_path text[] default '{}'::text[]
)
returns jsonb language plpgsql immutable set search_path = '' as $function$
declare
  existing_type text;
  incoming_type text;
  merged jsonb;
  old_status text;
  new_status text;
  old_rank integer;
  new_rank integer;
begin
  if p_existing is null or jsonb_typeof(p_existing) = 'null' then
    return coalesce(p_incoming, '{}'::jsonb);
  end if;
  if p_incoming is null or jsonb_typeof(p_incoming) = 'null' then return p_existing; end if;
  existing_type := jsonb_typeof(p_existing);
  incoming_type := jsonb_typeof(p_incoming);

  if existing_type = 'object' and incoming_type = 'object' then
    select coalesce(jsonb_object_agg(k, private.merge_learning_state_jsonb(p_existing -> k, p_incoming -> k, p_path || k)), '{}'::jsonb)
    into merged
    from (
      select jsonb_object_keys(p_existing) as k
      union
      select jsonb_object_keys(p_incoming) as k
    ) keys;
    return merged;
  end if;

  if existing_type = 'array' and incoming_type = 'array' then
    select coalesce(jsonb_agg(value order by value::text), '[]'::jsonb)
    into merged
    from (
      select value from jsonb_array_elements(p_existing) as a(value)
      union
      select value from jsonb_array_elements(p_incoming) as b(value)
    ) items;
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

create or replace function public.sync_learning_state(p_state jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  v_user_id uuid := auth.uid();
  v_state jsonb;
  v_revision bigint;
  v_updated_at timestamptz;
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

  return jsonb_build_object('state', v_state, 'revision', v_revision, 'updated_at', v_updated_at);
end;
$function$;

revoke all on function private.merge_learning_state_jsonb(jsonb, jsonb, text[]) from public, anon, authenticated;
revoke all on function public.sync_learning_state(jsonb) from public, anon;
grant execute on function public.sync_learning_state(jsonb) to authenticated;
commit;