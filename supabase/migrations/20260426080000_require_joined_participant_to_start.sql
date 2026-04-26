create or replace function public.start_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    starts_at timestamptz := now();
    session_record public.focus_sessions%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to start a focus session.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
        and owner_id = requester
        and status = 'lobby'
        and exists (
            select 1
            from public.session_members
            where session_members.session_id = target_session_id
                and session_members.user_id = requester
                and session_members.role = 'host'
                and session_members.status = 'joined'
        )
    for update;

    if not found then
        raise exception 'No focus lobby was found.' using errcode = 'P0002';
    end if;

    if session_record.mode = 'multiplayer' and not exists (
        select 1
        from public.session_members
        where session_id = target_session_id
            and role <> 'host'
            and status = 'joined'
    ) then
        raise exception 'At least one invited member must join before starting.' using errcode = '22023';
    end if;

    update public.focus_sessions
    set status = 'live',
        started_at = starts_at,
        planned_end_at = starts_at + make_interval(secs => duration_seconds)
    where id = target_session_id
        and status = 'lobby';

    delete from public.session_members
    where session_id = target_session_id
        and status = 'invited';

    insert into public.session_events (session_id, user_id, event_type)
    values (target_session_id, requester, 'session_started');

    return public.focus_session_payload(target_session_id);
end;
$$;

revoke all on function public.start_focus_session(uuid) from public, anon, authenticated;
grant execute on function public.start_focus_session(uuid) to authenticated;

notify pgrst, 'reload schema';
