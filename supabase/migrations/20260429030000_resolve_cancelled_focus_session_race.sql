update public.session_members
set status = 'left'
from public.focus_sessions
where session_members.session_id = focus_sessions.id
    and focus_sessions.status = 'cancelled'
    and session_members.status in ('invited', 'joined');

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
        raise exception 'No focus session invite was found.' using errcode = 'P0002';
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

create or replace function public.fetch_focus_session_detail(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    session_record public.focus_sessions%rowtype;
    left_membership_count integer := 0;
    payload jsonb;
begin
    if requester is null then
        raise exception 'You must be signed in to view a focus session.' using errcode = '28000';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
    for update;

    if not found then
        raise exception 'No focus session was found.' using errcode = 'P0002';
    end if;

    if session_record.status = 'cancelled' then
        update public.session_members
        set status = 'left'
        where session_id = target_session_id
            and user_id = requester
            and status in ('invited', 'joined');

        get diagnostics left_membership_count = row_count;

        if left_membership_count = 0 and not exists (
            select 1
            from public.session_members
            where session_id = target_session_id
                and user_id = requester
                and status = 'left'
        ) then
            raise exception 'No focus session membership was found.' using errcode = 'P0002';
        end if;

        return public.focus_session_detail_payload(target_session_id);
    end if;

    if not public.is_focus_session_member(target_session_id) then
        raise exception 'No focus session membership was found.' using errcode = 'P0002';
    end if;

    payload := public.focus_session_detail_payload(target_session_id);

    if payload is null then
        raise exception 'No focus session was found.' using errcode = 'P0002';
    end if;

    return payload;
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
    order by
        case focus_sessions.status when 'live' then 0 else 1 end,
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
            and focus_sessions.status = 'live'
            and focus_sessions.planned_end_at <= reconciled_at
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

            completed_count := completed_count + 1;
        elsif not exists (
            select 1
            from public.session_members
            where session_members.session_id = session_record.id
                and session_members.status = 'joined'
                and not exists (
                    select 1
                    from public.session_events
                    where session_events.session_id = session_record.id
                        and session_events.user_id = session_members.user_id
                        and session_events.event_type = 'member_completed'
                )
        ) then
            update public.focus_sessions
            set status = 'completed',
                ended_at = greatest(reconciled_at, planned_end_at)
            where id = session_record.id
                and status = 'live';

            completed_count := completed_count + 1;
        end if;
    end loop;

    return jsonb_build_object(
        'reconciled_at', reconciled_at,
        'completed_sessions', completed_count,
        'cancelled_lobbies', cancelled_lobby_count,
        'left_lobbies', left_lobby_count
    );
end;
$$;

revoke all on function public.join_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.fetch_focus_session_detail(uuid) from public, anon, authenticated;
revoke all on function public.fetch_current_focus_session_detail() from public, anon, authenticated;
revoke all on function public.reconcile_open_focus_sessions() from public, anon, authenticated;

grant execute on function public.join_focus_session(uuid) to authenticated;
grant execute on function public.fetch_focus_session_detail(uuid) to authenticated;
grant execute on function public.fetch_current_focus_session_detail() to authenticated;
grant execute on function public.reconcile_open_focus_sessions() to authenticated;

notify pgrst, 'reload schema';
