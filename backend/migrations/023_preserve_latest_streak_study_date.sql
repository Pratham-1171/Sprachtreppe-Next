begin;

-- Current streak follows the newest study date; longest streak remains a high-water mark.
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
        if existing_study_date is not null
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

revoke all on function private.merge_learning_state_jsonb(jsonb, jsonb, text[]) from public, anon, authenticated;

commit;