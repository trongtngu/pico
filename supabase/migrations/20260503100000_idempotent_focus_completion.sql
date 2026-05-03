create or replace function public.complete_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    finished_at timestamptz := now();
    completion_recorded_at timestamptz;
    session_record public.focus_sessions%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to complete a focus session.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
    for update;

    if not found then
        raise exception 'No live focus session was found.' using errcode = 'P0002';
    end if;

    if exists (
        select 1
        from public.session_events
        where session_events.session_id = target_session_id
            and session_events.user_id = requester
            and session_events.event_type = 'member_completed'
    ) then
        return public.focus_session_payload(target_session_id);
    end if;

    if not (
        session_record.status in ('live', 'completed')
        or (session_record.mode = 'multiplayer' and session_record.status = 'launched')
    ) then
        raise exception 'No live focus session was found.' using errcode = 'P0002';
    end if;

    if not exists (
        select 1
        from public.session_members
        where session_id = target_session_id
            and user_id = requester
            and status = 'joined'
    ) then
        raise exception 'No joined focus session membership was found.' using errcode = 'P0002';
    end if;

    if session_record.mode = 'multiplayer' and exists (
        select 1
        from public.session_events
        where session_events.session_id = target_session_id
            and session_events.user_id = requester
            and session_events.event_type = 'member_interrupted'
    ) then
        return public.focus_session_payload(target_session_id);
    end if;

    insert into public.session_events (session_id, user_id, event_type)
    values (target_session_id, requester, 'member_completed')
    on conflict do nothing
    returning occurred_at into completion_recorded_at;

    if completion_recorded_at is not null then
        perform public.record_user_completion_streak(
            requester,
            completion_recorded_at
        );

        perform public.create_focus_session_fish_catches(
            requester,
            target_session_id,
            completion_recorded_at
        );

        perform public.award_villager_completion_pairs(
            target_session_id,
            requester,
            completion_recorded_at
        );
    end if;

    if session_record.status = 'live' and session_record.mode = 'solo' then
        update public.focus_sessions
        set status = 'completed',
            ended_at = greatest(finished_at, planned_end_at)
        where id = target_session_id;
    end if;

    return public.focus_session_payload(target_session_id);
end;
$$;

grant execute on function public.complete_focus_session(uuid) to authenticated;

notify pgrst, 'reload schema';
