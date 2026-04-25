drop index if exists public.focus_sessions_one_open_owner;

delete from public.session_members
where status = 'declined';

alter table public.session_members
drop constraint if exists session_members_status;

alter table public.session_members
add constraint session_members_status
    check (status in ('invited', 'joined', 'left'));

create or replace function public.is_focus_session_member(target_session_id uuid)
returns boolean
security definer
set search_path = public
language sql
stable
as $$
    select exists (
        select 1
        from public.session_members
        where session_members.session_id = target_session_id
            and session_members.user_id = auth.uid()
            and session_members.status = 'joined'
    );
$$;

create or replace function public.can_read_focus_session_member(target_session_id uuid, target_user_id uuid)
returns boolean
security definer
set search_path = public
language sql
stable
as $$
    select public.is_focus_session_member(target_session_id)
        or target_user_id = auth.uid();
$$;

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
            and focus_sessions.status in ('lobby', 'live')
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

create or replace function public.update_focus_session_config(
    target_session_id uuid,
    duration_seconds integer
)
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

    if duration_seconds is null or duration_seconds < 60 or duration_seconds > 86400 then
        raise exception 'Focus session duration must be between 60 seconds and 24 hours.' using errcode = '22023';
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

create or replace function public.invite_focus_session_members(
    target_session_id uuid,
    invitee_ids uuid[]
)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    invitee uuid;
    session_record public.focus_sessions%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to invite members.' using errcode = '28000';
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

    if session_record.mode <> 'multiplayer' then
        raise exception 'Only multiplayer sessions can invite members.' using errcode = '22023';
    end if;

    foreach invitee in array coalesce(invitee_ids, array[]::uuid[])
    loop
        if invitee = requester then
            raise exception 'You cannot invite yourself.' using errcode = '22023';
        end if;

        if not exists (
            select 1
            from public.friendships
            where (
                friendships.user_one_id = least(requester, invitee)
                and friendships.user_two_id = greatest(requester, invitee)
            )
        ) then
            raise exception 'Only friends can be invited to a focus session.' using errcode = '22023';
        end if;

        insert into public.session_members (
            session_id,
            user_id,
            role,
            status
        )
        values (
            target_session_id,
            invitee,
            'participant',
            'invited'
        )
        on conflict (session_id, user_id) do update
        set status = case
                when session_members.status = 'joined' then session_members.status
                else 'invited'
            end,
            role = 'participant';
    end loop;

    return public.focus_session_payload(target_session_id);
end;
$$;

create or replace function public.decline_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    session_payload jsonb;
begin
    if requester is null then
        raise exception 'You must be signed in to decline a focus session.' using errcode = '28000';
    end if;

    session_payload := public.focus_session_payload(target_session_id);

    delete from public.session_members
    where session_id = target_session_id
        and user_id = requester
        and status = 'invited'
        and exists (
            select 1
            from public.focus_sessions
            where focus_sessions.id = target_session_id
                and focus_sessions.status = 'lobby'
        );

    if not found then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    return session_payload;
end;
$$;

create or replace function public.start_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    starts_at timestamptz := now();
begin
    if requester is null then
        raise exception 'You must be signed in to start a focus session.' using errcode = '28000';
    end if;

    update public.focus_sessions
    set status = 'live',
        started_at = starts_at,
        planned_end_at = starts_at + make_interval(secs => duration_seconds)
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
        raise exception 'No focus lobby was found.' using errcode = 'P0002';
    end if;

    delete from public.session_members
    where session_id = target_session_id
        and status = 'invited';

    insert into public.session_events (session_id, user_id, event_type)
    values (target_session_id, requester, 'session_started');

    return public.focus_session_payload(target_session_id);
end;
$$;

create or replace function public.cancel_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
begin
    if requester is null then
        raise exception 'You must be signed in to cancel a focus session.' using errcode = '28000';
    end if;

    update public.focus_sessions
    set status = 'cancelled',
        ended_at = now()
    where id = target_session_id
        and owner_id = requester
        and status in ('lobby', 'live')
        and exists (
            select 1
            from public.session_members
            where session_members.session_id = target_session_id
                and session_members.user_id = requester
                and session_members.role = 'host'
                and session_members.status = 'joined'
        );

    if not found then
        raise exception 'No cancellable focus session was found.' using errcode = 'P0002';
    end if;

    return public.focus_session_payload(target_session_id);
end;
$$;

create or replace function public.interrupt_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    session_record public.focus_sessions%rowtype;
    session_payload jsonb;
begin
    if requester is null then
        raise exception 'You must be signed in to interrupt a focus session.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
        and status in ('live', 'interrupted')
    for update;

    if not found then
        raise exception 'No live focus session was found.' using errcode = 'P0002';
    end if;

    if session_record.mode = 'solo' and session_record.owner_id <> requester then
        raise exception 'Only the host can interrupt a solo focus session.' using errcode = '42501';
    end if;

    if session_record.status = 'interrupted' then
        return public.focus_session_payload(target_session_id);
    end if;

    if session_record.mode = 'solo' then
        update public.focus_sessions
        set status = 'interrupted',
            ended_at = now()
        where id = target_session_id;

        insert into public.session_events (session_id, user_id, event_type)
        values (target_session_id, requester, 'member_interrupted')
        on conflict do nothing;

        return public.focus_session_payload(target_session_id);
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

    session_payload := public.focus_session_payload(target_session_id);

    insert into public.session_events (session_id, user_id, event_type)
    values (target_session_id, requester, 'member_interrupted')
    on conflict do nothing;

    delete from public.session_members
    where session_id = target_session_id
        and user_id = requester
        and status = 'joined';

    if not exists (
        select 1
        from public.session_members
        where session_id = target_session_id
            and status = 'joined'
    ) then
        delete from public.focus_sessions
        where id = target_session_id;
    end if;

    return session_payload;
end;
$$;
