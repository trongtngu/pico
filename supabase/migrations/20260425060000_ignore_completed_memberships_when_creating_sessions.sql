create or replace function public.create_focus_session(
    session_mode text default 'solo',
    duration_seconds integer default 1800
)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    new_session_id uuid;
    normalized_mode text := lower(btrim(session_mode));
begin
    if requester is null then
        raise exception 'You must be signed in to create a focus session.' using errcode = '28000';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(requester::text, 0));

    if normalized_mode not in ('solo', 'multiplayer') then
        raise exception 'Focus session mode must be solo or multiplayer.' using errcode = '22023';
    end if;

    if duration_seconds is null or duration_seconds < 60 or duration_seconds > 86400 then
        raise exception 'Focus session duration must be between 60 seconds and 24 hours.' using errcode = '22023';
    end if;

    if exists (
        select 1
        from public.session_members
        join public.focus_sessions
            on focus_sessions.id = session_members.session_id
        where session_members.user_id = requester
            and session_members.status = 'joined'
            and (
                focus_sessions.status = 'lobby'
                or (
                    focus_sessions.status = 'live'
                    and (
                        focus_sessions.mode = 'solo'
                        or not exists (
                            select 1
                            from public.session_events
                            where session_events.session_id = focus_sessions.id
                                and session_events.user_id = requester
                                and session_events.event_type = 'member_completed'
                        )
                    )
                )
            )
    ) then
        raise exception 'You already have an open focus session.' using errcode = '23505';
    end if;

    insert into public.focus_sessions (
        owner_id,
        mode,
        duration_seconds
    )
    values (
        requester,
        normalized_mode,
        duration_seconds
    )
    returning id into new_session_id;

    insert into public.session_members (
        session_id,
        user_id,
        role,
        status
    )
    values (
        new_session_id,
        requester,
        'host',
        'joined'
    );

    insert into public.session_events (session_id, user_id, event_type)
    values (new_session_id, requester, 'member_joined');

    return public.focus_session_payload(new_session_id);
end;
$$;

revoke all on function public.create_focus_session(text, integer) from public, anon, authenticated;
grant execute on function public.create_focus_session(text, integer) to authenticated;
