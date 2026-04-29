alter table public.focus_sessions
drop constraint if exists focus_sessions_status;

alter table public.focus_sessions
add constraint focus_sessions_status
    check (status in ('lobby', 'launched', 'live', 'interrupted', 'completed', 'cancelled'));

alter table public.focus_sessions
drop constraint if exists focus_sessions_lifecycle_timestamps;

alter table public.focus_sessions
add constraint focus_sessions_lifecycle_timestamps
    check (
        (status = 'lobby' and started_at is null and planned_end_at is null and ended_at is null)
        or (status in ('launched', 'live') and started_at is not null and planned_end_at is not null and ended_at is null)
        or (status in ('completed', 'interrupted') and started_at is not null and planned_end_at is not null and ended_at is not null)
        or (status = 'cancelled' and ended_at is not null)
    );

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
    perform public.reconcile_open_focus_sessions();

    if normalized_mode is null or normalized_mode not in ('solo', 'multiplayer') then
        raise exception 'Focus session mode must be solo or multiplayer.' using errcode = '22023';
    end if;

    if duration_seconds is null or duration_seconds < 600 or duration_seconds > 86400 then
        raise exception 'Focus session duration must be between 10 minutes and 24 hours.' using errcode = '22023';
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
                    focus_sessions.mode = 'solo'
                    and focus_sessions.status = 'live'
                )
                or (
                    focus_sessions.mode = 'multiplayer'
                    and focus_sessions.status = 'launched'
                    and focus_sessions.planned_end_at > now()
                    and not exists (
                        select 1
                        from public.session_events
                        where session_events.session_id = focus_sessions.id
                            and session_events.user_id = requester
                            and session_events.event_type in ('member_completed', 'member_interrupted')
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
    for update;

    if not found then
        raise exception 'No focus lobby was found.' using errcode = 'P0002';
    end if;

    if session_record.status <> 'lobby' then
        return public.focus_session_payload(target_session_id);
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

create or replace function public.join_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    session_record public.focus_sessions%rowtype;
    membership_record public.session_members%rowtype;
    joined_now boolean := false;
begin
    if requester is null then
        raise exception 'You must be signed in to join a focus session.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
    for update;

    if not found then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    select *
    into membership_record
    from public.session_members
    where session_id = target_session_id
        and user_id = requester
        and status in ('invited', 'joined', 'left')
    for update;

    if not found then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    if session_record.status = 'cancelled' then
        update public.session_members
        set status = 'left'
        where session_id = target_session_id
            and user_id = requester
            and status in ('invited', 'joined');

        return public.focus_session_payload(target_session_id);
    end if;

    if session_record.status <> 'lobby' then
        return public.focus_session_payload(target_session_id);
    end if;

    if membership_record.status = 'invited' then
        update public.session_members
        set status = 'joined'
        where session_id = target_session_id
            and user_id = requester
            and status = 'invited';

        joined_now := found;
    end if;

    if membership_record.status <> 'joined' and not joined_now then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    if joined_now then
        insert into public.session_events (session_id, user_id, event_type)
        values (target_session_id, requester, 'member_joined');
    end if;

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
    session_record public.focus_sessions%rowtype;
    has_membership boolean := false;
begin
    if requester is null then
        raise exception 'You must be signed in to decline a focus session.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id;

    if not found then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    select exists (
        select 1
        from public.session_members
        where session_id = target_session_id
            and user_id = requester
            and status in ('invited', 'joined', 'left')
    )
    into has_membership;

    if not has_membership then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    if session_record.status <> 'lobby' then
        return public.focus_session_payload(target_session_id);
    end if;

    delete from public.session_members
    where session_id = target_session_id
        and user_id = requester
        and status = 'invited';

    if not found then
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
    end if;

    return public.focus_session_payload(target_session_id);
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
    next_status text;
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

    if session_record.status in ('launched', 'live') then
        return public.focus_session_payload(target_session_id);
    end if;

    if session_record.status <> 'lobby' then
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

    next_status := case
        when session_record.mode = 'multiplayer' then 'launched'
        else 'live'
    end;

    update public.focus_sessions
    set status = next_status,
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
        and (
            status in ('live', 'completed')
            or (mode = 'multiplayer' and status = 'launched')
        )
    for update;

    if not found then
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
        perform public.award_user_score_for_completion(
            requester,
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

create or replace function public.cancel_session_lobby(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    session_record public.focus_sessions%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to cancel a focus lobby.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
        and owner_id = requester
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
        raise exception 'No cancellable focus lobby was found.' using errcode = 'P0002';
    end if;

    if session_record.status <> 'lobby' then
        return public.focus_session_payload(target_session_id);
    end if;

    update public.focus_sessions
    set status = 'cancelled',
        ended_at = now()
    where id = target_session_id
        and status = 'lobby';

    update public.session_members
    set status = 'left'
    where session_id = target_session_id;

    return public.focus_session_payload(target_session_id);
end;
$$;

create or replace function public.leave_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    session_record public.focus_sessions%rowtype;
    membership_record public.session_members%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to leave a focus session.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
    for update;

    if not found then
        raise exception 'No open focus session was found.' using errcode = 'P0002';
    end if;

    if session_record.mode <> 'multiplayer' then
        raise exception 'Only multiplayer sessions can be left.' using errcode = '22023';
    end if;

    select *
    into membership_record
    from public.session_members
    where session_id = target_session_id
        and user_id = requester
        and status = 'joined'
    for update;

    if not found then
        raise exception 'No joined focus session membership was found.' using errcode = 'P0002';
    end if;

    if session_record.status <> 'lobby' then
        return public.focus_session_payload(target_session_id);
    end if;

    if membership_record.role = 'host' or session_record.owner_id = requester then
        raise exception 'The host must cancel the focus session instead.' using errcode = '42501';
    end if;

    delete from public.session_members
    where session_id = target_session_id
        and user_id = requester
        and status = 'joined';

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
begin
    if requester is null then
        raise exception 'You must be signed in to interrupt a focus session.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
        and (
            status in ('live', 'interrupted')
            or (mode = 'multiplayer' and status = 'launched')
        )
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
    else
        if not exists (
            select 1
            from public.session_members
            where session_id = target_session_id
                and user_id = requester
                and status = 'joined'
        ) then
            raise exception 'No joined focus session membership was found.' using errcode = 'P0002';
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
    end if;

    insert into public.session_events (session_id, user_id, event_type)
    values (target_session_id, requester, 'member_interrupted')
    on conflict do nothing;

    return public.focus_session_payload(target_session_id);
end;
$$;

create or replace function public.fetch_current_focus_session_detail()
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    current_session_id uuid;
begin
    if requester is null then
        raise exception 'You must be signed in to view a focus session.' using errcode = '28000';
    end if;

    perform public.reconcile_open_focus_sessions();

    select focus_sessions.id
    into current_session_id
    from public.session_members
    join public.focus_sessions
        on focus_sessions.id = session_members.session_id
    where session_members.user_id = requester
        and session_members.status = 'joined'
        and (
            focus_sessions.status = 'lobby'
            or (
                focus_sessions.mode = 'solo'
                and focus_sessions.status = 'live'
            )
            or (
                focus_sessions.mode = 'multiplayer'
                and focus_sessions.status = 'launched'
                and focus_sessions.planned_end_at > now()
                and not exists (
                    select 1
                    from public.session_events
                    where session_events.session_id = focus_sessions.id
                        and session_events.user_id = requester
                        and session_events.event_type in ('member_completed', 'member_interrupted')
                )
            )
        )
    order by
        case
            when focus_sessions.status in ('live', 'launched') then 0
            else 1
        end,
        focus_sessions.updated_at desc
    limit 1;

    if current_session_id is null then
        return null;
    end if;

    return public.focus_session_detail_payload(current_session_id);
end;
$$;

create or replace function public.reconcile_open_focus_sessions()
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    reconciled_at timestamptz := now();
    stale_lobby_after interval := interval '24 hours';
    session_record record;
    completion_recorded_at timestamptz;
    completed_count integer := 0;
    cancelled_lobby_count integer := 0;
    left_lobby_count integer := 0;
    repaired_cancelled_count integer := 0;
begin
    if requester is null then
        raise exception 'You must be signed in to reconcile focus sessions.' using errcode = '28000';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(requester::text, 0));

    update public.session_members
    set status = 'left'
    from public.focus_sessions
    where session_members.session_id = focus_sessions.id
        and session_members.user_id = requester
        and session_members.status in ('invited', 'joined')
        and focus_sessions.status = 'cancelled';

    get diagnostics repaired_cancelled_count = row_count;
    cancelled_lobby_count := cancelled_lobby_count + repaired_cancelled_count;

    for session_record in
        select
            focus_sessions.*,
            session_members.role as member_role
        from public.focus_sessions
        join public.session_members
            on session_members.session_id = focus_sessions.id
        where session_members.user_id = requester
            and session_members.status = 'joined'
            and focus_sessions.status = 'lobby'
            and focus_sessions.updated_at <= reconciled_at - stale_lobby_after
        for update of focus_sessions
    loop
        if session_record.owner_id = requester or session_record.member_role = 'host' then
            update public.focus_sessions
            set status = 'cancelled',
                ended_at = reconciled_at
            where id = session_record.id
                and status = 'lobby';

            update public.session_members
            set status = 'left'
            where session_id = session_record.id
                and status in ('invited', 'joined');

            cancelled_lobby_count := cancelled_lobby_count + 1;
        else
            update public.session_members
            set status = 'left'
            where session_id = session_record.id
                and user_id = requester
                and status = 'joined';

            left_lobby_count := left_lobby_count + 1;
        end if;
    end loop;

    for session_record in
        select focus_sessions.*
        from public.focus_sessions
        join public.session_members
            on session_members.session_id = focus_sessions.id
        where session_members.user_id = requester
            and session_members.status = 'joined'
            and focus_sessions.planned_end_at <= reconciled_at
            and (
                (
                    focus_sessions.mode = 'solo'
                    and focus_sessions.status = 'live'
                )
                or (
                    focus_sessions.mode = 'multiplayer'
                    and focus_sessions.status = 'launched'
                )
            )
            and not exists (
                select 1
                from public.session_events
                where session_events.session_id = focus_sessions.id
                    and session_events.user_id = requester
                    and session_events.event_type in ('member_completed', 'member_interrupted')
            )
        for update of focus_sessions
    loop
        completion_recorded_at := null;

        insert into public.session_events (session_id, user_id, event_type)
        values (session_record.id, requester, 'member_completed')
        on conflict do nothing
        returning occurred_at into completion_recorded_at;

        if completion_recorded_at is not null then
            perform public.award_user_score_for_completion(
                requester,
                completion_recorded_at
            );

            perform public.award_villager_completion_pairs(
                session_record.id,
                requester,
                completion_recorded_at
            );
        end if;

        if session_record.mode = 'solo' then
            update public.focus_sessions
            set status = 'completed',
                ended_at = greatest(reconciled_at, planned_end_at)
            where id = session_record.id
                and status = 'live';
        end if;

        completed_count := completed_count + 1;
    end loop;

    return jsonb_build_object(
        'reconciled_at', reconciled_at,
        'completed_sessions', completed_count,
        'cancelled_lobbies', cancelled_lobby_count,
        'left_lobbies', left_lobby_count
    );
end;
$$;

revoke all on function public.create_focus_session(text, integer) from public, anon, authenticated;
revoke all on function public.invite_focus_session_members(uuid, uuid[]) from public, anon, authenticated;
revoke all on function public.join_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.decline_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.start_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.complete_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.cancel_session_lobby(uuid) from public, anon, authenticated;
revoke all on function public.leave_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.interrupt_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.fetch_current_focus_session_detail() from public, anon, authenticated;
revoke all on function public.reconcile_open_focus_sessions() from public, anon, authenticated;

grant execute on function public.create_focus_session(text, integer) to authenticated;
grant execute on function public.invite_focus_session_members(uuid, uuid[]) to authenticated;
grant execute on function public.join_focus_session(uuid) to authenticated;
grant execute on function public.decline_focus_session(uuid) to authenticated;
grant execute on function public.start_focus_session(uuid) to authenticated;
grant execute on function public.complete_focus_session(uuid) to authenticated;
grant execute on function public.cancel_session_lobby(uuid) to authenticated;
grant execute on function public.leave_focus_session(uuid) to authenticated;
grant execute on function public.interrupt_focus_session(uuid) to authenticated;
grant execute on function public.fetch_current_focus_session_detail() to authenticated;
grant execute on function public.reconcile_open_focus_sessions() to authenticated;

notify pgrst, 'reload schema';
