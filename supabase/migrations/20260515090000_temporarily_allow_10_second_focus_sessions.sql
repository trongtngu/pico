-- Temporary testing override: allow focus sessions as short as 10 seconds.
-- Remove this migration and restore the 600-second checks after testing.

alter table public.focus_sessions
drop constraint if exists focus_sessions_duration_seconds;

alter table public.focus_sessions
add constraint focus_sessions_duration_seconds
    check (duration_seconds between 10 and 86400);

create or replace function public.create_focus_session(
    session_mode text default 'solo',
    duration_seconds integer default 1800,
    island_id text default 'default'
)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    new_session_id uuid;
    normalized_island_id text := coalesce(nullif(lower(btrim(island_id)), ''), 'default');
    normalized_mode text := lower(btrim(session_mode));
begin
    if requester is null then
        raise exception 'You must be signed in to create a focus session.' using errcode = '28000';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(requester::text, 0));
    perform public.sync_open_focus_sessions();

    if normalized_mode is null or normalized_mode not in ('solo', 'multiplayer') then
        raise exception 'Focus session mode must be solo or multiplayer.' using errcode = '22023';
    end if;

    if duration_seconds is null or duration_seconds < 10 or duration_seconds > 86400 then
        raise exception 'Focus session duration must be between 10 seconds and 24 hours.' using errcode = '22023';
    end if;

    if not exists (
        select 1
        from public.islands
        where islands.id = normalized_island_id
            and islands.is_enabled
    ) then
        raise exception 'Island % is not enabled or does not exist.', normalized_island_id using errcode = '22023';
    end if;

    if not public.user_owns_island(requester, normalized_island_id) then
        raise exception 'You do not own that island.' using errcode = '42501';
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
                or focus_sessions.status = 'active'
            )
    ) then
        raise exception 'You already have an open focus session.' using errcode = '23505';
    end if;

    insert into public.focus_sessions (owner_id, mode, duration_seconds)
    values (requester, normalized_mode, duration_seconds)
    returning id into new_session_id;

    insert into public.session_members (session_id, user_id, island_id, role, status)
    values (new_session_id, requester, normalized_island_id, 'host', 'joined');

    insert into public.session_events (session_id, user_id, event_type)
    values (new_session_id, requester, 'member_joined');

    return public.focus_session_payload(new_session_id);
end;
$$;

create or replace function public.update_focus_session_config(target_session_id uuid, duration_seconds integer)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
begin
    if requester is null then
        raise exception 'You must be signed in to update a focus session.' using errcode = '28000';
    end if;

    if duration_seconds is null or duration_seconds < 10 or duration_seconds > 86400 then
        raise exception 'Focus session duration must be between 10 seconds and 24 hours.' using errcode = '22023';
    end if;

    update public.focus_sessions
    set duration_seconds = update_focus_session_config.duration_seconds
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
        );

    if not found then
        raise exception 'No configurable focus lobby was found.' using errcode = 'P0002';
    end if;

    return public.focus_session_payload(target_session_id);
end;
$$;
