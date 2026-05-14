create or replace function public.leave_focus_session(target_session_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    left_at timestamptz := now();
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
        and status in ('lobby', 'active', 'failed', 'completed', 'cancelled')
    for update;

    if not found then
        raise exception 'No focus session was found.' using errcode = 'P0002';
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
        return public.focus_session_payload(target_session_id);
    end if;

    if session_record.status in ('completed', 'failed', 'cancelled') then
        return public.focus_session_payload(target_session_id);
    end if;

    if session_record.status <> 'lobby' then
        raise exception 'Active focus sessions must be interrupted, not left.' using errcode = '22023';
    end if;

    if membership_record.role = 'host' or session_record.owner_id = requester then
        raise exception 'The host must cancel the focus session instead.' using errcode = '42501';
    end if;

    delete from public.session_members
    where session_id = target_session_id
        and user_id = requester
        and status = 'joined';

    insert into public.session_events (session_id, user_id, event_type, occurred_at)
    values (target_session_id, requester, 'member_left', left_at);

    return public.focus_session_payload(target_session_id);
end;
$$;

drop function if exists public.interrupt_focus_session(uuid);

create function public.interrupt_focus_session(
    target_session_id uuid,
    interruption_reason text default 'interrupted'
)
returns jsonb
security definer
set search_path = public
language plpgsql
as $$
declare
    requester uuid := auth.uid();
    failure_time timestamptz := now();
    normalized_reason text := coalesce(nullif(lower(btrim(interruption_reason)), ''), 'interrupted');
    session_record public.focus_sessions%rowtype;
begin
    if requester is null then
        raise exception 'You must be signed in to interrupt a focus session.' using errcode = '28000';
    end if;

    if normalized_reason not in ('interrupted', 'left_multiplayer') then
        normalized_reason := 'interrupted';
    end if;

    select *
    into session_record
    from public.focus_sessions
    where id = target_session_id
    for update;

    if not found then
        raise exception 'No active focus session was found.' using errcode = 'P0002';
    end if;

    if session_record.status in ('completed', 'failed', 'cancelled') then
        return public.focus_session_payload(target_session_id);
    end if;

    if session_record.status <> 'active' then
        raise exception 'No active focus session was found.' using errcode = 'P0002';
    end if;

    if not exists (
        select 1
        from public.session_members
        where session_id = target_session_id
            and user_id = requester
            and status = 'joined'
            and committed_at is not null
    ) then
        raise exception 'No committed focus session membership was found.' using errcode = 'P0002';
    end if;

    update public.session_members
    set failed_at = coalesce(public.session_members.failed_at, failure_time),
        failure_reason = coalesce(failure_reason, normalized_reason)
    where session_id = target_session_id
        and user_id = requester;

    update public.session_members
    set failed_at = coalesce(public.session_members.failed_at, failure_time),
        failure_reason = coalesce(failure_reason, 'group_failed')
    where session_id = target_session_id
        and committed_at is not null;

    update public.focus_sessions
    set status = 'failed',
        ended_at = failure_time,
        finalized_at = failure_time,
        failed_by_user_id = requester,
        failure_reason = normalized_reason
    where id = target_session_id
        and status = 'active';

    insert into public.session_events (session_id, user_id, event_type, occurred_at)
    values (target_session_id, requester, 'session_failed', failure_time);

    return public.focus_session_payload(target_session_id);
end;
$$;

revoke all on function public.leave_focus_session(uuid) from public, anon, authenticated;
revoke all on function public.interrupt_focus_session(uuid, text) from public, anon, authenticated;

grant execute on function public.leave_focus_session(uuid) to authenticated;
grant execute on function public.interrupt_focus_session(uuid, text) to authenticated;
